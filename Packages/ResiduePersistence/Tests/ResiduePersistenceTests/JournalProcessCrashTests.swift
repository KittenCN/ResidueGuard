import Darwin
import Foundation
import Testing

private enum ProbeError: Error { case unavailable, timeout, earlyExit }

private final class BundleAnchor: NSObject {}

private func probeURL() throws -> URL {
    // SwiftPM places its test bundle and dependency executable in the same build folder.
    let bundle = Bundle(for: BundleAnchor.self)
    let folder = bundle.bundleURL.deletingLastPathComponent()
    let url = folder.appendingPathComponent("JournalCrashProbe")
    guard FileManager.default.isExecutableFile(atPath: url.path) else { throw ProbeError.unavailable }
    return url
}

private func launch(_ mode: String, _ stage: String, _ directory: URL) throws -> Process {
    let process = Process()
    process.executableURL = try probeURL()
    process.arguments = [mode, stage, directory.path]
    try process.run()
    return process
}

private func wait(_ process: Process, until condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(10)
    while !condition() {
        guard process.isRunning else {
            if condition() { return }
            throw ProbeError.earlyExit
        }
        guard Date() < deadline else { throw ProbeError.timeout }
        usleep(10_000)
    }
}

private let crashStages: [String] = {
    let legacy = ["claim", "prepared", "result", "finished", "uncommitted"]
    #if DEBUG
    return legacy + ["audit-claim", "audit-prepared", "audit-result", "audit-finished",
                     "audit-prepare-beforecommit", "audit-result-beforecommit", "migration-beforecommit", "migration-aftercommit", "owned-created", "owned-prepared", "owned-result",
                     "owned-prepare-beforecommit", "owned-result-beforecommit"]
    #else
    return legacy
    #endif
}()

@Test(arguments: crashStages)
func killedWriterRecoversInIndependentVerifier(stage: String) throws {
    let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        .appendingPathComponent("ResidueJournalCrashTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try launch("writer", stage, directory)
    defer { if writer.isRunning { kill(writer.processIdentifier, SIGKILL); writer.waitUntilExit() } }
    try wait(writer) { FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path) }
    #expect(kill(writer.processIdentifier, SIGKILL) == 0)
    writer.waitUntilExit()
    #expect(writer.terminationReason == .uncaughtSignal)
    #expect(writer.terminationStatus == SIGKILL)
    let verifier = try launch("verify", stage, directory)
    defer { if verifier.isRunning { kill(verifier.processIdentifier, SIGKILL); verifier.waitUntilExit() } }
    try wait(verifier) { !verifier.isRunning }
    verifier.waitUntilExit()
    #expect(verifier.terminationReason == .exit)
    #expect(verifier.terminationStatus == 0)
}

import XCTest
import Darwin

#if DEBUG
final class OwnedFixtureCrashIntegrationTests: XCTestCase {
    private func executable() throws -> URL {
        let directory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        return try XCTUnwrap([directory.appendingPathComponent("ResidueOwnedFixtureCrashProbe")].first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }, "SwiftPM must build the DEBUG crash probe alongside tests")
    }
    private func wait(_ process: Process, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if condition() { return true }
            if !process.isRunning { return condition() }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
    private func stopAndReap(_ process: Process) {
        if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
    private func fileBytes(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
            }
        }
        return result
    }
    private func crash(_ phase: String, steps: Int, pending: Bool, source: Bool, effect: String, sidecar: Bool = false) throws {
        let token = UUID()
        // Derive only the fixed test root from the canonical child token, never a caller-supplied path.
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent("ResidueGuard-owned-crash-" + token.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        defer { try? FileManager.default.removeItem(at: owned) }
        let worker = Process(); worker.executableURL = try executable(); worker.arguments = [phase, token.uuidString]
        worker.standardOutput = Pipe(); worker.standardError = Pipe()
        try worker.run()
        defer { stopAndReap(worker) }
        let marker = owned.appendingPathComponent("checkpoint")
        guard wait(worker, until: { (try? String(contentsOf: marker, encoding: .utf8)) == phase }) else {
            XCTFail("worker failed to reach bounded checkpoint \(phase)"); return
        }
        XCTAssertTrue(worker.isRunning)
        XCTAssertEqual(kill(worker.processIdentifier, SIGKILL), 0)
        worker.waitUntilExit()
        XCTAssertEqual(worker.terminationReason, .uncaughtSignal); XCTAssertEqual(worker.terminationStatus, SIGKILL)
        if sidecar {
            let journal = owned.appendingPathComponent("ResidueGuard-VM-VerifiedBackup-" + token.uuidString)
                .appendingPathComponent("owned-fixture-experiment.sqlite-journal")
            XCTAssertTrue(FileManager.default.createFile(atPath: journal.path, contents: Data("synthetic unresolved rollback sidecar".utf8), attributes: [.posixPermissions: 0o600]))
        }
        let before = try fileBytes(owned)
        let verifier = Process(), output = Pipe()
        verifier.executableURL = try executable(); verifier.arguments = ["verify", token.uuidString]
        verifier.standardOutput = output; verifier.standardError = Pipe()
        try verifier.run()
        defer { stopAndReap(verifier) }
        guard wait(verifier, until: { !verifier.isRunning }) else { XCTFail("verifier timeout"); return }
        verifier.waitUntilExit()
        if sidecar {
            XCTAssertEqual(verifier.terminationStatus, 65)
            XCTAssertEqual(try fileBytes(owned), before, "refusal must leave unresolved sidecar and fixture untouched")
            return
        }
        XCTAssertEqual(verifier.terminationStatus, 0)
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["syntheticRuntimeAndBuild"] as? Bool, true)
        XCTAssertEqual(object["authorizesMutation"] as? Bool, false)
        XCTAssertEqual(object["automaticRecovery"] as? Bool, false)
        XCTAssertEqual(object["stepCount"] as? Int, steps)
        XCTAssertEqual(object["pending"] as? Bool, pending)
        XCTAssertEqual(object["source"] as? String, source ? "matches" : "absent")
        XCTAssertEqual(object["quarantine"] as? String, source ? "absent" : "matches")
        XCTAssertEqual(object["lastEffect"] as? String, effect)
        XCTAssertEqual(try fileBytes(owned), before, "independent verifier must not rewrite journal or any fixture")
    }
    func testKillAfterIsolationPrepare() throws { try crash("afterPrepare", steps: 1, pending: true, source: true, effect: "none") }
    func testKillAfterIsolationRenameBeforeResult() throws { try crash("afterIsolateRename", steps: 1, pending: true, source: false, effect: "none") }
    func testKillAfterIsolationResult() throws { try crash("afterIsolationResult", steps: 1, pending: false, source: false, effect: "quarantinedVerified") }
    func testKillAfterRestorePrepare() throws { try crash("afterRestorePrepare", steps: 2, pending: true, source: false, effect: "none") }
    func testKillAfterRestoreRenameBeforeResult() throws { try crash("afterRestoreRename", steps: 2, pending: true, source: true, effect: "none") }
    func testVerifierRefusesRollbackSidecarWithoutRecovery() throws { try crash("afterPrepare", steps: 1, pending: true, source: true, effect: "none", sidecar: true) }

}

#endif

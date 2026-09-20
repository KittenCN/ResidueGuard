import XCTest
import Darwin

#if DEBUG
final class OwnedBootoutCrashIntegrationTests: XCTestCase {
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
    private func crash(_ phase: String, recorded: Bool) throws {
        let token = UUID()
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent("ResidueGuard-owned-crash-" + token.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        defer { try? FileManager.default.removeItem(at: owned) }
        let worker = Process(); worker.executableURL = try executable(); worker.arguments = [phase, token.uuidString]
        worker.standardOutput = Pipe(); worker.standardError = Pipe()
        try worker.run(); defer { stopAndReap(worker) }
        let marker = owned.appendingPathComponent("checkpoint")
        guard wait(worker, until: { (try? String(contentsOf: marker, encoding: .utf8)) == phase }) else {
            XCTFail("worker failed to reach checkpoint"); return
        }
        XCTAssertTrue(worker.isRunning)
        XCTAssertEqual(kill(worker.processIdentifier, SIGKILL), 0)
        worker.waitUntilExit()
        XCTAssertEqual(worker.terminationReason, .uncaughtSignal)
        XCTAssertEqual(worker.terminationStatus, SIGKILL)
        let before = try fileBytes(owned)
        let verifier = Process(), output = Pipe()
        verifier.executableURL = try executable(); verifier.arguments = ["bootoutVerify", token.uuidString]
        verifier.standardOutput = output; verifier.standardError = Pipe()
        try verifier.run(); defer { stopAndReap(verifier) }
        guard wait(verifier, until: { !verifier.isRunning }) else { XCTFail("verifier timeout"); return }
        verifier.waitUntilExit(); XCTAssertEqual(verifier.terminationStatus, 0)
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["syntheticRuntimeAndBuild"] as? Bool, true)
        XCTAssertEqual(object["actualServiceCalls"] as? Int, 0)
        XCTAssertEqual(object["authorizesMutation"] as? Bool, false)
        XCTAssertEqual(object["automaticRecovery"] as? Bool, false)
        let report = try XCTUnwrap(object["report"] as? [String: Any])
        XCTAssertEqual(report["attempt"] as? String, token.uuidString)
        XCTAssertEqual(report["slots"] as? [String], recorded ? ["intent", "outcome"] : ["intent"])
        XCTAssertEqual(report["outcome"] as? String, recorded ? "issuedOutcomeRecorded" : "pendingOutcomeUnknown")
        XCTAssertEqual(report["mayHaveExecuted"] as? String, recorded ? "true" : "unknown")
        XCTAssertEqual(report["postRuntime"] as? String, "unknown")
        XCTAssertEqual(report["absenceProven"] as? Bool, false)
        XCTAssertNil(report["post"])
        XCTAssertEqual(try fileBytes(owned), before, "verifier must preserve every file byte and create nothing")
    }
    func testKillAfterBootoutIntent() throws { try crash("bootoutAfterIntent", recorded: false) }
    func testKillBeforeBootoutOutcome() throws { try crash("bootoutBeforeOutcome", recorded: false) }
    func testKillAfterBootoutOutcome() throws { try crash("bootoutAfterOutcome", recorded: true) }
}
#endif

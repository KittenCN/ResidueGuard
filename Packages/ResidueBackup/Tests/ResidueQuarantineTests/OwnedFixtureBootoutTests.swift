import XCTest
import Foundation
import Darwin
import CryptoKit
@testable import ResidueQuarantine

final class OwnedFixtureBootoutTests: XCTestCase {
    func testCaptureHashesRawInvalidUTF8BeforeDisplayDecoding() {
        let stdout = Data([0xff, 0x61, 0xc0]), stderr = Data([0x80, 0xfe])
        let capture = OwnedBootoutCapture(stdoutData: stdout, stderrData: stderr, exitCode: 15,
            failure: .timedOut, outputTruncated: true, launched: true)
        func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(capture.stdoutSHA256, digest(stdout))
        XCTAssertEqual(capture.stderrSHA256, digest(stderr))
        XCTAssertNotEqual(capture.stdoutSHA256, digest(Data(capture.stdout.utf8)))
        XCTAssertNotEqual(capture.stderrSHA256, digest(Data(capture.stderr.utf8)))
        XCTAssertEqual(capture.failure, .timedOut)
        XCTAssertTrue(capture.outputTruncated)
    }
    func testExactGateRejectsHostRootOtherBuild() {
        XCTAssertTrue(OwnedBootoutGate.accepts(model: "VirtualMac2,1", uid: 501, euid: 501, major: 27, minor: 0, patch: 0, build: "26A428"))
        for (model, uid, euid, major, minor, patch, build) in [
            ("Mac17,2", UInt32(501), UInt32(501), 27, 0, 0, "26A428"),
            ("VirtualMac2,1", 0, 0, 27, 0, 0, "26A428"),
            ("VirtualMac2,1", 501, 0, 27, 0, 0, "26A428"),
            ("VirtualMac2,1", 501, 501, 26, 0, 0, "26A428"),
            ("VirtualMac2,1", 501, 501, 27, 0, 1, "26A428"),
            ("VirtualMac2,1", 501, 501, 27, 0, 0, "future")
        ] { XCTAssertFalse(OwnedBootoutGate.accepts(model: model, uid: uid, euid: euid, major: major, minor: minor, patch: patch, build: build)) }
    }
    func testExclusiveDurableLogRejectsRewriteAndSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RG-Bootout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW); XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        let attempt = UUID()
        let log = try OwnedBootoutLog(directoryFD: fd, attempt: attempt)
        try log.append(.intent, ["attempt": attempt.uuidString, "authorizesReplay": "false"])
        let reopened = try OwnedBootoutLog(directoryFD: fd, attempt: attempt, readOnly: true)
        XCTAssertNotNil(try reopened.readAll()[.intent])
        XCTAssertThrowsError(try reopened.append(.outcome, ["forbidden": "readOnly"]))
        let wrongAttempt = try OwnedBootoutLog(directoryFD: fd, attempt: UUID())
        XCTAssertThrowsError(try wrongAttempt.readAll())
        let before = try Data(contentsOf: root.appendingPathComponent("owned-bootout-intent.json"))
        XCTAssertThrowsError(try log.append(.intent, ["overwrite": "forbidden"]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("owned-bootout-intent.json")), before)
        XCTAssertEqual(symlinkat("owned-bootout-intent.json", fd, "owned-bootout-outcome.json"), 0)
        XCTAssertThrowsError(try log.append(.outcome, ["overwrite": "forbidden"]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("owned-bootout-intent.json")), before)
    }
    private static func successfulCapture() -> OwnedBootoutCapture {
        .init(stdout: "", stderr: "", exitCode: 0, failure: nil, outputTruncated: false, launched: true)
    }
    func testPrepareFailureNeverCallsFreshIssueOrRecord() async {
        do {
            _ = try await OwnedBootoutSequence.execute(prepare: { throw OwnedBootoutError.storage }, fresh: { XCTFail() },
                issue: { XCTFail(); return Self.successfulCapture() }, record: { _ in XCTFail() })
            XCTFail()
        } catch {}
    }
    func testFreshFailureRecordsNotIssuedWithoutCallingCommand() async {
        var recorded = false
        do {
            _ = try await OwnedBootoutSequence.execute(prepare: {}, fresh: { throw OwnedBootoutError.changed },
                issue: { XCTFail(); return Self.successfulCapture() }, record: { capture in XCTAssertNil(capture); recorded = true })
            XCTFail()
        } catch {}
        XCTAssertTrue(recorded)
    }
    func testCancellationAfterFreshNeverIssues() async {
        let task = Task {
            var recorded = false
            do {
                _ = try await OwnedBootoutSequence.execute(prepare: {}, fresh: { withUnsafeCurrentTask { $0?.cancel() } },
                    issue: { XCTFail(); return Self.successfulCapture() }, record: { capture in XCTAssertNil(capture); recorded = true })
                XCTFail()
            } catch {}
            return recorded
        }
        let recorded = await task.value
        XCTAssertTrue(recorded)
    }
    func testIssuedTimeoutIsRecordedThenStops() async {
        var issues = 0, recorded = false
        do {
            _ = try await OwnedBootoutSequence.execute(prepare: {}, fresh: {}, issue: {
                issues += 1
                return .init(stdout: "", stderr: "", exitCode: 15, failure: .timedOut, outputTruncated: false, launched: true)
            }, record: { capture in XCTAssertEqual(capture?.failure, .timedOut); XCTAssertEqual(capture?.launched, true); recorded = true })
            XCTFail()
        } catch {}
        XCTAssertEqual(issues, 1); XCTAssertTrue(recorded)
    }
    func testOutcomeWriteFailureStopsAfterSingleIssue() async {
        var issues = 0
        do {
            _ = try await OwnedBootoutSequence.execute(prepare: {}, fresh: {}, issue: { issues += 1; return Self.successfulCapture() },
                record: { _ in throw OwnedBootoutError.storage })
            XCTFail()
        } catch {}
        XCTAssertEqual(issues, 1)
    }
    func testNonzeroExitIsRecordedWithoutRetry() async {
        var issues = 0, recorded = false
        do {
            _ = try await OwnedBootoutSequence.execute(prepare: {}, fresh: {}, issue: {
                issues += 1
                return .init(stdout: "", stderr: "fixture rejection", exitCode: 5, failure: nil, outputTruncated: false, launched: true)
            }, record: { capture in XCTAssertEqual(capture?.exitCode, 5); recorded = true })
            XCTFail()
        } catch {}
        XCTAssertEqual(issues, 1); XCTAssertTrue(recorded)
    }
    func testSuccessfulSequenceHasDurableOrdering() async throws {
        var events: [String] = []
        _ = try await OwnedBootoutSequence.execute(prepare: { events.append("intent") }, fresh: { events.append("fresh") },
            issue: { events.append("issue"); return Self.successfulCapture() }, record: { _ in events.append("outcome") })
        XCTAssertEqual(events, ["intent", "fresh", "issue", "outcome"])
    }
    private func withLog(_ body: (URL, Int32, OwnedBootoutLog) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RG-Bootout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW); defer { close(fd) }
        let log = try OwnedBootoutLog(directoryFD: fd)
        try log.append(.intent, ["fixture": "not authority"])
        try body(root, fd, log)
    }
    func testReaderRejectsWrongSlotAndPreservesFiles() throws {
        try withLog { root, _, log in
            let bytes = try Data(contentsOf: root.appendingPathComponent("owned-bootout-intent.json"))
            let other = root.appendingPathComponent("owned-bootout-outcome.json")
            try bytes.write(to: other)
            XCTAssertEqual(chmod(other.path, 0o600), 0)
            XCTAssertThrowsError(try log.readAll())
            XCTAssertEqual(try Data(contentsOf: other), bytes)
        }
    }
    func testReaderRejectsCorruptionAndHardlink() throws {
        try withLog { root, fd, log in
            XCTAssertEqual(linkat(fd, "owned-bootout-intent.json", fd, "extra", 0), 0)
            XCTAssertThrowsError(try log.readAll())
            XCTAssertEqual(unlinkat(fd, "extra", 0), 0)
            let file = root.appendingPathComponent("owned-bootout-intent.json")
            var bytes = try Data(contentsOf: file); bytes.removeLast()
            try bytes.write(to: file)
            XCTAssertThrowsError(try log.readAll())
        }
    }
    func testReaderRejectsRootFlagsAndReplacement() throws {
        try withLog { root, fd, log in
            XCTAssertEqual(fchflags(fd, UInt32(UF_HIDDEN)), 0)
            XCTAssertThrowsError(try log.readAll())
            XCTAssertEqual(fchflags(fd, 0), 0)
            let moved = root.appendingPathExtension("moved")
            try FileManager.default.moveItem(at: root, to: moved)
            defer { try? FileManager.default.removeItem(at: moved) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            XCTAssertThrowsError(try log.readAll())
        }
    }
}

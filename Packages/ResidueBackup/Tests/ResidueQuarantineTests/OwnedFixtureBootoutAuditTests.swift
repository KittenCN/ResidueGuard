import XCTest
import Foundation
import Darwin
@testable import ResidueQuarantine

final class OwnedFixtureBootoutAuditTests: XCTestCase {
    private struct Intent: Encodable {
        let version = 1, profile = "owned-iso01-bootout-v1", authorizesReplay = false
        let attempt: UUID
    }
    private func fixture(_ body: (URL, Int32, UUID, OwnedBootoutLog) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RG-BootoutAudit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW); defer { close(fd) }
        let attempt = UUID(), log = try OwnedBootoutLog(directoryFD: fd, attempt: attempt)
        try body(root, fd, attempt, log)
    }
    func testAbsentAndPendingAreDistinctAndReadDoesNotWrite() throws {
        try fixture { root, fd, attempt, log in
            XCTAssertNil(try OwnedBootoutAuditReader.read(directoryFD: fd))
            try log.append(.intent, Intent(attempt: attempt))
            let file = root.appendingPathComponent("owned-bootout-intent.json")
            let before = try Data(contentsOf: file)
            let report = try XCTUnwrap(OwnedBootoutAuditReader.read(directoryFD: fd))
            XCTAssertEqual(report.attempt, attempt)
            XCTAssertEqual(report.outcome, "pendingOutcomeUnknown")
            XCTAssertEqual(report.mayHaveExecuted, "unknown")
            XCTAssertFalse(report.authorizesMutation)
            XCTAssertEqual(try Data(contentsOf: file), before)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["owned-bootout-intent.json"])
        }
    }
    func testIssuedCaptureAndPostRemainHistoricalUnknown() throws {
        try fixture { _, fd, attempt, log in
            try log.append(.intent, Intent(attempt: attempt))
            let capture = OwnedBootoutCapture(stdout: "private fixture path", stderr: "", exitCode: 0, failure: nil,
                                               outputTruncated: false, launched: true)
            try log.append(.outcome, OwnedBootoutOutcome(attempt: attempt, observedAt: Date(), disposition: "issuedOutcomeRecorded", capture: capture))
            try log.append(.observation, OwnedBootoutPostObservation(attempt: attempt, observedAt: Date(), runtime: nil,
                                                                    capture: capture, filesStillMatch: true))
            let report = try XCTUnwrap(OwnedBootoutAuditReader.read(directoryFD: fd))
            XCTAssertEqual(report.postRuntime, "unknown")
            XCTAssertEqual(report.postFileMatchesHistory, true)
            XCTAssertFalse(report.absenceProven); XCTAssertFalse(report.freshFilesInspected)
            XCTAssertEqual(report.command?.exitCode, 0)
            XCTAssertEqual(report.post?.textClassification, "unparsedDiagnostic")
            XCTAssertEqual(report.post?.stdoutSHA256, capture.stdoutSHA256)
            XCTAssertEqual(report.command?.launched, true)
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(report), as: UTF8.self).contains("private fixture path"))
        }
    }
    func testOrphanedSlotsAndInconsistentOutcomeAreRejected() throws {
        try fixture { root, fd, attempt, log in
            try log.append(.intent, Intent(attempt: attempt))
            try log.append(.outcome, OwnedBootoutOutcome(attempt: attempt, observedAt: Date(), disposition: "issuedOutcomeRecorded", capture: nil))
            XCTAssertThrowsError(try OwnedBootoutAuditReader.read(directoryFD: fd))
            try FileManager.default.removeItem(at: root.appendingPathComponent("owned-bootout-intent.json"))
            XCTAssertThrowsError(try OwnedBootoutAuditReader.read(directoryFD: fd))
        }
    }
    func testCaptureSummaryPreservesFailureAndRejectsUnsafeDigest() throws {
        let capture = OwnedBootoutCapture(stdout: "", stderr: "private message", exitCode: 15, failure: .timedOut,
                                           outputTruncated: true, launched: true)
        let summary = try OwnedBootoutAuditCaptureSummary(capture)
        XCTAssertEqual(summary.failure, "timedOut"); XCTAssertEqual(summary.exitCode, 15)
        XCTAssertTrue(summary.outputTruncated); XCTAssertTrue(summary.launched)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as? [String: Any])
        object["stdoutSHA256"] = "/private/untrusted/path"
        let altered = try JSONDecoder().decode(OwnedBootoutCapture.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try OwnedBootoutAuditCaptureSummary(altered))
    }
}

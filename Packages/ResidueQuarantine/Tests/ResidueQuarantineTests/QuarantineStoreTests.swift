import XCTest
import Darwin
@testable import ResidueBackup
@testable import ResidueQuarantine

final class QuarantineStoreTests: XCTestCase {
    struct Lab {
        let store: QuarantineStore
        let receipt: BackupReceipt
        let source: URL
        let quarantine: URL
        let backup: URL
        var original: URL { source.appendingPathComponent("fixture.plist") }
        var isolated: URL { quarantine.appendingPathComponent(receipt.id.uuidString + ".plist") }
    }
    func fixture(configure: ((URL) throws -> Void)? = nil, _ body: (Lab) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), backup = root.appendingPathComponent("backup"), quarantine = root.appendingPathComponent("quarantine")
        for url in [source, backup, quarantine] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let a = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), b = open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), c = open(quarantine.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        defer { close(a); close(b); close(c) }
        XCTAssertTrue(FileManager.default.createFile(atPath: source.appendingPathComponent("fixture.plist").path, contents: Data("<plist><dict/></plist>".utf8), attributes: [.posixPermissions: 0o600]))
        try configure?(source.appendingPathComponent("fixture.plist"))
        let backupStore = try VerifiedBackup(testSourceFD: a, testDestinationFD: b)
        let receipt = try backupStore.prepare(name: "fixture.plist", expected: backupStore.inspect(name: "fixture.plist"), planID: UUID())
        let store = try QuarantineStore(testSourceFD: a, testQuarantineFD: c, backup: backupStore)
        try body(Lab(store: store, receipt: receipt, source: source, quarantine: quarantine, backup: backup))
    }
    func testRoundTripPreservesInodeBytesAndMode() throws { try fixture { lab in
        let bytes = try Data(contentsOf: lab.original)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lab.original.path))
        XCTAssertEqual(try Data(contentsOf: lab.isolated), bytes)
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).state, .restoredVerified)
        XCTAssertEqual(try Data(contentsOf: lab.original), bytes)
        var info = stat(); XCTAssertEqual(lstat(lab.original.path, &info), 0)
        XCTAssertEqual(info.st_ino, lab.receipt.fingerprint.inode)
        XCTAssertEqual(info.st_mode, lab.receipt.fingerprint.mode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testWrongPlanRejected() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: UUID()).reason, .invalidPlan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.original.path))
    } }
    func testSourceReplacementRejected() throws { try fixture { lab in
        try FileManager.default.moveItem(at: lab.original, to: lab.source.appendingPathComponent("old.plist"))
        try Data("replacement".utf8).write(to: lab.original)
        let result = lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(result.state, .notMoved); XCTAssertEqual(result.reason, .sourceInvalid)
    } }
    func testSourceSymlinkRejected() throws { try fixture { lab in
        try FileManager.default.moveItem(at: lab.original, to: lab.source.appendingPathComponent("old.plist"))
        XCTAssertEqual(symlink("old.plist", lab.original.path), 0)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .notMoved)
    } }
    func testSourceHardlinkRejected() throws { try fixture { lab in
        XCTAssertEqual(link(lab.original.path, lab.source.appendingPathComponent("extra.plist").path), 0)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .notMoved)
    } }
    func testQuarantineConflictNotOverwritten() throws { try fixture { lab in
        try Data("conflict".utf8).write(to: lab.isolated)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).reason, .conflict)
        XCTAssertEqual(try Data(contentsOf: lab.isolated), Data("conflict".utf8))
    } }
    func testDanglingRestoreSymlinkConflict() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        XCTAssertEqual(symlink("missing.plist", lab.original.path), 0)
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).reason, .conflict)
        var info = stat(); XCTAssertEqual(lstat(lab.original.path, &info), 0); XCTAssertEqual(info.st_mode & S_IFMT, S_IFLNK)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testTamperedBackupBlocksIsolation() throws { try fixture { lab in
        try Data("tampered".utf8).write(to: lab.backup.appendingPathComponent(lab.receipt.id.uuidString).appendingPathComponent("source.plist"))
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).reason, .backupInvalid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.original.path))
    } }
    func testTamperedBackupBlocksRestore() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        try Data("tampered".utf8).write(to: lab.backup.appendingPathComponent(lab.receipt.id.uuidString).appendingPathComponent("manifest.json"))
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).reason, .backupInvalid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testQuarantinedContentTamperBlocksRestore() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        try Data("tampered".utf8).write(to: lab.isolated)
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).reason, .sourceInvalid)
    } }
    func testDestinationRaceIsExclusive() throws { try fixture { lab in
        lab.store.beforeRenameForTesting = { try Data("raced".utf8).write(to: lab.isolated) }
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).reason, .conflict)
        XCTAssertEqual(try Data(contentsOf: lab.isolated), Data("raced".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.original.path))
    } }
    func testSourceRaceReportsMovedUnverifiedWithoutDeleting() throws { try fixture { lab in
        lab.store.beforeRenameForTesting = {
            try FileManager.default.moveItem(at: lab.original, to: lab.source.appendingPathComponent("retained.plist"))
            XCTAssertTrue(FileManager.default.createFile(atPath: lab.original.path, contents: Data("unexpected".utf8), attributes: [.posixPermissions: 0o600]))
        }
        let result = lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(result.state, .movedUnverified)
        XCTAssertEqual(try Data(contentsOf: lab.isolated), Data("unexpected".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.source.appendingPathComponent("retained.plist").path))
    } }
    func testPostMoveFailureNeverReportsSuccessOrCompensates() throws { try fixture { lab in
        lab.store.afterRenameForTesting = { throw CocoaError(.fileWriteUnknown) }
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .movedUnverified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lab.original.path))
    } }
    func testUnsafeQuarantineModeBlocks() throws { try fixture { lab in
        XCTAssertEqual(chmod(lab.quarantine.path, 0o755), 0)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).reason, .unsafeDirectory)
    } }
    func testSourceMissingRejected() throws { try fixture { lab in
        try FileManager.default.moveItem(at: lab.original, to: lab.source.appendingPathComponent("retained.plist"))
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).reason, .sourceInvalid)
    } }
    func testRepeatedIsolationDoesNotRepeatMutation() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .notMoved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testExtendedAttributesPreservedAcrossRoundTrip() throws {
        let value = Data([0, 1, 2, 255])
        try fixture(configure: { path in
            XCTAssertEqual(value.withUnsafeBytes { setxattr(path.path, "example.residueguard.test", $0.baseAddress, $0.count, 0, 0) }, 0)
        }) { lab in
            XCTAssertEqual(lab.receipt.fingerprint.extendedAttributes["example.residueguard.test"], value)
            XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
            XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).state, .restoredVerified)
            var bytes = Data(count: 4)
            XCTAssertEqual(bytes.withUnsafeMutableBytes { getxattr(lab.original.path, "example.residueguard.test", $0.baseAddress, 4, 0, 0) }, 4)
            XCTAssertEqual(bytes, value)
        }
    }
    func addACL(_ path: String) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow read", path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    func testQuarantineACLRejected() throws { try fixture { lab in
        try addACL(lab.quarantine.path)
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).reason, .unsafeDirectory)
    } }
    func testQuarantinedACLBlocksRestore() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        try addACL(lab.isolated.path)
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).reason, .sourceInvalid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testRestoreDestinationRaceNeverOverwrites() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        lab.store.beforeRenameForTesting = { try Data("new version".utf8).write(to: lab.original) }
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).reason, .conflict)
        XCTAssertEqual(try Data(contentsOf: lab.original), Data("new version".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }

    func testInspectionOfOriginalNeverMovesOrAuthorizes() throws { try fixture { lab in
        lab.store.beforeRenameForTesting = { XCTFail("inspection must never enter rename") }
        lab.store.afterRenameForTesting = { XCTFail("inspection must never enter rename") }
        let before = try FileManager.default.contentsOfDirectory(atPath: lab.source.path)
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .sourcePresentNoMoveRequired)
        XCTAssertEqual(report.source, .matchesReceipt); XCTAssertEqual(report.quarantined, .absent)
        XCTAssertTrue(report.backupVerified); XCTAssertFalse(report.permitsMutation); XCTAssertFalse(report.runtimeInspected)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: lab.source.path), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testInspectionOfQuarantinedIsCandidateOnly() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .restoreCandidateRequiresNewPlan)
        XCTAssertFalse(report.permitsMutation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lab.original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.isolated.path))
    } }
    func testInspectionAfterRestorationAllowsChangedCtime() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        XCTAssertEqual(lab.store.restore(receipt: lab.receipt, planID: lab.receipt.planID).state, .restoredVerified)
        XCTAssertEqual(lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID).decision, .sourcePresentNoMoveRequired)
    } }
    func testInspectionRejectsWrongPlan() throws { try fixture { lab in
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: UUID())
        XCTAssertEqual(report.decision, .invalidPlan); XCTAssertFalse(report.backupVerified)
    } }
    func testInspectionDetectsBothMissingWithoutRestoringBackup() throws { try fixture { lab in
        try FileManager.default.moveItem(at: lab.original, to: lab.source.appendingPathComponent("retained.plist"))
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .objectsMissing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lab.original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lab.source.appendingPathComponent("retained.plist").path))
    } }
    func testInspectionDetectsTwoLocationsConflict() throws { try fixture { lab in
        try Data("unrelated".utf8).write(to: lab.isolated)
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .conflict); XCTAssertEqual(report.quarantined, .conflict)
        XCTAssertEqual(try Data(contentsOf: lab.isolated), Data("unrelated".utf8))
    } }
    func testInspectionDetectsDanglingSourceConflict() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        XCTAssertEqual(symlink("missing", lab.original.path), 0)
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .conflict); XCTAssertEqual(report.source, .conflict)
    } }
    func testInspectionRejectsTamperedBackup() throws { try fixture { lab in
        try Data("tampered".utf8).write(to: lab.backup.appendingPathComponent(lab.receipt.id.uuidString).appendingPathComponent("manifest.json"))
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .invalidBackup); XCTAssertFalse(report.backupVerified)
    } }
    func testInspectionRejectsUnsafeStorage() throws { try fixture { lab in
        XCTAssertEqual(chmod(lab.quarantine.path, 0o755), 0)
        XCTAssertEqual(lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID).decision, .unsafeStorage)
    } }
    func testInspectionMarksUnreadableUnsafeMetadataUnverified() throws { try fixture { lab in
        XCTAssertEqual(lab.store.isolate(receipt: lab.receipt, planID: lab.receipt.planID).state, .quarantinedVerified)
        try addACL(lab.isolated.path)
        let report = lab.store.inspectRecovery(receipt: lab.receipt, planID: lab.receipt.planID)
        XCTAssertEqual(report.decision, .unverified); XCTAssertEqual(report.quarantined, .unverified)
    } }

}

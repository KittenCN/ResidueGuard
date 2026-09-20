import XCTest
import CryptoKit
import Darwin
@testable import ResidueBackup

final class BackupAuditEvidenceTests: XCTestCase {
    struct Fixture {
        let store: VerifiedBackup
        let receipt: BackupReceipt
        let root: URL
        let backup: URL
        let rootID: UUID
        let sourceFD: Int32
        let backupFD: Int32
        let parentFD: Int32
        var directory: URL { backup.appendingPathComponent(receipt.id.uuidString) }
        var manifest: URL { directory.appendingPathComponent("manifest.json") }
        var content: URL { directory.appendingPathComponent("source.plist") }
    }
    func fixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), backup = root.appendingPathComponent("backup")
        for url in [source, backup] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let a = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), b = open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), p = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        defer { close(a); close(b); close(p) }
        XCTAssertTrue(FileManager.default.createFile(atPath: source.appendingPathComponent("fixture.plist").path, contents: Data("<plist><dict/></plist>".utf8), attributes: [.posixPermissions: 0o600]))
        let store = try VerifiedBackup(testSourceFD: a, testDestinationFD: b), rootID = UUID()
        try store.bindAuditRootForTesting(parentFD: p, name: "backup", id: rootID)
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        try body(Fixture(store: store, receipt: receipt, root: root, backup: backup, rootID: rootID, sourceFD: a, backupFD: b, parentFD: p))
    }
    func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func replaceWithSameBytes(_ path: URL) throws {
        let bytes = try Data(contentsOf: path)
        try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("retained"))
        XCTAssertTrue(FileManager.default.createFile(atPath: path.path, contents: bytes, attributes: [.posixPermissions: 0o600]))
    }
    func testEvidenceBindsActualBytesMetadataAndPrivateRoot() throws { try fixture { f in
        let evidence = try f.store.inspectAuditEvidence(receipt: f.receipt)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(evidence.backupID, f.receipt.id); XCTAssertEqual(evidence.planID, f.receipt.planID)
        XCTAssertEqual(evidence.manifestSHA256, hash(try Data(contentsOf: f.manifest)))
        XCTAssertEqual(evidence.contentSHA256, hash(try Data(contentsOf: f.content)))
        XCTAssertEqual(evidence.metadataSHA256, hash(try encoder.encode(f.receipt.fingerprint)))
        XCTAssertEqual(evidence.root.namespace, .temporaryFixture); XCTAssertEqual(evidence.root.rootID, f.rootID)
        XCTAssertEqual(evidence.root.directoryName, "backup"); XCTAssertEqual(evidence.root.owner, getuid())
        XCTAssertFalse(evidence.authorizesMutation)
    } }
    func testAlteredPlanReceiptRejected() throws { try fixture { f in
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.receipt)) as? [String: Any])
        object["planID"] = UUID().uuidString
        let forged = try JSONDecoder().decode(BackupReceipt.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: forged))
    } }
    func testReceiptFromAnotherStoreNotAcceptedAsIssuedEvidence() throws { try fixture { f in
        let second = try VerifiedBackup(testSourceFD: f.sourceFD, testDestinationFD: f.backupFD)
        try second.bindAuditRootForTesting(parentFD: f.parentFD, name: "backup", id: f.rootID)
        try second.verify(f.receipt) // Content verification alone is deliberately insufficient for issuing audit evidence.
        XCTAssertThrowsError(try second.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testSameBytesManifestReplacementRejected() throws { try fixture { f in
        try replaceWithSameBytes(f.manifest)
        try f.store.verify(f.receipt)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testSameBytesContentReplacementRejected() throws { try fixture { f in
        try replaceWithSameBytes(f.content)
        try f.store.verify(f.receipt)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testManifestSymlinkRejected() throws { try fixture { f in
        let retained = f.manifest.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: f.manifest, to: retained)
        XCTAssertEqual(symlink(retained.lastPathComponent, f.manifest.path), 0)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testContentHardlinkRejected() throws { try fixture { f in
        XCTAssertEqual(link(f.content.path, f.root.appendingPathComponent("linked.plist").path), 0)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testRootDirectoryReplacementRejected() throws { try fixture { f in
        let retained = f.root.appendingPathComponent("retained-backup")
        try FileManager.default.moveItem(at: f.backup, to: retained)
        try FileManager.default.createDirectory(at: f.backup, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.appendingPathComponent(f.receipt.id.uuidString).path))
    } }
    func testRootSymlinkRejected() throws { try fixture { f in
        let retained = f.root.appendingPathComponent("retained-backup")
        try FileManager.default.moveItem(at: f.backup, to: retained)
        XCTAssertEqual(symlink("retained-backup", f.backup.path), 0)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testBackupSubdirectoryReplacementRejected() throws { try fixture { f in
        let retained = f.backup.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: f.directory, to: retained)
        try FileManager.default.createDirectory(at: f.directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for name in ["manifest.json", "source.plist"] {
            try FileManager.default.copyItem(at: retained.appendingPathComponent(name), to: f.directory.appendingPathComponent(name))
        }
        try f.store.verify(f.receipt)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testMetadataMutationRejectedWithoutDroppingIt() throws { try fixture { f in
        let bytes = [UInt8]("changed".utf8)
        XCTAssertEqual(bytes.withUnsafeBytes { setxattr(f.content.path, "example.residueguard.changed", $0.baseAddress, $0.count, 0, 0) }, 0)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
        XCTAssertGreaterThan(getxattr(f.content.path, "example.residueguard.changed", nil, 0, 0, 0), 0)
    } }
    func testUnboundStoreCannotEmitEvidence() throws { try fixture { f in
        let unbound = try VerifiedBackup(testSourceFD: f.sourceFD, testDestinationFD: f.backupFD)
        let receipt = try unbound.prepare(name: "fixture.plist", expected: unbound.inspect(name: "fixture.plist"), planID: UUID())
        XCTAssertThrowsError(try unbound.inspectAuditEvidence(receipt: receipt))
    } }
    func testUnrelatedSiblingDoesNotInvalidateRootIdentity() throws { try fixture { f in
        try FileManager.default.createDirectory(at: f.backup.appendingPathComponent("quarantine"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        XCTAssertNoThrow(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testContentTamperingRejected() throws { try fixture { f in
        try Data("tampered content".utf8).write(to: f.content)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testRootPermissionWideningRejected() throws { try fixture { f in
        XCTAssertEqual(chmod(f.backup.path, 0o755), 0)
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }

    func setACL(_ text: String, at path: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", text, path.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    func clearACL(at path: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["-N", path.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    func testParentDenyDeleteACLAcceptedForBindingAndEvidence() throws { try fixture { f in
        try setACL("everyone deny delete", at: f.root)
        defer { try? clearACL(at: f.root) }
        let second = try VerifiedBackup(testSourceFD: f.sourceFD, testDestinationFD: f.backupFD)
        try second.bindAuditRootForTesting(parentFD: f.parentFD, name: "backup", id: f.rootID)
        let receipt = try second.prepare(name: "fixture.plist", expected: second.inspect(name: "fixture.plist"), planID: UUID())
        XCTAssertNoThrow(try second.inspectAuditEvidence(receipt: receipt))
        XCTAssertNoThrow(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testParentAllowACLRejected() throws { try fixture { f in
        try setACL("everyone allow readattr", at: f.root)
        defer { try? clearACL(at: f.root) }
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
        let second = try VerifiedBackup(testSourceFD: f.sourceFD, testDestinationFD: f.backupFD)
        XCTAssertThrowsError(try second.bindAuditRootForTesting(parentFD: f.parentFD, name: "backup", id: f.rootID))
    } }
    func testParentOtherDenyPermissionRejected() throws { try fixture { f in
        try setACL("everyone deny writeattr", at: f.root)
        defer { try? clearACL(at: f.root) }
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testParentInheritingDenyDeleteRejected() throws { try fixture { f in
        try setACL("everyone deny delete,directory_inherit", at: f.root)
        defer { try? clearACL(at: f.root) }
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testBackupRootDenyDeleteStillRejected() throws { try fixture { f in
        try setACL("everyone deny delete", at: f.backup)
        defer { try? clearACL(at: f.backup) }
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }

    func testParentHiddenAndDenyDeleteAcceptedForBindingAndEvidence() throws { try fixture { f in
        XCTAssertEqual(chflags(f.root.path, UInt32(UF_HIDDEN)), 0)
        try setACL("everyone deny delete", at: f.root)
        defer { _ = chflags(f.root.path, 0); try? clearACL(at: f.root) }
        let second = try VerifiedBackup(testSourceFD: f.sourceFD, testDestinationFD: f.backupFD)
        try second.bindAuditRootForTesting(parentFD: f.parentFD, name: "backup", id: f.rootID)
        let receipt = try second.prepare(name: "fixture.plist", expected: second.inspect(name: "fixture.plist"), planID: UUID())
        XCTAssertNoThrow(try second.inspectAuditEvidence(receipt: receipt))
        XCTAssertNoThrow(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testBackupRootHiddenFlagRejected() throws { try fixture { f in
        XCTAssertEqual(chflags(f.backup.path, UInt32(UF_HIDDEN)), 0)
        defer { _ = chflags(f.backup.path, 0) }
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
    } }
    func testParentOtherFlagRejected() throws { try fixture { f in
        XCTAssertEqual(chflags(f.root.path, UInt32(UF_HIDDEN | UF_NODUMP)), 0)
        defer { _ = chflags(f.root.path, 0) }
        XCTAssertThrowsError(try f.store.inspectAuditEvidence(receipt: f.receipt))
        let second = try VerifiedBackup(testSourceFD: f.sourceFD, testDestinationFD: f.backupFD)
        XCTAssertThrowsError(try second.bindAuditRootForTesting(parentFD: f.parentFD, name: "backup", id: f.rootID))
    } }

}

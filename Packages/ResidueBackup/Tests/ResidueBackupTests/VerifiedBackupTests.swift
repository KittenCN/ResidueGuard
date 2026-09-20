import XCTest
import Darwin
@testable import ResidueBackup

final class VerifiedBackupTests: XCTestCase {
    func fixture(_ body: (VerifiedBackup, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), backup = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let a = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), b = open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        defer { close(a); close(b) }
        let file = source.appendingPathComponent("fixture.plist")
        FileManager.default.createFile(atPath: file.path, contents: Data("<plist><dict/></plist>".utf8), attributes: [.posixPermissions: 0o600])
        try body(VerifiedBackup(testSourceFD: a, testDestinationFD: b), source, backup)
    }
    func testRoundTripAndSourceUnchanged() throws { try fixture { store, source, backup in
        let before = try store.inspect(name: "fixture.plist")
        let receipt = try store.prepare(name: "fixture.plist", expected: before, planID: UUID())
        try store.verify(receipt)
        XCTAssertEqual(try store.inspect(name: "fixture.plist"), before)
        XCTAssertEqual(receipt.runtimeState, "notInspected")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("fixture.plist").path))
        let path = backup.appendingPathComponent(receipt.id.uuidString).appendingPathComponent("source.plist").path
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    } }
    func testChangedSourceRejected() throws { try fixture { store, source, _ in
        let before = try store.inspect(name: "fixture.plist")
        try Data("changed".utf8).write(to: source.appendingPathComponent("fixture.plist"))
        XCTAssertThrowsError(try store.prepare(name: "fixture.plist", expected: before, planID: UUID()))
    } }
    func testTraversalRejected() throws { try fixture { store, _, _ in
        for name in ["../fixture.plist", "/fixture.plist", "x\0.plist", "fixture", ".plist"] { XCTAssertThrowsError(try store.inspect(name: name)) }
    } }
    func testSymlinkRejected() throws { try fixture { store, source, _ in
        XCTAssertEqual(symlink("fixture.plist", source.appendingPathComponent("link.plist").path), 0)
        XCTAssertThrowsError(try store.inspect(name: "link.plist"))
    } }
    func testHardlinkRejected() throws { try fixture { store, source, _ in
        XCTAssertEqual(link(source.appendingPathComponent("fixture.plist").path, source.appendingPathComponent("link.plist").path), 0)
        XCTAssertThrowsError(try store.inspect(name: "fixture.plist"))
    } }
    func testUnsafeModesRejected() throws { try fixture { store, source, _ in
        XCTAssertEqual(chmod(source.appendingPathComponent("fixture.plist").path, 0o666), 0)
        XCTAssertThrowsError(try store.inspect(name: "fixture.plist"))
    } }
    func testExtendedAttributesPreservedInManifest() throws { try fixture { store, source, _ in
        let bytes = [UInt8]("test".utf8)
        XCTAssertEqual(bytes.withUnsafeBytes { setxattr(source.appendingPathComponent("fixture.plist").path, "example.residueguard.fixture", $0.baseAddress, $0.count, 0, 0) }, 0)
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        XCTAssertEqual(receipt.fingerprint.extendedAttributes["example.residueguard.fixture"], Data(bytes))
        try store.verify(receipt)
    } }
    func testOversizedRejected() throws { try fixture { store, source, _ in
        try Data(repeating: 1, count: 1_048_577).write(to: source.appendingPathComponent("fixture.plist"))
        XCTAssertThrowsError(try store.inspect(name: "fixture.plist"))
    } }
    func testBackupTamperingRejected() throws { try fixture { store, _, backup in
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        try Data("tampered".utf8).write(to: backup.appendingPathComponent(receipt.id.uuidString).appendingPathComponent("source.plist"))
        XCTAssertThrowsError(try store.verify(receipt))
    } }
    func testManifestTamperingRejected() throws { try fixture { store, _, backup in
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        try Data("{}".utf8).write(to: backup.appendingPathComponent(receipt.id.uuidString).appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try store.verify(receipt))
    } }
    func testDestinationModeChangeRejected() throws { try fixture { store, _, backup in
        let expected = try store.inspect(name: "fixture.plist")
        XCTAssertEqual(chmod(backup.path, 0o755), 0)
        XCTAssertThrowsError(try store.prepare(name: "fixture.plist", expected: expected, planID: UUID()))
    } }
    func testFIFORejectedWithoutBlocking() throws { try fixture { store, source, _ in
        XCTAssertEqual(mkfifo(source.appendingPathComponent("fifo.plist").path, 0o600), 0)
        XCTAssertThrowsError(try store.inspect(name: "fifo.plist"))
    } }
    func addACL(_ path: String) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "everyone allow read", path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    func testSourceACLRejected() throws { try fixture { store, source, _ in
        try addACL(source.appendingPathComponent("fixture.plist").path)
        XCTAssertThrowsError(try store.inspect(name: "fixture.plist"))
    } }
    func testBackupACLRejected() throws { try fixture { store, _, backup in
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        try addACL(backup.appendingPathComponent(receipt.id.uuidString).appendingPathComponent("source.plist").path)
        XCTAssertThrowsError(try store.verify(receipt))
    } }
    func testBackupHardlinkRejected() throws { try fixture { store, _, backup in
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        let path = backup.appendingPathComponent(receipt.id.uuidString).appendingPathComponent("source.plist").path
        XCTAssertEqual(link(path, backup.appendingPathComponent("extra-link").path), 0)
        XCTAssertThrowsError(try store.verify(receipt))
    } }
    func testSourceReplacementSameBytesRejected() throws { try fixture { store, source, _ in
        let expected = try store.inspect(name: "fixture.plist")
        let path = source.appendingPathComponent("fixture.plist")
        let bytes = try Data(contentsOf: path)
        try FileManager.default.moveItem(at: path, to: source.appendingPathComponent("old.plist"))
        FileManager.default.createFile(atPath: path.path, contents: bytes, attributes: [.posixPermissions: 0o600])
        XCTAssertThrowsError(try store.prepare(name: "fixture.plist", expected: expected, planID: UUID()))
    } }

    func testReadOnlySourceDirectory755Accepted() throws { try fixture { store, source, _ in
        XCTAssertEqual(chmod(source.path, 0o755), 0)
        let receipt = try store.prepare(name: "fixture.plist", expected: store.inspect(name: "fixture.plist"), planID: UUID())
        try store.verify(receipt)
    } }

}

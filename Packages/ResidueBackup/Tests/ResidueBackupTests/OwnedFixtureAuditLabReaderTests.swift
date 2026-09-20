import XCTest
import Darwin
@testable import ResidueBackup

final class OwnedFixtureAuditLabReaderTests: XCTestCase {
    func fixture(_ body: (URL, Int32) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        defer { close(fd) }
        try body(root, fd)
    }
    func lab(_ root: URL) throws -> URL {
        let path = root.appendingPathComponent("ResidueGuard-VM-VerifiedBackup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return path
    }
    func testEnumerationIsReadOnlyAndOnlyCanonicalOwnedNamesMatch() throws { try fixture { root, fd in
        let expected = try lab(root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ResidueGuard-VM-VerifiedBackup-invalid"), withIntermediateDirectories: false)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let result = try OwnedFixtureAuditLabReader.enumerate(libraryFD: fd)
        XCTAssertEqual(result.coverage, .complete); XCTAssertEqual(result.refusedRootCount, 0)
        XCTAssertEqual(result.labs.map(\.directoryName), [expected.lastPathComponent])
        let anchor = try XCTUnwrap(result.labs.first)
        try anchor.withDirectoryFD { child in var s = stat(); XCTAssertEqual(fstat(child, &s), 0); XCTAssertEqual(s.st_uid, getuid()) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), before)
    } }
    func testUnsafeAndSymlinkRootsAreRefused() throws { try fixture { root, fd in
        let wide = try lab(root), hidden = try lab(root)
        XCTAssertEqual(chmod(wide.path, 0o755), 0)
        XCTAssertEqual(chflags(hidden.path, UInt32(UF_HIDDEN)), 0)
        defer { _ = chflags(hidden.path, 0) }
        let alias = root.appendingPathComponent("ResidueGuard-VM-VerifiedBackup-" + UUID().uuidString)
        XCTAssertEqual(symlink(wide.lastPathComponent, alias.path), 0)
        let result = try OwnedFixtureAuditLabReader.enumerate(libraryFD: fd)
        XCTAssertTrue(result.labs.isEmpty); XCTAssertEqual(result.refusedRootCount, 3)
    } }
    func testAnchorRejectsRootReplacement() throws { try fixture { root, fd in
        let path = try lab(root)
        let anchor = try XCTUnwrap(OwnedFixtureAuditLabReader.enumerate(libraryFD: fd).labs.first)
        try FileManager.default.moveItem(at: path, to: root.appendingPathComponent("retained"))
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try anchor.revalidate())
        XCTAssertThrowsError(try anchor.withDirectoryFD { _ in XCTFail("must refuse before exposing replaced root") })
    } }
    func testRootCountBoundReportsLimitedCoverage() throws { try fixture { root, fd in
        for _ in 0..<65 { _ = try lab(root) }
        let result = try OwnedFixtureAuditLabReader.enumerate(libraryFD: fd)
        XCTAssertEqual(result.labs.count, 64); XCTAssertEqual(result.coverage, .experimentLimit)
    } }
    func testDirectoryEntryBoundReportsLimitedCoverage() throws { try fixture { _, fd in
        for index in 0..<4097 {
            let child = openat(fd, "unrelated-\(index)", O_CREAT | O_EXCL | O_WRONLY, 0o600)
            XCTAssertGreaterThanOrEqual(child, 0); if child >= 0 { close(child) }
        }
        let result = try OwnedFixtureAuditLabReader.enumerate(libraryFD: fd)
        XCTAssertEqual(result.coverage, .directoryEntryLimit); XCTAssertTrue(result.labs.isEmpty)
    } }
}

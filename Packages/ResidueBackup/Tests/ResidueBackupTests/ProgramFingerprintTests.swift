import XCTest
import CryptoKit
import Darwin
@testable import ResidueBackup

final class ProgramFingerprintTests: XCTestCase {
    func fixture(_ body: (VerifiedBackup, Int32, Int32, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), backup = root.appendingPathComponent("backup")
        for path in [source, backup] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let program = source.appendingPathComponent("fixture")
        XCTAssertTrue(FileManager.default.createFile(atPath: program.path, contents: Data("owned test bytes, never executed".utf8), attributes: [.posixPermissions: 0o700]))
        let directory = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        let destination = open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        let fd = openat(directory, "fixture", O_RDONLY | O_NOFOLLOW)
        defer { close(directory); close(destination); close(fd) }
        try body(VerifiedBackup(testSourceFD: directory, testDestinationFD: destination), fd, directory, program)
    }
    func testBoundedProgramReadIncludesContentMetadataAndXattrsAndDoesNotConsumeFDOffset() throws { try fixture { store, fd, directory, path in
        let bytes = Data("metadata".utf8)
        XCTAssertEqual(bytes.withUnsafeBytes { fsetxattr(fd, "example.residueguard.test", $0.baseAddress, $0.count, 0, 0) }, 0)
        let fingerprint = try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory)
        let data = try Data(contentsOf: path)
        XCTAssertEqual(fingerprint.sha256, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(fingerprint.extendedAttributes["example.residueguard.test"], bytes)
        XCTAssertEqual(fingerprint.owner, getuid()); XCTAssertEqual(fingerprint.mode & 0o7777, 0o700)
        XCTAssertEqual(fingerprint.size, Int64(data.count))
        XCTAssertEqual(lseek(fd, 0, SEEK_CUR), 0)
        XCTAssertEqual(try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory, expected: fingerprint), fingerprint)
    } }
    func testChangedProgramRejectsExpectedFingerprint() throws { try fixture { store, fd, directory, path in
        let expected = try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory)
        try Data("changed".utf8).write(to: path)
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory, expected: expected))
    } }
    func testReplacedProgramNameRejectsOldOpenFD() throws { try fixture { store, fd, directory, path in
        try FileManager.default.moveItem(at: path, to: path.appendingPathExtension("retained"))
        XCTAssertTrue(FileManager.default.createFile(atPath: path.path, contents: Data("replacement".utf8), attributes: [.posixPermissions: 0o700]))
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory))
    } }
    func testOversizedProgramRejected() throws { try fixture { store, fd, directory, path in
        try Data(repeating: 1, count: 1_048_577).write(to: path)
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory))
    } }
    func testProgramMustRemainOwnerExecutableOnly() throws { try fixture { store, fd, directory, path in
        XCTAssertEqual(chmod(path.path, 0o600), 0)
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory))
    } }
    func testProgramSymlinkReplacementRejected() throws { try fixture { store, fd, directory, path in
        let retained = path.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: path, to: retained)
        XCTAssertEqual(symlink(retained.lastPathComponent, path.path), 0)
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectProgram(store: store, fd: fd, directory: directory))
    } }
    func signFixture(_ path: URL, identifier: String = "example.residueguard.fixture.iso01") throws {
        try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")).write(to: path)
        XCTAssertEqual(chmod(path.path, 0o700), 0)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", "--identifier", identifier, path.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    }
    func testSignedProgramRevalidationAndChangedBytesRefusal() throws { try fixture { store, _, directory, path in
        try signFixture(path)
        let expected = try OwnedFixtureLabContext.inspectSignedProgram(store: store, directory: directory, fixedPath: path.path)
        XCTAssertEqual(try OwnedFixtureLabContext.inspectSignedProgram(store: store, directory: directory, fixedPath: path.path, expected: expected), expected)
        let handle = try FileHandle(forWritingTo: path); try handle.seek(toOffset: 512)
        try handle.write(contentsOf: Data([0x45, 0x32])); try handle.close()
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectSignedProgram(store: store, directory: directory, fixedPath: path.path, expected: expected))
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectSignedProgram(store: store, directory: directory, fixedPath: path.path))
    } }
    func testWrongSigningIdentifierRejected() throws { try fixture { store, _, directory, path in
        try signFixture(path, identifier: "example.residueguard.wrong")
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectSignedProgram(store: store, directory: directory, fixedPath: path.path))
    } }
    func testUnsignedProgramRejected() throws { try fixture { store, _, directory, path in
        XCTAssertThrowsError(try OwnedFixtureLabContext.inspectSignedProgram(store: store, directory: directory, fixedPath: path.path))
    } }

}

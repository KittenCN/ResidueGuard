import Foundation
import Darwin
import Testing
@testable import ResidueBackup

private final class RecoveryFixture {
    let root: URL
    let parent: Int32
    let source: Int32
    let backups: Int32
    let receipt: BackupReceipt
    var backupDirectory: URL { root.appendingPathComponent("backups/" + receipt.id.uuidString) }
    var isolated: URL { root.appendingPathComponent("quarantine/" + receipt.id.uuidString + ".plist") }
    var sourceURL: URL { root.appendingPathComponent("source/" + TemporaryFreshRecoveryReader.sourceName) }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ResidueGuard-fresh-recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for name in ["source", "quarantine", "backups"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        parent = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        source = openat(parent, "source", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        backups = openat(parent, "backups", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        let url = root.appendingPathComponent("source/" + TemporaryFreshRecoveryReader.sourceName)
        let data = try PropertyListSerialization.data(fromPropertyList: ["Label": "example.residueguard.fixture.iso01", "RunAtLoad": false], format: .xml, options: 0)
        try data.write(to: url); chmod(url.path, 0o600)
        let backup = try VerifiedBackup(testSourceFD: source, testDestinationFD: backups)
        receipt = try backup.prepare(name: TemporaryFreshRecoveryReader.sourceName,
            expected: backup.inspect(name: TemporaryFreshRecoveryReader.sourceName), planID: UUID())
        guard rename(url.path, root.appendingPathComponent("quarantine/" + receipt.id.uuidString + ".plist").path) == 0 else { throw BackupFailure.io }
    }
    deinit { close(source); close(backups); close(parent); try? FileManager.default.removeItem(at: root) }
    func reader() throws -> TemporaryFreshRecoveryReader { try .init(testParentFD: parent) }
}

@Test func freshReadsActualFilesWithoutMintingAuthority() throws {
    let fixture = try RecoveryFixture(), reader = try fixture.reader()
    let result = try reader.inspect(backupID: fixture.receipt.id)
    #expect(result.sourceAbsent && !result.permitsMutation && !result.runtimeInspected)
    #expect(!result.programInspected && !result.fixturePolicyVerified)
    #expect(result.historyTrust == "untrustedHistory")
    #expect(result.quarantined.sha256 == fixture.receipt.fingerprint.sha256)
    #expect(result.backupContent.sha256 == fixture.receipt.fingerprint.sha256)
    #expect(result.quarantined.inode == fixture.receipt.fingerprint.inode)
}
@Test func sourceConflictIncludesDanglingSymlink() throws {
    for link in [false, true] {
        let fixture = try RecoveryFixture(), reader = try fixture.reader()
        if link { #expect(symlink("absent-owned-target", fixture.sourceURL.path) == 0) }
        else { try Data("conflict".utf8).write(to: fixture.sourceURL) }
        #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
    }
}
@Test func tamperedBackupAndManifestAndQuarantineAreRejected() throws {
    for target in ["source.plist", "manifest.json", "quarantine"] {
        let fixture = try RecoveryFixture(), reader = try fixture.reader()
        let url = target == "quarantine" ? fixture.isolated : fixture.backupDirectory.appendingPathComponent(target)
        try Data("tampered".utf8).write(to: url)
        #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
    }
}
@Test func artifactLinksAndModesAreRejected() throws {
    for kind in ["symlink", "hardlink", "mode"] {
        let fixture = try RecoveryFixture(), reader = try fixture.reader()
        let artifact = fixture.backupDirectory.appendingPathComponent("source.plist")
        if kind == "symlink" {
            try FileManager.default.removeItem(at: artifact)
            #expect(symlink(fixture.isolated.path, artifact.path) == 0)
        } else if kind == "hardlink" {
            #expect(link(artifact.path, fixture.root.appendingPathComponent("extra-link").path) == 0)
        } else { #expect(chmod(artifact.path, 0o644) == 0) }
        #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
    }
}
@Test func namedRootReplacementAndRootSymlinkAreRejected() throws {
    for name in ["source", "quarantine", "backups"] {
        let fixture = try RecoveryFixture(), reader = try fixture.reader()
        let original = fixture.root.appendingPathComponent(name)
        let moved = fixture.root.appendingPathComponent(name + "-moved")
        try FileManager.default.moveItem(at: original, to: moved)
        #expect(symlink(moved.path, original.path) == 0)
        #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
    }
}
@Test func changesBetweenIndependentReadsAreRejected() throws {
    let fixture = try RecoveryFixture(), reader = try fixture.reader()
    reader.betweenReadsForTesting = {
        // Preserve bytes but replace the manifest inode; its current identity must remain stable.
        let url = fixture.backupDirectory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try data.write(to: url); chmod(url.path, 0o600)
    }
    #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
}
@Test func metadataMismatchAndIncorrectBackupIDAreRejected() throws {
    let fixture = try RecoveryFixture(), reader = try fixture.reader()
    #expect(throws: (any Error).self) { try reader.inspect(backupID: UUID()) }
    #expect(chmod(fixture.isolated.path, 0o644) == 0)
    #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
}
@Test func sourceAppearingBetweenReadsIsRejected() throws {
    let fixture = try RecoveryFixture(), reader = try fixture.reader()
    reader.betweenReadsForTesting = { try Data("new source".utf8).write(to: fixture.sourceURL) }
    #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
}

@Test func backupDirectoryIdentityCannotChangeBetweenReads() throws {
    let fixture = try RecoveryFixture(), reader = try fixture.reader()
    reader.betweenReadsForTesting = {
        let old = fixture.backupDirectory, moved = fixture.root.appendingPathComponent("moved-backup")
        try FileManager.default.moveItem(at: old, to: moved)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        // Moving original files preserves their inode: directory identity must be checked separately.
        for name in ["source.plist", "manifest.json"] {
            try FileManager.default.moveItem(at: moved.appendingPathComponent(name), to: old.appendingPathComponent(name))
        }
    }
    #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
}

@Test func ambiguousOrUnknownManifestFieldsAreRejected() throws {
    for prefix in ["\"unknown\":1,", "\"version\":1,", " "] {
        let fixture = try RecoveryFixture(), reader = try fixture.reader()
        let url = fixture.backupDirectory.appendingPathComponent("manifest.json")
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let malformed = "{" + prefix + text.dropFirst()
        try Data(malformed.utf8).write(to: url)
        #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
    }
}

@Test func legacyNoncanonicalManifestRemainsVerifiableButFreshProfileRejects() throws {
    let fixture = try RecoveryFixture()
    let url = fixture.backupDirectory.appendingPathComponent("manifest.json")
    var bytes = try Data(contentsOf: url); bytes.append(10)
    try bytes.write(to: url)
    let legacyVerifier = try VerifiedBackup(testSourceFD: fixture.source, testDestinationFD: fixture.backups)
    try legacyVerifier.verify(fixture.receipt)
    let reader = try fixture.reader()
    #expect(throws: (any Error).self) { try reader.inspect(backupID: fixture.receipt.id) }
}

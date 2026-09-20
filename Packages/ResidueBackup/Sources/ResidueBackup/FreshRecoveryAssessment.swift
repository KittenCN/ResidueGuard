import Foundation
import Darwin

/// Current bytes verified for consistency, not historical authenticity or restoration authority.
struct FreshRecoveryAssessment: Sendable {
    let observedAt: Date
    let backupID: UUID
    let originalPlanID: UUID
    let backupDirectoryDevice: Int32
    let backupDirectoryInode: UInt64
    let quarantined: SourceFingerprint
    let backupContent: SourceFingerprint
    let manifest: SourceFingerprint
    let historyTrust = "untrustedHistory"
    let permitsMutation = false
    let runtimeInspected = false
    let programInspected = false
    let fixturePolicyVerified = false
    let sourceAbsent = true
}

/// Internal temporary-fixture seam only. No public VM or arbitrary path entry point.
/// The injected parent FD is the test trust boundary; its ancestors are not inspected.
final class TemporaryFreshRecoveryReader {
    static let sourceName = "example.residueguard.fixture.iso01.plist"
    private struct Anchor {
        let name: String
        let fd: Int32
        let device: Int32
        let inode: UInt64
    }
    private struct UntrustedManifest: Codable {
        let version: Int
        let id: UUID
        let planID: UUID
        let sourceName: String
        let fingerprint: SourceFingerprint
        let createdAt: Date
        let runtimeState: String
    }
    private let parent: Int32
    private let anchors: [Anchor]
    private let reader: VerifiedBackup
    // Deterministic competing update seam, unavailable outside this module/tests.
    var betweenReadsForTesting: (() throws -> Void)?

    init(testParentFD: Int32) throws {
        let parent = dup(testParentFD)
        guard parent >= 0 else { throw BackupFailure.io }
        var anchors: [Anchor] = []
        do {
            try VerifiedBackup.checkRecoveryDirectory(parent)
            for name in ["source", "quarantine", "backups"] {
                let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw BackupFailure.unsafeFile }
                do { try VerifiedBackup.checkRecoveryDirectory(fd, privateRequired: name != "source") }
                catch { close(fd); throw error }
                var value = stat()
                guard fstat(fd, &value) == 0 else { close(fd); throw BackupFailure.io }
                anchors.append(.init(name: name, fd: fd, device: value.st_dev, inode: value.st_ino))
            }
            self.reader = try VerifiedBackup(testSourceFD: anchors[0].fd, testDestinationFD: anchors[2].fd)
        } catch { anchors.forEach { close($0.fd) }; close(parent); throw error }
        self.parent = parent; self.anchors = anchors

    }
    deinit { anchors.forEach { close($0.fd) }; close(parent) }

    func inspect(backupID: UUID) throws -> FreshRecoveryAssessment {
        try revalidate(); try requireAbsent()
        let first = try observe(backupID)
        try betweenReadsForTesting?()
        let final = try observe(backupID)
        try requireAbsent(); try revalidate()
        guard first.quarantined == final.quarantined, first.backupContent == final.backupContent,
              first.manifest == final.manifest, first.originalPlanID == final.originalPlanID,
              first.backupDirectoryDevice == final.backupDirectoryDevice, first.backupDirectoryInode == final.backupDirectoryInode else { throw BackupFailure.changed }
        return final
    }
    private func revalidate() throws {
        try VerifiedBackup.checkRecoveryDirectory(parent)
        for anchor in anchors {
            try VerifiedBackup.checkRecoveryDirectory(anchor.fd, privateRequired: anchor.name != "source")
            var named = stat(), opened = stat()
            guard fstat(anchor.fd, &opened) == 0,
                  fstatat(parent, anchor.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_mode & S_IFMT == S_IFDIR, named.st_dev == anchor.device, named.st_ino == anchor.inode,
                  opened.st_dev == anchor.device, opened.st_ino == anchor.inode else { throw BackupFailure.changed }
        }
        guard Set(anchors.map(\.device)).count == 1 else { throw BackupFailure.unsafeFile }
    }
    private func requireAbsent() throws {
        var named = stat()
        guard fstatat(anchors[0].fd, Self.sourceName, &named, AT_SYMLINK_NOFOLLOW) == -1,
              errno == ENOENT else { throw BackupFailure.changed }
    }
    private func read(_ name: String, at directory: Int32, privateFile: Bool) throws -> (Data, SourceFingerprint) {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.unsafeFile }; defer { close(fd) }
        return try reader.readOpened(fd: fd, directory: directory, name: name, requirePrivate: privateFile)
    }
    private func observe(_ id: UUID) throws -> FreshRecoveryAssessment {
        let fd = openat(anchors[2].fd, id.uuidString, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.invalidBackup }; defer { close(fd) }
        try VerifiedBackup.checkRecoveryDirectory(fd)
        var item = stat(), named = stat()
        guard fstat(fd, &item) == 0 else { throw BackupFailure.io }
        let manifest = try read("manifest.json", at: fd, privateFile: true)
        let historical = try JSONDecoder().decode(UntrustedManifest.self, from: manifest.0)
        let canonical = JSONEncoder(); canonical.outputFormatting = [.sortedKeys]
        guard try canonical.encode(historical) == manifest.0 else { throw BackupFailure.invalidBackup }
        guard historical.version == 1, historical.id == id, historical.sourceName == Self.sourceName,
              historical.createdAt.timeIntervalSince1970.isFinite,
              historical.runtimeState == "notInspected" else { throw BackupFailure.invalidBackup }
        let content = try read("source.plist", at: fd, privateFile: true)
        let isolated = try read(id.uuidString + ".plist", at: anchors[1].fd, privateFile: false)
        let f = historical.fingerprint, q = isolated.1
        // Historical ctime may differ after rename. The new current assessment retains exact current ctime.
        guard content.0 == isolated.0, content.1.sha256 == f.sha256, content.1.size == f.size,
              q.device == f.device, q.inode == f.inode, q.owner == f.owner, q.group == f.group,
              q.mode == f.mode, q.size == f.size, q.modifiedSeconds == f.modifiedSeconds,
              q.modifiedNanos == f.modifiedNanos, q.extendedAttributes == f.extendedAttributes,
              let plist = try PropertyListSerialization.propertyList(from: isolated.0, format: nil) as? [String: Any],
              plist["Label"] as? String == "example.residueguard.fixture.iso01" else { throw BackupFailure.invalidBackup }
        try VerifiedBackup.checkRecoveryDirectory(fd)
        guard fstatat(anchors[2].fd, id.uuidString, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR, named.st_dev == item.st_dev, named.st_ino == item.st_ino else { throw BackupFailure.changed }
        return .init(observedAt: Date(), backupID: id, originalPlanID: historical.planID, backupDirectoryDevice: item.st_dev, backupDirectoryInode: item.st_ino,
                     quarantined: q, backupContent: content.1, manifest: manifest.1)
    }
}

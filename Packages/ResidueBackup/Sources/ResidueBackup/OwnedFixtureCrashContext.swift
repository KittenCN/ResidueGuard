#if DEBUG
import Foundation
import Darwin

/// DEBUG-only, fixed temporary fixtures. No production path or executable input.
package final class OwnedFixtureCrashContext {
    package let rootFD: Int32
    package let sourceFD: Int32
    package let backupFD: Int32
    package let quarantineFD: Int32
    package let token: UUID
    private init(root: Int32, source: Int32, backup: Int32, quarantine: Int32, token: UUID) {
        rootFD = root; sourceFD = source; backupFD = backup; quarantineFD = quarantine; self.token = token
    }
    deinit { close(rootFD); close(sourceFD); close(backupFD); close(quarantineFD) }
    package static func open(token: UUID, create: Bool) throws -> OwnedFixtureCrashContext {
        guard getuid() != 0, geteuid() == getuid() else { throw BackupFailure.unsafeFile }
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let parent = Darwin.open(temp.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw BackupFailure.io }; defer { close(parent) }
        let name = "ResidueGuard-owned-crash-" + token.uuidString
        if create { guard mkdirat(parent, name, 0o700) == 0 else { throw BackupFailure.unsafeFile } }
        let root = try directory(parent: parent, name: name)
        var source: Int32 = -1, backup: Int32 = -1, quarantine: Int32 = -1
        do {
            let backupName = "ResidueGuard-VM-VerifiedBackup-" + token.uuidString
            if create {
                for child in ["source", backupName, "quarantine"] {
                    guard mkdirat(root, child, 0o700) == 0 else { throw BackupFailure.io }
                }
            }
            source = try directory(parent: root, name: "source")
            backup = try directory(parent: root, name: backupName)
            quarantine = try directory(parent: root, name: "quarantine")
            return .init(root: root, source: source, backup: backup, quarantine: quarantine, token: token)
        } catch {
            close(root); if source >= 0 { close(source) }; if backup >= 0 { close(backup) }; throw error
        }
    }
    package func createFixtureAndBackup() throws -> (VerifiedBackup, BackupReceipt) {
        let name = "example.residueguard.fixture.iso01.plist"
        let fd = openat(sourceFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BackupFailure.unsafeFile }; defer { close(fd) }
        let data = Data("<plist><dict><key>syntheticCrashFixture</key><true/></dict></plist>".utf8)
        let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard count == data.count, fsync(fd) == 0 else { throw BackupFailure.io }
        let store = try VerifiedBackup(testSourceFD: sourceFD, testDestinationFD: backupFD)
        try store.bindAuditRootForTesting(parentFD: rootFD, name: "ResidueGuard-VM-VerifiedBackup-" + token.uuidString, id: token)
        let receipt = try store.prepare(name: name, expected: store.inspect(name: name), planID: token)
        return (store, receipt)
    }
    package func checkpoint(_ phase: String) throws -> Never {
        let fd = openat(rootFD, "checkpoint", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BackupFailure.io }
        let bytes = Data(phase.utf8)
        let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count, fsync(fd) == 0, fsync(rootFD) == 0 else { close(fd); throw BackupFailure.io }
        close(fd)
        while true { _ = Darwin.pause() }
    }
    private static func directory(parent: Int32, name: String) throws -> Int32 {
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.unsafeFile }
        do {
            var s = stat()
            guard fstat(fd, &s) == 0, s.st_uid == getuid(), s.st_mode & 0o7777 == 0o700, s.st_flags == 0 else { throw BackupFailure.unsafeFile }
            if let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) {
                defer { acl_free(UnsafeMutableRawPointer(acl)) }; var entry: acl_entry_t?
                guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw BackupFailure.unsupportedMetadata }
            } else if errno != ENOENT { throw BackupFailure.unsupportedMetadata }
            return fd
        } catch { close(fd); throw error }
    }
}
#endif

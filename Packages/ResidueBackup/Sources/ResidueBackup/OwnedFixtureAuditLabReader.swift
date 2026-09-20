import Foundation
import Darwin

package enum OwnedFixtureAuditEnumerationCoverage: String, Sendable {
    case complete, directoryEntryLimit, experimentLimit
}
package struct OwnedFixtureAuditLabEnumeration {
    package let labs: [OwnedFixtureAuditLabAnchor]
    package let source: OwnedFixtureSourceAuditAnchor?
    package let coverage: OwnedFixtureAuditEnumerationCoverage
    package let refusedRootCount: Int
}

/// Package-only fixed-root reader. No public constructor, caller path, creation or recovery operation.
package enum OwnedFixtureAuditLabReader {
    package static func read() throws -> OwnedFixtureAuditLabEnumeration {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard try sysctlString("hw.model").hasPrefix("VirtualMac"), getuid() != 0, geteuid() == getuid(),
              os.majorVersion == 27, os.minorVersion == 0, os.patchVersion == 0,
              try sysctlString("kern.osversion") == "26A428" else { throw VMLabProbeError.virtualMachineRequired }
        guard let entry = getpwuid(getuid()), let pointer = entry.pointee.pw_dir else { throw VMLabProbeError.invalidLab }
        let home = String(cString: pointer)
        guard home.hasPrefix("/Users/"), home.split(separator: "/").count == 2 else { throw VMLabProbeError.invalidLab }
        let library = try OwnedFixtureLabContext.labOpenChain(home + "/Library")
        defer { close(library) }
        let source = try OwnedFixtureSourceAuditAnchor(fixedPath: home + "/Library/LaunchAgents")
        let result = try enumerate(libraryFD: library, fixedLibraryPath: home + "/Library")
        return .init(labs: result.labs, source: source, coverage: result.coverage, refusedRootCount: result.refusedRootCount)
    }
    // Internal temporary-fixture seam; no externally supplied paths reach the package entry point.
    static func enumerate(libraryFD: Int32, fixedLibraryPath: String? = nil) throws -> OwnedFixtureAuditLabEnumeration {
        let streamFD = openat(libraryFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard streamFD >= 0 else { throw BackupFailure.io }
        guard let stream = fdopendir(streamFD) else { close(streamFD); throw BackupFailure.io }
        defer { closedir(stream) }
        var labs: [OwnedFixtureAuditLabAnchor] = [], refused = 0, count = 0, candidates = 0
        while count < 4096 {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw BackupFailure.io }
                return .init(labs: labs, source: nil, coverage: .complete, refusedRootCount: refused)
            }
            count += 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            let prefix = "ResidueGuard-VM-VerifiedBackup-"
            guard name.hasPrefix(prefix), let id = UUID(uuidString: String(name.dropFirst(prefix.count))),
                  name == prefix + id.uuidString else { continue }
            guard candidates < 64 else { return .init(labs: labs, source: nil, coverage: .experimentLimit, refusedRootCount: refused) }
            candidates += 1
            do { labs.append(try OwnedFixtureAuditLabAnchor(parentFD: libraryFD, name: name, id: id, fixedLibraryPath: fixedLibraryPath)) }
            catch { refused += 1 }
        }
        return .init(labs: labs, source: nil, coverage: .directoryEntryLimit, refusedRootCount: refused)
    }
    private static func sysctlString(_ name: String) throws -> String {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 0, count < 256 else { throw VMLabProbeError.invalidLab }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname(name, &bytes, &count, nil, 0) == 0 else { throw VMLabProbeError.invalidLab }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Holds an O_RDONLY directory descriptor. The closure is only for trusted same-package journal readers;
/// O_RDONLY on a directory is not a sandbox or a general write-prevention capability.
package final class OwnedFixtureAuditLabAnchor {
    package let rootID: UUID
    package let directoryName: String
    private let parentFD: Int32
    private let directoryFD: Int32
    private let parentDevice: Int32
    private let parentInode: UInt64
    private let device: Int32
    private let inode: UInt64
    private let fixedLibraryPath: String?
    fileprivate init(parentFD: Int32, name: String, id: UUID, fixedLibraryPath: String?) throws {
        let parent = dup(parentFD)
        guard parent >= 0 else { throw BackupFailure.io }
        let root = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { close(parent); throw BackupFailure.unsafeFile }
        do {
            let info = try Self.strictRoot(root)
            var p = stat(), named = stat()
            guard fstat(parent, &p) == 0, fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_dev == info.st_dev, named.st_ino == info.st_ino else { throw BackupFailure.changed }
            self.parentFD = parent; directoryFD = root; rootID = id; directoryName = name
            parentDevice = p.st_dev; parentInode = p.st_ino; device = info.st_dev; inode = info.st_ino
            self.fixedLibraryPath = fixedLibraryPath
        } catch { close(parent); close(root); throw error }
    }
    deinit { close(parentFD); close(directoryFD) }
    package func revalidate() throws {
        let current = try Self.strictRoot(directoryFD)
        var p = stat(), named = stat()
        guard fstat(parentFD, &p) == 0, p.st_dev == parentDevice, p.st_ino == parentInode,
              current.st_dev == device, current.st_ino == inode,
              fstatat(parentFD, directoryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR, named.st_dev == device, named.st_ino == inode else { throw BackupFailure.changed }
        if let fixedLibraryPath {
            let live = try OwnedFixtureLabContext.labOpenChain(fixedLibraryPath)
            defer { close(live) }
            var info = stat()
            guard fstat(live, &info) == 0, info.st_dev == parentDevice, info.st_ino == parentInode else { throw BackupFailure.changed }
        }
    }
    package func withDirectoryFD<T>(_ body: (Int32) throws -> T) throws -> T {
        try revalidate()
        let value = try body(directoryFD)
        try revalidate()
        return value
    }
    fileprivate static func strictRoot(_ fd: Int32, privateRequired: Bool = true) throws -> stat {
        var s = stat()
        guard fstat(fd, &s) == 0, s.st_mode & S_IFMT == S_IFDIR, s.st_uid == getuid(),
              s.st_mode & 0o7022 == 0, (!privateRequired || s.st_mode & 0o7777 == 0o700), s.st_flags == 0 else { throw BackupFailure.unsafeFile }
        if let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw BackupFailure.unsupportedMetadata }
        } else if errno != ENOENT { throw BackupFailure.unsupportedMetadata }
        return s
    }
}

/// Fixed current-user LaunchAgents read anchor; never accepts an external path.
package final class OwnedFixtureSourceAuditAnchor {
    private let fd: Int32
    private let fixedPath: String
    private let device: Int32
    private let inode: UInt64
    fileprivate init(fixedPath: String) throws {
        let opened = try OwnedFixtureLabContext.labOpenChain(fixedPath)
        do {
            let info = try OwnedFixtureAuditLabAnchor.strictRoot(opened, privateRequired: false)
            fd = opened; self.fixedPath = fixedPath; device = info.st_dev; inode = info.st_ino
        } catch { close(opened); throw error }
    }
    deinit { close(fd) }
    package func revalidate() throws {
        let saved = try OwnedFixtureAuditLabAnchor.strictRoot(fd, privateRequired: false)
        let live = try OwnedFixtureLabContext.labOpenChain(fixedPath)
        defer { close(live) }
        let current = try OwnedFixtureAuditLabAnchor.strictRoot(live, privateRequired: false)
        guard saved.st_dev == device, saved.st_ino == inode, current.st_dev == device, current.st_ino == inode else { throw BackupFailure.changed }
    }
    package func withSourceDirectoryFD<T>(_ body: (Int32) throws -> T) throws -> T {
        try revalidate(); let value = try body(fd); try revalidate(); return value
    }
}

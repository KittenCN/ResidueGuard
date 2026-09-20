import Foundation
import CryptoKit
import Darwin

public enum BackupFailure: Error { case invalidName, unsafeFile, unsupportedMetadata, changed, io, invalidBackup }
public struct SourceFingerprint: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let owner: UInt32
    public let group: UInt32
    public let mode: UInt16
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanos: Int64
    public let changedSeconds: Int64
    public let changedNanos: Int64
    public let sha256: String
    public let extendedAttributes: [String: Data]
}
public struct BackupReceipt: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let planID: UUID
    public let sourceName: String
    public let fingerprint: SourceFingerprint
    public let createdAt: Date
    // Runtime identity must be verified independently before any future source mutation.
    public let runtimeState: String
}

/// Prototype only: no public initializer and no production filesystem entry point.
/// Internal tests inject already opened private directories containing only test fixtures.
public final class VerifiedBackup {
    private let source: Int32
    private let destination: Int32
    private let maximumSize = 1_048_576
    private var auditRoot: BackupAuditRootAnchor?
    private var issuedAuditReceipts: [UUID: IssuedAuditReceipt] = [:]
    private struct ArtifactIdentity: Equatable {
        let device: Int32; let inode: UInt64; let owner: UInt32
    }
    private struct IssuedAuditReceipt {
        let receipt: BackupReceipt
        let directory: ArtifactIdentity
        let manifest: SourceFingerprint
        let content: SourceFingerprint
    }
    init(testSourceFD: Int32, testDestinationFD: Int32) throws {
        let sourceCopy = dup(testSourceFD), destinationCopy = dup(testDestinationFD)
        guard sourceCopy >= 0, destinationCopy >= 0 else {
            if sourceCopy >= 0 { close(sourceCopy) }; if destinationCopy >= 0 { close(destinationCopy) }
            throw BackupFailure.io
        }
        do { try Self.directory(sourceCopy, privateRequired: false); try Self.directory(destinationCopy) }
        catch { close(sourceCopy); close(destinationCopy); throw error }
        source = sourceCopy; destination = destinationCopy
    }
    deinit { close(source); close(destination) }

    public func inspect(name: String) throws -> SourceFingerprint { try readSource(name).1 }
    public func prepare(name: String, expected: SourceFingerprint, planID: UUID) throws -> BackupReceipt {
        try Self.directory(source, privateRequired: false); try Self.directory(destination)
        if auditRoot != nil {
            guard issuedAuditReceipts.count < 64 else { throw BackupFailure.invalidBackup }
            _ = try validateAuditRoot()
        }
        let (bytes, fingerprint) = try readSource(name)
        guard fingerprint == expected else { throw BackupFailure.changed }
        let receipt = BackupReceipt(version: 1, id: UUID(), planID: planID, sourceName: name,
                                    fingerprint: fingerprint, createdAt: Date(), runtimeState: "notInspected")
        let directoryName = receipt.id.uuidString
        guard mkdirat(destination, directoryName, 0o700) == 0 else { throw BackupFailure.io }
        // Failures intentionally leave an incomplete private directory for diagnosis, never a verified receipt.
        let fd = openat(destination, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.io }; defer { close(fd) }
        try Self.directory(fd)
        try write(bytes, name: "source.plist", directory: fd)
        try write(JSONEncoder().encode(receipt), name: "manifest.json", directory: fd)
        guard fsync(fd) == 0, fsync(destination) == 0 else { throw BackupFailure.io }
        try verify(receipt)
        guard try readSource(name).1 == expected else { throw BackupFailure.changed }
        if auditRoot != nil {
            let observed = try auditArtifacts(receipt)
            _ = try validateAuditRoot()
            issuedAuditReceipts[receipt.id] = IssuedAuditReceipt(receipt: receipt, directory: observed.directory,
                                                              manifest: observed.manifest.1, content: observed.content.1)
        }
        return receipt
    }
    public func verify(_ receipt: BackupReceipt) throws {
        try Self.directory(destination)
        let fd = openat(destination, receipt.id.uuidString, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.invalidBackup }; defer { close(fd) }
        try Self.directory(fd)
        let manifest = try read("manifest.json", directory: fd, requirePrivate: true).0
        guard try JSONDecoder().decode(BackupReceipt.self, from: manifest) == receipt,
              receipt.version == 1 else { throw BackupFailure.invalidBackup }
        let bytes = try read("source.plist", directory: fd, requirePrivate: true).0
        guard Int64(bytes.count) == receipt.fingerprint.size, Self.digest(bytes) == receipt.fingerprint.sha256 else {
            throw BackupFailure.invalidBackup
        }
    }
    /// Observation only; receipt must have been actually issued by this bound store instance.
    package func inspectAuditEvidence(receipt: BackupReceipt) throws -> BackupAuditEvidence {
        guard let issued = issuedAuditReceipts[receipt.id], issued.receipt == receipt else { throw BackupFailure.invalidBackup }
        let root = try validateAuditRoot()
        let observed = try auditArtifacts(receipt)
        guard observed.directory == issued.directory, observed.manifest.1 == issued.manifest,
              observed.content.1 == issued.content else { throw BackupFailure.changed }
        // Verify a second independently opened snapshot before emitting evidence; this is still not an atomic filesystem snapshot.
        let final = try auditArtifacts(receipt)
        guard final.directory == issued.directory, final.manifest.1 == issued.manifest,
              final.content.1 == issued.content, try validateAuditRoot() == root else { throw BackupFailure.changed }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return BackupAuditEvidence(backupID: receipt.id, planID: receipt.planID, root: root,
            contentSHA256: Self.digest(observed.content.0),
            metadataSHA256: Self.digest(try encoder.encode(receipt.fingerprint)),
            manifestSHA256: Self.digest(observed.manifest.0), observedAt: Date())
    }
    // Internal factory-only binding. These methods are not exposed even to other package targets.
    func bindOwnedFixtureAuditRoot(parentFD: Int32, labID: UUID, home: String) throws {
        try bindAuditRoot(parentFD: parentFD, name: "ResidueGuard-VM-VerifiedBackup-" + labID.uuidString,
                          id: labID, namespace: .ownedISO01VM, fixedParentPath: home + "/Library")
    }
    func bindAuditRootForTesting(parentFD: Int32, name: String, id: UUID) throws {
        try bindAuditRoot(parentFD: parentFD, name: name, id: id, namespace: .temporaryFixture, fixedParentPath: nil)
    }
    private func bindAuditRoot(parentFD: Int32, name: String, id: UUID,
                               namespace: BackupAuditRootLocator.Namespace, fixedParentPath: String?) throws {
        guard auditRoot == nil, !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\0"), name.utf8.count <= 255 else { throw BackupFailure.invalidBackup }
        try Self.auditParentDirectory(parentFD); try Self.directory(destination)
        var parent = stat(), root = stat(), named = stat()
        guard fstat(parentFD, &parent) == 0, fstat(destination, &root) == 0,
              fstatat(parentFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR, named.st_dev == root.st_dev, named.st_ino == root.st_ino else { throw BackupFailure.changed }
        auditRoot = try BackupAuditRootAnchor(parentFD: parentFD,
            locator: .init(namespace: namespace, rootID: id, directoryName: name, parent: parent, root: root),
            fixedParentPath: fixedParentPath)
        _ = try validateAuditRoot()
    }
    private func validateAuditRoot() throws -> BackupAuditRootLocator {
        guard let anchor = auditRoot else { throw BackupFailure.invalidBackup }
        try Self.auditParentDirectory(anchor.parentFD); try Self.directory(destination)
        var parent = stat(), root = stat(), named = stat()
        guard fstat(anchor.parentFD, &parent) == 0, fstat(destination, &root) == 0,
              parent.st_dev == anchor.locator.parentDevice, parent.st_ino == anchor.locator.parentInode,
              root.st_dev == anchor.locator.device, root.st_ino == anchor.locator.inode, root.st_uid == anchor.locator.owner,
              fstatat(anchor.parentFD, anchor.locator.directoryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR, named.st_dev == root.st_dev, named.st_ino == root.st_ino else { throw BackupFailure.changed }
        if let fixedParentPath = anchor.fixedParentPath {
            let current = try OwnedFixtureLabContext.labOpenChain(fixedParentPath)
            defer { close(current) }
            var live = stat()
            guard fstat(current, &live) == 0, live.st_dev == parent.st_dev, live.st_ino == parent.st_ino else { throw BackupFailure.changed }
        }
        return anchor.locator
    }
    private func auditArtifacts(_ receipt: BackupReceipt) throws -> (directory: ArtifactIdentity, manifest: (Data, SourceFingerprint), content: (Data, SourceFingerprint)) {
        let fd = openat(destination, receipt.id.uuidString, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.invalidBackup }; defer { close(fd) }
        try Self.directory(fd)
        var info = stat(), named = stat()
        guard fstat(fd, &info) == 0 else { throw BackupFailure.io }
        let manifest = try read("manifest.json", directory: fd, requirePrivate: true)
        guard receipt.version == 1, try JSONDecoder().decode(BackupReceipt.self, from: manifest.0) == receipt else { throw BackupFailure.invalidBackup }
        let content = try read("source.plist", directory: fd, requirePrivate: true)
        guard content.0.count == receipt.fingerprint.size, Self.digest(content.0) == receipt.fingerprint.sha256,
              fstatat(destination, receipt.id.uuidString, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR, named.st_dev == info.st_dev, named.st_ino == info.st_ino else { throw BackupFailure.changed }
        try Self.directory(fd)
        return (.init(device: info.st_dev, inode: info.st_ino, owner: info.st_uid), manifest, content)
    }
    func readSource(_ name: String) throws -> (Data, SourceFingerprint) {
        guard name.hasSuffix(".plist"), name != ".plist", !name.contains("/"), !name.contains("\0"), name.utf8.count <= 255 else { throw BackupFailure.invalidName }
        try Self.directory(source, privateRequired: false)
        return try read(name, directory: source, requirePrivate: false)
    }
    private func read(_ name: String, directory: Int32, requirePrivate: Bool) throws -> (Data, SourceFingerprint) {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw BackupFailure.unsafeFile }; defer { close(fd) }
        return try readOpened(fd: fd, directory: directory, name: name, requirePrivate: requirePrivate)
    }
    // Module-internal shared bounded reader; no raw-fd interface crosses the module boundary.
    func readOpened(fd: Int32, directory: Int32, name: String, requirePrivate: Bool) throws -> (Data, SourceFingerprint) {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw BackupFailure.invalidName }
        let before = try attributes(fd, privateMode: requirePrivate)
        let beforeXattrs = try xattrs(fd)
        guard before.st_size >= 0, before.st_size <= maximumSize else { throw BackupFailure.unsafeFile }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.pread(fd, &buffer, buffer.count, off_t(data.count))
            if count < 0 { if errno == EINTR { continue }; throw BackupFailure.io }
            if count == 0 { break }
            guard data.count + count <= maximumSize else { throw BackupFailure.unsafeFile }
            data.append(contentsOf: buffer.prefix(count))
        }
        let after = try attributes(fd, privateMode: requirePrivate)
        let fingerprint = Self.fingerprint(before, data, beforeXattrs)
        guard fingerprint == Self.fingerprint(after, data, try xattrs(fd)), data.count == before.st_size else { throw BackupFailure.changed }
        var pathStat = stat()
        guard fstatat(directory, name, &pathStat, AT_SYMLINK_NOFOLLOW) == 0,
              fingerprint == Self.fingerprint(pathStat, data, beforeXattrs), pathStat.st_nlink == 1 else { throw BackupFailure.changed }
        return (data, fingerprint)
    }
    private func attributes(_ fd: Int32, privateMode: Bool) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              value.st_uid == getuid(), value.st_nlink == 1,
              value.st_mode & 0o7022 == 0, value.st_flags == 0,
              !privateMode || value.st_mode & 0o777 == 0o600 else { throw BackupFailure.unsafeFile }
        try Self.noMetadata(fd)
        return value
    }
    private static func directory(_ fd: Int32, privateRequired: Bool = true) throws {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR,
              value.st_uid == getuid(), value.st_mode & 0o7022 == 0,
              !privateRequired || value.st_mode & 0o7777 == 0o700, value.st_flags == 0 else { throw BackupFailure.unsafeFile }
        try noMetadata(fd)
    }
    // Ancestors are not backup artifacts: macOS Library commonly has a protective deny-delete ACL.
    // Permit only that non-inheriting restriction; never relax the artifact no-ACL policy.
    private static func auditParentDirectory(_ fd: Int32) throws {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR,
              value.st_uid == getuid(), value.st_mode & 0o7022 == 0, value.st_flags & ~UInt32(UF_HIDDEN) == 0 else {
            throw BackupFailure.unsafeFile
        }
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw BackupFailure.unsupportedMetadata }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?, selector = Int32(ACL_FIRST_ENTRY.rawValue), count = 0
        while acl_get_entry(acl, selector, &entry) == 0 {
            count += 1
            guard count <= 128, let entry else { throw BackupFailure.unsupportedMetadata }
            var tag = ACL_UNDEFINED_TAG, mask: acl_permset_mask_t = 0
            var flags: acl_flagset_t?
            guard acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_DENY,
                  acl_get_permset_mask_np(entry, &mask) == 0, mask == acl_permset_mask_t(ACL_DELETE.rawValue),
                  acl_get_flagset_np(UnsafeMutableRawPointer(entry), &flags) == 0, let flags else { throw BackupFailure.unsupportedMetadata }
            for flag in [ACL_ENTRY_INHERITED, ACL_ENTRY_FILE_INHERIT, ACL_ENTRY_DIRECTORY_INHERIT,
                         ACL_ENTRY_LIMIT_INHERIT, ACL_ENTRY_ONLY_INHERIT, ACL_FLAG_DEFER_INHERIT, ACL_FLAG_NO_INHERIT] {
                guard acl_get_flag_np(flags, flag) == 0 else { throw BackupFailure.unsupportedMetadata }
            }
            selector = Int32(ACL_NEXT_ENTRY.rawValue)
        }
        guard errno == EINVAL else { throw BackupFailure.unsupportedMetadata }
    }
    private static func noMetadata(_ fd: Int32) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            // Darwin reports absent extended ACL as ENOENT on an already validated open fd.
            guard errno == ENOENT else { throw BackupFailure.unsupportedMetadata }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else {
            throw BackupFailure.unsupportedMetadata
        }
    }
    private func xattrs(_ fd: Int32) throws -> [String: Data] {
        let count = flistxattr(fd, nil, 0, 0)
        guard count >= 0, count <= 65_536 else { throw BackupFailure.unsupportedMetadata }
        if count == 0 { return [:] }
        var names = [CChar](repeating: 0, count: count)
        guard flistxattr(fd, &names, count, 0) == count else { throw BackupFailure.changed }
        var result: [String: Data] = [:]; var total = 0
        for bytes in names.split(separator: 0) {
            guard let name = String(bytes: bytes.map({ UInt8(bitPattern: $0) }), encoding: .utf8) else { throw BackupFailure.unsupportedMetadata }
            let size = fgetxattr(fd, name, nil, 0, 0, 0)
            guard size >= 0, size <= 65_536, total + size <= 131_072 else { throw BackupFailure.unsupportedMetadata }
            var value = Data(count: size)
            let obtained = value.withUnsafeMutableBytes { fgetxattr(fd, name, $0.baseAddress, size, 0, 0) }
            guard obtained == size else { throw BackupFailure.changed }
            result[name] = value; total += size
        }
        return result
    }
    private func write(_ data: Data, name: String, directory: Int32) throws {
        let fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BackupFailure.io }; defer { close(fd) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw BackupFailure.io }; offset += count
            }
        }
        guard fsync(fd) == 0 else { throw BackupFailure.io }
        _ = try attributes(fd, privateMode: true)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func fingerprint(_ s: stat, _ data: Data, _ extendedAttributes: [String: Data]) -> SourceFingerprint {
        SourceFingerprint(device: s.st_dev, inode: s.st_ino, owner: s.st_uid, group: s.st_gid, mode: s.st_mode,
                          size: s.st_size, modifiedSeconds: Int64(s.st_mtimespec.tv_sec), modifiedNanos: Int64(s.st_mtimespec.tv_nsec),
                          changedSeconds: Int64(s.st_ctimespec.tv_sec), changedNanos: Int64(s.st_ctimespec.tv_nsec), sha256: digest(data), extendedAttributes: extendedAttributes)
    }
}

public enum VMLabProbeError: Error { case virtualMachineRequired, invalidLab }

extension VerifiedBackup {
    /// Fixed self-owned ISO01 experiment only. No caller-selected paths or source mutation.
    public static func runISO01VirtualMachineProbe() throws -> String {
        let context = try OwnedFixtureLabContext.createISO01()
        let receipt = try context.backup.prepare(name: context.sourceName, expected: context.fingerprint, planID: UUID())
        try context.backup.verify(receipt)
        guard try context.backup.inspect(name: context.sourceName) == context.fingerprint else { throw BackupFailure.changed }
        return "PASS ISO01 verified backup; sourceUnchanged=true; runtime=notInspected; productionGate=disabled; backupID=\(receipt.id.uuidString)"
    }
}

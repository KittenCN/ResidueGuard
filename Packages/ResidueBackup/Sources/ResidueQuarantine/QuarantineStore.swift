import Foundation
import CryptoKit
import Darwin
import ResidueBackup

public enum MoveState: String, Sendable {
    case notMoved
    case movedUnverified
    case quarantinedVerified
    case restoredVerified
}
public enum MoveReason: String, Sendable {
    case complete, invalidPlan, unsafeDirectory, backupInvalid, sourceInvalid, conflict
    case crossVolume, renameFailed, verificationFailed, durabilityFailed
}
public struct MoveOutcome: Equatable, Sendable {
    public let state: MoveState
    public let reason: MoveReason
}
private enum CheckFailure: Error { case unsafe, mismatch }

/// Isolated prototype. No public initializer, production factory, service operation or automatic compensation.
public final class QuarantineStore {
    private let source: Int32
    private let quarantine: Int32
    private let backup: VerifiedBackup
    // Deterministic test boundary used to model a competing change after preflight.
    var beforeRenameForTesting: (() throws -> Void)?
    var afterRenameForTesting: (() throws -> Void)?
    init(testSourceFD: Int32, testQuarantineFD: Int32, backup: VerifiedBackup) throws {
        let a = dup(testSourceFD), b = dup(testQuarantineFD)
        guard a >= 0, b >= 0 else {
            if a >= 0 { close(a) }; if b >= 0 { close(b) }; throw CheckFailure.unsafe
        }
        do {
            let x = try Self.directory(a, privateRequired: false)
            let y = try Self.directory(b, privateRequired: true)
            guard x.st_dev != y.st_dev || x.st_ino != y.st_ino else { throw CheckFailure.unsafe }
        } catch { close(a); close(b); throw error }
        source = a; quarantine = b; self.backup = backup
    }
    deinit { close(source); close(quarantine) }

    public func isolate(receipt: BackupReceipt, planID: UUID) -> MoveOutcome {
        move(receipt: receipt, planID: planID, restoring: false)
    }
    public func restore(receipt: BackupReceipt, planID: UUID) -> MoveOutcome {
        move(receipt: receipt, planID: planID, restoring: true)
    }
    /// Inspects the two fixed names bound by a caller-trusted receipt. Never retries or compensates.
    /// A candidate is only input to a new restoration plan, not permission to restore.
    public func inspectRecovery(receipt: BackupReceipt, planID: UUID) -> RecoveryInspection {
        func result(_ decision: RecoveryInspectionDecision, _ a: RecoveryObjectState = .unverified,
                    _ b: RecoveryObjectState = .unverified, verified: Bool = false) -> RecoveryInspection {
            .init(observedAt: Date(), source: a, quarantined: b, backupVerified: verified, decision: decision)
        }
        guard receipt.version == 1, receipt.planID == planID,
              Self.validName(receipt.sourceName) else { return result(.invalidPlan) }
        do {
            let a = try Self.directory(source, privateRequired: false)
            let b = try Self.directory(quarantine, privateRequired: true)
            guard a.st_dev == b.st_dev else { return result(.crossVolume) }
        } catch { return result(.unsafeStorage) }
        do { try backup.verify(receipt) } catch { return result(.invalidBackup) }
        let a = Self.observe(directory: source, name: receipt.sourceName, expected: receipt.fingerprint)
        let b = Self.observe(directory: quarantine, name: receipt.id.uuidString + ".plist", expected: receipt.fingerprint)
        do {
            _ = try Self.directory(source, privateRequired: false)
            _ = try Self.directory(quarantine, privateRequired: true)
            try backup.verify(receipt)
        } catch { return result(.unverified, a, b) }
        let decision: RecoveryInspectionDecision
        if a == .unverified || b == .unverified { decision = .unverified }
        else if a == .conflict || b == .conflict || (a == .matchesReceipt && b == .matchesReceipt) { decision = .conflict }
        else if a == .absent && b == .absent { decision = .objectsMissing }
        else if a == .matchesReceipt && b == .absent { decision = .sourcePresentNoMoveRequired }
        else { decision = .restoreCandidateRequiresNewPlan }
        return result(decision, a, b, verified: true)
    }
    private static func validName(_ name: String) -> Bool {
        name.hasSuffix(".plist") && name != ".plist" && !name.contains("/") &&
        !name.contains("\0") && name.utf8.count <= 255
    }
    private static func observe(directory: Int32, name: String, expected: SourceFingerprint) -> RecoveryObjectState {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT ? .absent : .unverified
        }
        guard info.st_mode & S_IFMT == S_IFREG else { return .conflict }
        do {
            return try snapshot(directory: directory, name: name).matches(expected, allowChangedTime: true)
                ? .matchesReceipt : .conflict
        } catch { return .unverified }
    }
    private func move(receipt: BackupReceipt, planID: UUID, restoring: Bool) -> MoveOutcome {
        func stopped(_ reason: MoveReason) -> MoveOutcome { .init(state: .notMoved, reason: reason) }
        let name = receipt.sourceName
        guard receipt.version == 1, receipt.planID == planID, Self.validName(name) else { return stopped(.invalidPlan) }
        let fromFD = restoring ? quarantine : source
        let toFD = restoring ? source : quarantine
        let quarantineName = receipt.id.uuidString + ".plist"
        let fromName = restoring ? quarantineName : name
        let toName = restoring ? name : quarantineName
        let fromDirectory: stat, toDirectory: stat
        do {
            fromDirectory = try Self.directory(fromFD, privateRequired: restoring)
            toDirectory = try Self.directory(toFD, privateRequired: !restoring)
        } catch { return stopped(.unsafeDirectory) }
        guard fromDirectory.st_dev == toDirectory.st_dev else { return stopped(.crossVolume) }
        do { try backup.verify(receipt) } catch { return stopped(.backupInvalid) }
        do {
            let current = try Self.snapshot(directory: fromFD, name: fromName)
            guard current.matches(receipt.fingerprint, allowChangedTime: restoring) else { return stopped(.sourceInvalid) }
        } catch { return stopped(.sourceInvalid) }
        guard Self.absent(directory: toFD, name: toName) else { return stopped(.conflict) }
        do { try beforeRenameForTesting?() } catch { return stopped(.sourceInvalid) }
        // RENAME_EXCL never falls back to overwriting rename or copy/unlink.
        guard renameatx_np(fromFD, fromName, toFD, toName, UInt32(RENAME_EXCL)) == 0 else {
            return stopped(errno == EEXIST ? .conflict : (errno == EXDEV ? .crossVolume : .renameFailed))
        }
        // From here any failure is explicitly potentially moved; do not rename back or delete an unexpected object.
        do {
            try afterRenameForTesting?()
            guard Self.absent(directory: fromFD, name: fromName),
                  try Self.snapshot(directory: toFD, name: toName).matches(receipt.fingerprint, allowChangedTime: true) else {
                return .init(state: .movedUnverified, reason: .verificationFailed)
            }
            _ = try Self.directory(fromFD, privateRequired: restoring)
            _ = try Self.directory(toFD, privateRequired: !restoring)
            try backup.verify(receipt)
        } catch { return .init(state: .movedUnverified, reason: .verificationFailed) }
        guard fsync(fromFD) == 0, fsync(toFD) == 0 else { return .init(state: .movedUnverified, reason: .durabilityFailed) }
        return .init(state: restoring ? .restoredVerified : .quarantinedVerified, reason: .complete)
    }
    private static func absent(directory: Int32, name: String) -> Bool {
        var result = stat()
        return fstatat(directory, name, &result, AT_SYMLINK_NOFOLLOW) == -1 && errno == ENOENT
    }
    /// Internal read-only experiment seam. A missing object is distinct from an unsafe read.
    static func inspectAuditFile(directoryFD: Int32, name: String, privateDirectory: Bool) throws -> Snapshot? {
        guard validName(name) else { throw CheckFailure.unsafe }
        _ = try directory(directoryFD, privateRequired: privateDirectory)
        var info = stat()
        if fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw CheckFailure.unsafe }
            return nil
        }
        return try snapshot(directory: directoryFD, name: name)
    }
    /// Fresh internal observation for the experiment journal; never mutation authority.
    func observeAuditObject(restored: Bool, receipt: BackupReceipt) throws -> Snapshot {
        _ = try Self.directory(source, privateRequired: false)
        _ = try Self.directory(quarantine, privateRequired: true)
        try backup.verify(receipt)
        let result = try Self.snapshot(directory: restored ? source : quarantine,
            name: restored ? receipt.sourceName : receipt.id.uuidString + ".plist")
        guard result.matches(receipt.fingerprint, allowChangedTime: true) else { throw CheckFailure.mismatch }
        return result
    }
    private static func directory(_ fd: Int32, privateRequired: Bool) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o7022 == 0, info.st_flags == 0,
              !privateRequired || info.st_mode & 0o7777 == 0o700 else { throw CheckFailure.unsafe }
        try noACL(fd)
        return info
    }
    private static func noACL(_ fd: Int32) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw CheckFailure.unsafe }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw CheckFailure.unsafe }
    }
    struct Snapshot {
        let info: stat
        let hash: String
        let attributes: [String: Data]
        func matches(_ expected: SourceFingerprint, allowChangedTime: Bool) -> Bool {
            info.st_dev == expected.device && info.st_ino == expected.inode && info.st_uid == expected.owner &&
            info.st_gid == expected.group && info.st_mode == expected.mode && info.st_size == expected.size &&
            Int64(info.st_mtimespec.tv_sec) == expected.modifiedSeconds && Int64(info.st_mtimespec.tv_nsec) == expected.modifiedNanos &&
            (allowChangedTime || (Int64(info.st_ctimespec.tv_sec) == expected.changedSeconds && Int64(info.st_ctimespec.tv_nsec) == expected.changedNanos)) &&
            hash == expected.sha256 && attributes == expected.extendedAttributes
        }
    }
    private static func snapshot(directory: Int32, name: String) throws -> Snapshot {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw CheckFailure.unsafe }; defer { close(fd) }
        let before = try fileInfo(fd)
        let attributes = try xattrs(fd)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw CheckFailure.unsafe }
            if count == 0 { break }
            guard data.count + count <= 1_048_576 else { throw CheckFailure.unsafe }
            data.append(contentsOf: buffer.prefix(count))
        }
        let after = try fileInfo(fd)
        var named = stat()
        guard stable(before, after), attributes == (try xattrs(fd)), data.count == before.st_size,
              fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0, stable(before, named) else { throw CheckFailure.mismatch }
        return Snapshot(info: before, hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), attributes: attributes)
    }
    private static func fileInfo(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o7022 == 0,
              info.st_flags == 0, info.st_size >= 0, info.st_size <= 1_048_576 else { throw CheckFailure.unsafe }
        try noACL(fd)
        return info
    }
    private static func stable(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_gid == b.st_gid &&
        a.st_mode == b.st_mode && a.st_nlink == b.st_nlink && a.st_flags == b.st_flags && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static func xattrs(_ fd: Int32) throws -> [String: Data] {
        let length = flistxattr(fd, nil, 0, 0)
        guard length >= 0, length <= 65_536 else { throw CheckFailure.unsafe }
        if length == 0 { return [:] }
        var names = [CChar](repeating: 0, count: length)
        guard flistxattr(fd, &names, length, 0) == length else { throw CheckFailure.mismatch }
        var result: [String: Data] = [:], total = 0
        for raw in names.split(separator: 0) {
            guard let name = String(bytes: raw.map({ UInt8(bitPattern: $0) }), encoding: .utf8) else { throw CheckFailure.unsafe }
            let size = fgetxattr(fd, name, nil, 0, 0, 0)
            guard size >= 0, size <= 65_536, total + size <= 131_072 else { throw CheckFailure.unsafe }
            var value = Data(count: size)
            guard value.withUnsafeMutableBytes({ fgetxattr(fd, name, $0.baseAddress, size, 0, 0) }) == size else { throw CheckFailure.mismatch }
            result[name] = value; total += size
        }
        return result
    }
}

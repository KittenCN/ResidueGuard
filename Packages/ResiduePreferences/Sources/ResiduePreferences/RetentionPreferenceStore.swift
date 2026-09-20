import CryptoKit
import Darwin
import Foundation

public enum RetentionPreferenceError: Error, Equatable, Sendable {
    case unsafeStorage, ioFailure, oversized, unsupportedVersion, corrupt, conflict, busy
    /// Replacement may already be durable. Caller must reread; never blindly retry.
    case writeOutcomeUnknown
}

public struct RetentionPreferenceSnapshot: Equatable, Sendable {
    public let data: Data
    public let revision: String
}

/// App-owned configuration only; never a privileged executor trust root.
/// The caller supplies its existing sandbox Application Support directory and
/// runs these synchronous APIs off the main actor. No source cleanup is exposed.
public final class RetentionPreferenceStore: Sendable {
    public static let maximumDataBytes = 128 * 1024
    public static let maximumEnvelopeBytes = 180_000
    private let parent: URL
    private static let folderName = "ResidueGuard"
    private static let fileName = "retention.json"
    private static let lockName = "retention.lock"
    private struct Envelope: Codable { let version: Int; let revision: String; let data: Data }
    enum WritePhase { case beforeRename, afterRename, beforeDirectorySync }

    public init(applicationSupportDirectory: URL) throws {
        let path = applicationSupportDirectory.path
        guard applicationSupportDirectory.isFileURL, path.hasPrefix("/"), !path.contains("\0"),
              !applicationSupportDirectory.path(percentEncoded: true).contains("%00"), path.utf8.count < Int(PATH_MAX),
              applicationSupportDirectory.host == nil || applicationSupportDirectory.host == "" || applicationSupportDirectory.host == "localhost" else { throw RetentionPreferenceError.unsafeStorage }
        parent = applicationSupportDirectory
        let fd = try openParent(); close(fd)
    }

    /// Fresh-sandbox entry points. Library must already exist and belong to the
    /// caller's sandbox; only the fixed Application Support child may be created.
    /// Reading never bootstraps directories. This is not a privilege boundary.
    public static func read(sandboxLibraryDirectory: URL) throws -> RetentionPreferenceSnapshot? {
        guard let support = try applicationSupport(in: sandboxLibraryDirectory, create: false) else { return nil }
        return try Self(applicationSupportDirectory: support).read()
    }

    public static func save(data: Data, expectedRevision: String?, sandboxLibraryDirectory: URL) throws -> RetentionPreferenceSnapshot {
        try Task.checkCancellation()
        guard data.count <= maximumDataBytes else { throw RetentionPreferenceError.oversized }
        guard expectedRevision == nil || validRevision(expectedRevision!) else { throw RetentionPreferenceError.conflict }
        guard let support = try applicationSupport(in: sandboxLibraryDirectory, create: true) else { throw RetentionPreferenceError.ioFailure }
        return try Self(applicationSupportDirectory: support).save(data: data, expectedRevision: expectedRevision)
    }

    private static func applicationSupport(in library: URL, create: Bool) throws -> URL? {
        try Task.checkCancellation()
        // Reuse the existing full-chain, ownership, mode and ACL validation for
        // the caller-provided Library. No recursive directory creation is used.
        let anchor = try Self(applicationSupportDirectory: library)
        let libraryFD = try anchor.openParent(); defer { close(libraryFD) }
        let name = "Application Support"
        if create {
            try Task.checkCancellation()
            if mkdirat(libraryFD, name, 0o700) != 0, errno != EEXIST { throw RetentionPreferenceError.ioFailure }
        }
        let fd = openat(libraryFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw RetentionPreferenceError.unsafeStorage
        }
        defer { close(fd) }
        let support = library.appendingPathComponent(name, isDirectory: true)
        let validated = try Self(applicationSupportDirectory: support)
        let current = try validated.openParent(); defer { close(current) }
        var opened = stat(), named = stat()
        guard fstat(fd, &opened) == 0, fstat(current, &named) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else { throw RetentionPreferenceError.unsafeStorage }
        try Task.checkCancellation()
        return support
    }

    /// Missing configuration returns nil, without creating a directory or lock.
    /// Corrupt, unreadable or unsafe storage is an error, never an empty setting.
    public func read() throws -> RetentionPreferenceSnapshot? {
        try Task.checkCancellation()
        let parentFD = try openParent(); defer { close(parentFD) }
        guard let directoryFD = try openDirectory(parentFD, create: false) else { return nil }
        defer { close(directoryFD) }
        // A genuinely absent config needs no lock creation. Recheck after locking
        // when present; cooperating saves are serialized by the same lock inode.
        var info = stat()
        if fstatat(directoryFD, Self.fileName, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw RetentionPreferenceError.ioFailure }
            return nil
        }
        let lock = try acquireLock(directoryFD); defer { flock(lock, LOCK_UN); close(lock) }
        try checkDirectory(parentFD, directoryFD)
        try checkLock(directoryFD, lock)
        let loaded = try load(directoryFD)
        try checkDirectory(parentFD, directoryFD)
        try checkLock(directoryFD, lock)
        return loaded?.snapshot
    }

    /// nil revision means create-if-absent; an update requires the last observed hash.
    public func save(data: Data, expectedRevision: String?) throws -> RetentionPreferenceSnapshot {
        try save(data: data, expectedRevision: expectedRevision, checkpoint: { _ in try Task.checkCancellation() })
    }

    // Deterministic failure boundary injection is internal, not an application API.
    func save(data: Data, expectedRevision: String?, checkpoint: (WritePhase) throws -> Void) throws -> RetentionPreferenceSnapshot {
        try Task.checkCancellation()
        guard data.count <= Self.maximumDataBytes else { throw RetentionPreferenceError.oversized }
        if let expectedRevision, !Self.validRevision(expectedRevision) { throw RetentionPreferenceError.conflict }
        let revision = Self.hash(data)
        let bytes = try Self.encode(Envelope(version: 1, revision: revision, data: data))
        guard bytes.count <= Self.maximumEnvelopeBytes else { throw RetentionPreferenceError.oversized }
        let parentFD = try openParent(); defer { close(parentFD) }
        guard let directoryFD = try openDirectory(parentFD, create: true) else { throw RetentionPreferenceError.ioFailure }
        defer { close(directoryFD) }
        let lock = try acquireLock(directoryFD); defer { flock(lock, LOCK_UN); close(lock) }
        try checkDirectory(parentFD, directoryFD)
        let current = try load(directoryFD)
        guard current?.snapshot.revision == expectedRevision else { throw RetentionPreferenceError.conflict }
        let temporary = ".retention-" + UUID().uuidString + ".tmp"
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RetentionPreferenceError.ioFailure }
        defer { close(fd); unlinkat(directoryFD, temporary, 0) }
        try requirePrivateFile(fd)
        try write(bytes, to: fd)
        guard fsync(fd) == 0 else { throw RetentionPreferenceError.ioFailure }
        try checkpoint(.beforeRename)
        try Task.checkCancellation()
        try checkDirectory(parentFD, directoryFD)
        try checkLock(directoryFD, lock)
        let fresh = try load(directoryFD)
        guard fresh?.snapshot.revision == expectedRevision,
              fresh?.identity == current?.identity else { throw RetentionPreferenceError.conflict }
        // The cooperating-process lock serializes this compare-and-replace. It is
        // advisory, not protection against a malicious process with the same UID.
        let renamed: Int32
        if current == nil { renamed = renameatx_np(directoryFD, temporary, directoryFD, Self.fileName, UInt32(RENAME_EXCL)) }
        else { renamed = renameat(directoryFD, temporary, directoryFD, Self.fileName) }
        guard renamed == 0 else {
            if errno == EEXIST { throw RetentionPreferenceError.conflict }
            throw RetentionPreferenceError.ioFailure
        }
        do {
            try checkpoint(.afterRename)
            try Task.checkCancellation()
            try checkDirectory(parentFD, directoryFD)
            try checkLock(directoryFD, lock)
            let installed = try load(directoryFD)
            guard installed?.snapshot == RetentionPreferenceSnapshot(data: data, revision: revision) else { throw RetentionPreferenceError.ioFailure }
            try checkpoint(.beforeDirectorySync)
            guard fsync(directoryFD) == 0, fsync(parentFD) == 0 else { throw RetentionPreferenceError.ioFailure }
            try Task.checkCancellation()
        } catch { throw RetentionPreferenceError.writeOutcomeUnknown }
        return RetentionPreferenceSnapshot(data: data, revision: revision)
    }

    private func openParent() throws -> Int32 {
        let fd = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard fd >= 0 else { throw RetentionPreferenceError.unsafeStorage }
        do {
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o022 == 0 else { throw RetentionPreferenceError.unsafeStorage }
            try Self.noACL(fd)
            return fd
        } catch { close(fd); throw error }
    }
    private func openDirectory(_ parentFD: Int32, create: Bool) throws -> Int32? {
        if create, mkdirat(parentFD, Self.folderName, 0o700) != 0, errno != EEXIST { throw RetentionPreferenceError.ioFailure }
        let fd = openat(parentFD, Self.folderName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw RetentionPreferenceError.unsafeStorage
        }
        do { try checkDirectory(parentFD, fd); return fd }
        catch { close(fd); throw error }
    }
    private func checkDirectory(_ parentFD: Int32, _ directoryFD: Int32) throws {
        let freshParent = try openParent(); defer { close(freshParent) }
        var originalParent = stat(), currentParent = stat(), opened = stat(), named = stat()
        guard fstat(parentFD, &originalParent) == 0, fstat(freshParent, &currentParent) == 0,
              originalParent.st_dev == currentParent.st_dev, originalParent.st_ino == currentParent.st_ino,
              fstat(directoryFD, &opened) == 0, fstatat(parentFD, Self.folderName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              named.st_mode & S_IFMT == S_IFDIR, named.st_uid == geteuid(), named.st_mode & 0o7777 == 0o700 else { throw RetentionPreferenceError.unsafeStorage }
        try Self.noACL(directoryFD)
    }
    private func requirePrivateFile(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o7777 == 0o600, info.st_nlink == 1 else { throw RetentionPreferenceError.unsafeStorage }
        try Self.noACL(fd)
    }
    private func acquireLock(_ directoryFD: Int32) throws -> Int32 {
        let fd = openat(directoryFD, Self.lockName, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RetentionPreferenceError.unsafeStorage }
        do {
            try requirePrivateFile(fd)
            let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                try Task.checkCancellation()
                guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else { throw RetentionPreferenceError.ioFailure }
                guard DispatchTime.now().uptimeNanoseconds < deadline else { throw RetentionPreferenceError.busy }
                usleep(10_000)
            }
            try checkLock(directoryFD, fd)
            return fd
        } catch { close(fd); throw error }
    }
    private func checkLock(_ directoryFD: Int32, _ fd: Int32) throws {
        try requirePrivateFile(fd)
        var opened = stat(), named = stat()
        guard fstat(fd, &opened) == 0, fstatat(directoryFD, Self.lockName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else { throw RetentionPreferenceError.unsafeStorage }
    }
    private struct Identity: Equatable { let device: dev_t; let inode: ino_t; let size: off_t; let modifiedSeconds: Int; let modifiedNanos: Int; let changedSeconds: Int; let changedNanos: Int }
    private struct Loaded { let snapshot: RetentionPreferenceSnapshot; let identity: Identity }
    private func identity(_ fd: Int32) throws -> Identity {
        var s = stat(); guard fstat(fd, &s) == 0 else { throw RetentionPreferenceError.ioFailure }
        return Identity(device: s.st_dev, inode: s.st_ino, size: s.st_size, modifiedSeconds: s.st_mtimespec.tv_sec, modifiedNanos: s.st_mtimespec.tv_nsec, changedSeconds: s.st_ctimespec.tv_sec, changedNanos: s.st_ctimespec.tv_nsec)
    }
    private func load(_ directoryFD: Int32) throws -> Loaded? {
        let fd = openat(directoryFD, Self.fileName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw RetentionPreferenceError.unsafeStorage
        }
        defer { close(fd) }
        try requirePrivateFile(fd)
        let before = try identity(fd)
        guard before.size >= 0, before.size <= Self.maximumEnvelopeBytes else { throw RetentionPreferenceError.oversized }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count <= Self.maximumEnvelopeBytes {
            try Task.checkCancellation()
            let amount = min(buffer.count, Self.maximumEnvelopeBytes + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, amount) }
            if count < 0 { if errno == EINTR { continue }; throw RetentionPreferenceError.ioFailure }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= Self.maximumEnvelopeBytes else { throw RetentionPreferenceError.oversized }
        try requirePrivateFile(fd)
        guard try identity(fd) == before else { throw RetentionPreferenceError.conflict }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw RetentionPreferenceError.corrupt }
        guard envelope.version == 1 else { throw RetentionPreferenceError.unsupportedVersion }
        guard envelope.data.count <= Self.maximumDataBytes else { throw RetentionPreferenceError.oversized }
        guard Self.validRevision(envelope.revision), Self.hash(envelope.data) == envelope.revision,
              try Self.encode(envelope) == data else { throw RetentionPreferenceError.corrupt }
        return Loaded(snapshot: .init(data: envelope.data, revision: envelope.revision), identity: before)
    }
    private func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), min(16_384, bytes.count - offset))
                if count < 0 { if errno == EINTR { continue }; throw RetentionPreferenceError.ioFailure }
                guard count > 0 else { throw RetentionPreferenceError.ioFailure }
                offset += count
            }
        }
    }
    private static func encode(_ envelope: Envelope) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try encoder.encode(envelope) }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validRevision(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private static func noACL(_ fd: Int32) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw RetentionPreferenceError.unsafeStorage }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?; errno = 0
        guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw RetentionPreferenceError.unsafeStorage }
    }
}

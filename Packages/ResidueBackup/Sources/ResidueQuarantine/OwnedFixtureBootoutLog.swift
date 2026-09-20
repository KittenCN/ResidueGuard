import Foundation
import Darwin
import CryptoKit

/// Private experiment evidence, never an imported plan or permission to replay.
final class OwnedBootoutLog {
    enum Slot: String, Codable, CaseIterable { case intent, preflight, outcome, observation }
    private struct Envelope: Codable {
        let version: Int
        let attempt: UUID
        let slot: Slot
        let payload: Data
        let sha256: String
    }
    private let fd: Int32
    private let root: stat
    private let path: String
    private let attempt: UUID
    private let readOnly: Bool
    init(directoryFD: Int32, attempt: UUID = UUID(), readOnly: Bool = false) throws {
        let copy = dup(directoryFD)
        guard copy >= 0 else { throw OwnedBootoutError.storage }
        do {
            root = try Self.safe(copy, directory: true)
            var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
            guard fcntl(copy, F_GETPATH, &bytes) == 0 else { throw OwnedBootoutError.storage }
            path = bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            fd = copy; self.attempt = attempt; self.readOnly = readOnly
        } catch { close(copy); throw error }
    }
    deinit { close(fd) }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func safe(_ file: Int32, directory: Bool) throws -> stat {
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == getuid(), info.st_flags == 0,
              info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              info.st_mode & 0o7777 == (directory ? 0o700 : 0o600),
              directory || (info.st_nlink == 1 && info.st_size >= 0 && info.st_size <= 3_145_728) else { throw OwnedBootoutError.storage }
        if let acl = acl_get_fd_np(file, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?; errno = 0
            guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw OwnedBootoutError.storage }
        } else if errno != ENOENT { throw OwnedBootoutError.storage }
        return info
    }
    private func checkRoot() throws {
        let saved = try Self.safe(fd, directory: true)
        var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw OwnedBootoutError.storage }
        for name in path.split(separator: "/") {
            let next = openat(current, String(name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(current)
            guard next >= 0 else { throw OwnedBootoutError.storage }
            current = next
        }
        defer { close(current) }
        let fresh = try Self.safe(current, directory: true)
        guard saved.st_dev == root.st_dev, saved.st_ino == root.st_ino,
              fresh.st_dev == root.st_dev, fresh.st_ino == root.st_ino else { throw OwnedBootoutError.storage }
    }
    private func name(_ slot: Slot) -> String { "owned-bootout-" + slot.rawValue + ".json" }
    private func checkFile(_ file: Int32, slot: Slot) throws -> stat {
        let opened = try Self.safe(file, directory: false)
        var named = stat()
        guard fstatat(fd, name(slot), &named, AT_SYMLINK_NOFOLLOW) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else { throw OwnedBootoutError.storage }
        return opened
    }
    func append<T: Encodable>(_ slot: Slot, _ value: T) throws {
        guard !readOnly else { throw OwnedBootoutError.storage }
        try checkRoot()
        let prior = try readAll()
        guard prior[slot] == nil, slot == .intent ? prior.isEmpty : prior[.intent] != nil,
              slot != .preflight || prior[.outcome] == nil,
              slot != .observation || prior[.outcome] != nil else { throw OwnedBootoutError.storage }
        let payload = try Self.encode(value)
        guard payload.count <= 2_097_152 else { throw OwnedBootoutError.storage }
        let data = try Self.encode(Envelope(version: 1, attempt: attempt, slot: slot, payload: payload, sha256: Self.hash(payload)))
        guard data.count <= 3_145_728 else { throw OwnedBootoutError.storage }
        let file = openat(fd, name(slot), O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw OwnedBootoutError.storage }
        defer { close(file) }
        _ = try checkFile(file, slot: slot)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw OwnedBootoutError.storage }
                offset += count
            }
        }
        guard fsync(file) == 0, fcntl(file, F_FULLFSYNC) == 0, fsync(fd) == 0 else { throw OwnedBootoutError.storage }
        _ = try checkFile(file, slot: slot); try checkRoot()
        guard try readAll()[slot] == payload else { throw OwnedBootoutError.storage }
    }
    /// Opens only fixed files O_RDONLY; no sidecars, repairs, overwrite or replay.
    func readAll() throws -> [Slot: Data] {
        try checkRoot()
        var results: [Slot: Data] = [:]
        for slot in Slot.allCases {
            let file = openat(fd, name(slot), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if file < 0 { if errno == ENOENT { continue }; throw OwnedBootoutError.storage }
            defer { close(file) }
            let before = try checkFile(file, slot: slot)
            var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = read(file, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0, data.count + max(0, count) <= 3_145_728 else { throw OwnedBootoutError.storage }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            let after = try checkFile(file, slot: slot)
            guard before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec, data.count == after.st_size else { throw OwnedBootoutError.storage }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1, envelope.attempt == attempt, envelope.slot == slot,
                  Self.hash(envelope.payload) == envelope.sha256, try Self.encode(envelope) == data else { throw OwnedBootoutError.storage }
            // Payloads with their own attempt must agree with the envelope.
            if let object = try JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any], let id = object["attempt"] as? String {
                guard id == attempt.uuidString else { throw OwnedBootoutError.storage }
            }
            results[slot] = envelope.payload
        }
        guard results.isEmpty || results[.intent] != nil,
              results[.observation] == nil || results[.outcome] != nil else { throw OwnedBootoutError.storage }
        try checkRoot()
        return results
    }
}

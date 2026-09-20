import CSQLite
import Darwin
import Foundation

/// Dedicated database; no production journal tables, plan conversion or nonce reuse.
final class OwnedExperimentStorage: @unchecked Sendable {
    private var db: OpaquePointer?
    private let directoryFD: Int32
    private var fileFD: Int32 = -1
    private let path: String
    private let name = "owned-fixture-experiment.sqlite"
    private static let schema = "CREATE TABLE experiments(id TEXT PRIMARY KEY NOT NULL,payload TEXT NOT NULL,digest TEXT NOT NULL)"
    private var initializing = true
    private var poisoned = false
    private let readOnly: Bool
    init(directoryFD supplied: Int32, createNew: Bool, readOnly: Bool) throws {
        guard !readOnly || !createNew else { throw JournalError.invalidInput }
        self.readOnly = readOnly
        directoryFD = dup(supplied)
        guard directoryFD >= 0 else { throw JournalError.unsafeStorage }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(directoryFD, F_GETPATH, &buffer) == 0 else { close(directoryFD); throw JournalError.unsafeStorage }
        path = String(cString: buffer)
        do {
            try checkDirectory()
            fileFD = openat(directoryFD, name, (readOnly ? O_RDONLY : O_RDWR) | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (createNew ? O_CREAT | O_EXCL : 0), 0o600)
            guard fileFD >= 0 else { throw JournalError.unsafeStorage }
            try check()
            guard sqlite3_open_v2(path + "/" + name, &db, (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE) | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK,
                  sqlite3_busy_timeout(db, 2000) == SQLITE_OK else { throw JournalError.storageFailure }
            sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 262144)
            try execute("PRAGMA trusted_schema=OFF")
            if !createNew { try verifySchema() }
            if readOnly {
                try execute("PRAGMA query_only=ON")
                guard try integer("PRAGMA query_only") == 1 else { throw JournalError.storageFailure }
            } else {
                guard try rows("PRAGMA journal_mode=DELETE") == [["delete"]] else { throw JournalError.storageFailure }
                try execute("PRAGMA synchronous=FULL"); try execute("PRAGMA fullfsync=ON")
                guard try integer("PRAGMA synchronous") == 2, try integer("PRAGMA fullfsync") == 1 else { throw JournalError.storageFailure }
            }
            if createNew {
                try transaction {
                    try execute(Self.schema)
                    try execute("PRAGMA application_id=1380403781")
                    try execute("PRAGMA user_version=1")
                }
                guard fsync(directoryFD) == 0 else { throw JournalError.storageFailure }
            }
            try verifySchema()
            guard try rows("PRAGMA integrity_check") == [["ok"]] else { throw JournalError.storageFailure }
            initializing = false
            try check()
        } catch {
            if db != nil { sqlite3_close_v2(db); db = nil }
            if fileFD >= 0 { close(fileFD); fileFD = -1 }
            close(directoryFD)
            throw error
        }
    }
    deinit { if db != nil { sqlite3_close_v2(db) }; if fileFD >= 0 { close(fileFD) }; close(directoryFD) }
    private func checkDirectory() throws {
        let fresh = try Storage.openDirectory(path); defer { close(fresh) }
        var a = stat(), b = stat()
        guard fstat(directoryFD, &a) == 0, fstat(fresh, &b) == 0, a.st_dev == b.st_dev, a.st_ino == b.st_ino else { throw JournalError.unsafeStorage }
    }
    private func safeFile(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o7777 == 0o600,
              info.st_uid == geteuid(), info.st_nlink == 1 else { throw JournalError.unsafeStorage }
        guard info.st_size <= 16 * 1024 * 1024 else { throw JournalError.resourceLimit }
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            guard errno == ENOENT else { throw JournalError.unsafeStorage }; return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?; errno = 0
        guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else { throw JournalError.unsafeStorage }
    }
    private func check() throws {
        do { try checkImpl() } catch { poisoned = true; throw error }
    }
    private func checkImpl() throws {
        guard !poisoned else { throw JournalError.storageFailure }
        try checkDirectory(); try safeFile(fileFD)
        var opened = stat(), named = stat()
        guard fstat(fileFD, &opened) == 0, fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else { throw JournalError.unsafeStorage }
        for suffix in ["-journal", "-wal", "-shm"] {
            if fstatat(directoryFD, name + suffix, &named, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw JournalError.unsafeStorage }; continue
            }
            guard suffix == "-journal" else { throw JournalError.unsafeStorage }
            let fd = openat(directoryFD, name + suffix, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if fd < 0 { if errno == ENOENT { continue }; throw JournalError.unsafeStorage }
            defer { close(fd) }; try safeFile(fd)
        }
    }
    private func verifySchema() throws {
        guard try integer("PRAGMA user_version") == 1, try integer("PRAGMA application_id") == 1380403781,
              try rows("SELECT sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name") == [[Self.schema]] else { throw JournalError.unsupportedSchema }
    }
    func snapshot<T>(_ body: () throws -> T) throws -> T {
        try check(); try execute("BEGIN DEFERRED")
        do {
            try verifySchema(); let result = try body(); try check(); try execute("COMMIT"); return result
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func transaction(_ body: () throws -> Void) throws {
        guard !readOnly else { throw JournalError.invalidTransition }
        try check(); try execute("BEGIN IMMEDIATE")
        do {
            if !initializing { try verifySchema() }
            try body(); try check()
            #if DEBUG
            if let checkpoint = JournalCrashCheckpoint.beforeCommit {
                guard sqlite3_db_cacheflush(db) == SQLITE_OK else { throw JournalError.storageFailure }
                checkpoint("ownedExperiment")
            }
            #endif
            do { try execute("COMMIT"); try check() }
            catch { poisoned = true; throw error }
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func execute(_ sql: String, _ arguments: [String] = []) throws { _ = try rows(sql, arguments) }
    func integer(_ sql: String, _ arguments: [String] = []) throws -> Int {
        guard let row = try rows(sql, arguments).first, let text = row[0], let value = Int(text) else { throw JournalError.storageFailure }; return value
    }
    func rows(_ sql: String, _ arguments: [String] = []) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw JournalError.storageFailure }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, argument) in arguments.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), argument, -1, transient) == SQLITE_OK else { throw JournalError.storageFailure }
        }
        var result: [[String?]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, result.count < 256 else { throw JournalError.storageFailure }
            var row: [String?] = []
            for index in 0..<sqlite3_column_count(statement) {
                guard sqlite3_column_bytes(statement, index) <= 131072 else { throw JournalError.resourceLimit }
                if sqlite3_column_type(statement, index) == SQLITE_NULL { row.append(nil) }
                else {
                    guard let bytes = sqlite3_column_text(statement, index) else { throw JournalError.storageFailure }
                    let count = Int(sqlite3_column_bytes(statement, index))
                    guard let value = String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8) else { throw JournalError.storageFailure }
                    row.append(value)
                }
            }
            result.append(row)
        }
    }
}

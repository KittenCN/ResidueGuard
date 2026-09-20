import CSQLite
import Darwin
import Foundation

public enum JournalError: Error, Equatable, Sendable {
    case unsafeStorage, storageFailure, unsupportedSchema, invalidInput, replay, invalidTransition
}

public enum StepResult: String, Sendable { case succeeded, failed, unverified }

public struct JournalStep: Equatable, Sendable {
    public let index: Int
    public let operationID: String
    public let result: StepResult?
}

public struct JournalEntry: Equatable, Sendable {
    public let planID: String
    public let digest: String
    public let steps: [JournalStep]
    public let finished: Bool
}

/// Audit persistence only. This type never executes, retries, or authorizes an operation.
public actor TransactionJournal {
    private let storage: Storage

    /// The directory must already exist, be owned by the current effective UID, and be 0700.
    /// All path components must be real directories (use a canonical path, without symlinks).
    /// Pass createNew only for explicit first-time provisioning; it refuses an existing database.
    /// Normal startup never creates/replaces a missing database or resets replay protection.
    public init(directory: URL, createNew: Bool = false) throws {
        storage = try Storage(directory: directory, createNew: createNew)
    }

    /// Atomically consumes both identifiers. They remain consumed even after failure or restart.
    public func claim(planID: String, digest: String, nonce: String) throws {
        try validate([planID, digest, nonce])
        try storage.transaction {
            guard try storage.integer("SELECT count(*) FROM plans WHERE plan_id=? OR nonce=?", [planID, nonce]) == 0 else {
                throw JournalError.replay
            }
            try storage.execute("INSERT INTO plans(plan_id,digest,nonce,finished) VALUES(?,?,?,0)", [planID, digest, nonce])
        }
    }

    /// Commit this record successfully BEFORE performing the corresponding system mutation.
    public func prepare(planID: String, operationID: String) throws {
        try validate([planID, operationID])
        try storage.transaction {
            try requireOpen(planID)
            guard try storage.integer("SELECT count(*) FROM steps WHERE plan_id=? AND (result IS NULL OR result!='succeeded')", [planID]) == 0,
                  try storage.integer("SELECT count(*) FROM steps WHERE plan_id=? AND operation_id=?", [planID, operationID]) == 0 else {
                throw JournalError.invalidTransition
            }
            try storage.execute("INSERT INTO steps(plan_id,step_index,operation_id,result) SELECT ?,count(*),?,NULL FROM steps WHERE plan_id=?", [planID, operationID, planID])
        }
    }

    /// An unverified/failed result blocks subsequent steps. It does not imply rollback.
    public func recordResult(planID: String, operationID: String, result: StepResult) throws {
        try validate([planID, operationID])
        try storage.transaction {
            try requireOpen(planID)
            guard try storage.integer("SELECT count(*) FROM steps WHERE plan_id=? AND operation_id=? AND result IS NULL", [planID, operationID]) == 1 else {
                throw JournalError.invalidTransition
            }
            try storage.execute("UPDATE steps SET result=? WHERE plan_id=? AND operation_id=?", [result.rawValue, planID, operationID])
        }
    }

    /// Marks audit bookkeeping complete, not success. Prepared steps without a result cannot finish.
    public func finish(planID: String) throws {
        try validate([planID])
        try storage.transaction {
            try requireOpen(planID)
            guard try storage.integer("SELECT count(*) FROM steps WHERE plan_id=? AND result IS NULL", [planID]) == 0 else {
                throw JournalError.invalidTransition
            }
            try storage.execute("UPDATE plans SET finished=1 WHERE plan_id=?", [planID])
        }
    }

    /// Startup recovery is observation only; no records are resumed or marked complete.
    public func unfinishedEntries() throws -> [JournalEntry] {
        return try storage.snapshot {
            try storage.rows("SELECT plan_id,digest FROM plans WHERE finished=0 ORDER BY rowid").map { row in
                guard let planID = row[0], let digest = row[1] else { throw JournalError.storageFailure }
                let steps = try storage.rows("SELECT step_index,operation_id,result FROM steps WHERE plan_id=? ORDER BY step_index", [planID]).map { item in
                    guard let indexText = item[0], let index = Int(indexText), let operation = item[1] else { throw JournalError.storageFailure }
                    let result = item[2].flatMap(StepResult.init(rawValue:))
                    if item[2] != nil && result == nil { throw JournalError.storageFailure }
                    return JournalStep(index: index, operationID: operation, result: result)
                }
                return JournalEntry(planID: planID, digest: digest, steps: steps, finished: false)
            }
        }
    }

    private func requireOpen(_ planID: String) throws {
        guard try storage.integer("SELECT count(*) FROM plans WHERE plan_id=? AND finished=0", [planID]) == 1 else {
            throw JournalError.invalidTransition
        }
    }

    private func validate(_ values: [String]) throws {
        guard values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 && !$0.contains("\0") }) else { throw JournalError.invalidInput }
    }
}

// OpaquePointer lifetime is owned by this wrapper, used exclusively by its owning actor.
private final class Storage: @unchecked Sendable {
    private var db: OpaquePointer?
    private let directory: String
    private var directoryFD: Int32 = -1
    private var fileFD: Int32 = -1
    private let fileName = "journal.sqlite"
    private var poisoned = false
    private static let planSchema = "CREATE TABLE plans(plan_id TEXT PRIMARY KEY NOT NULL,digest TEXT NOT NULL,nonce TEXT UNIQUE NOT NULL,finished INTEGER NOT NULL CHECK(finished IN (0,1)))"
    private static let stepSchema = "CREATE TABLE steps(plan_id TEXT NOT NULL REFERENCES plans(plan_id),step_index INTEGER NOT NULL CHECK(step_index>=0),operation_id TEXT NOT NULL,result TEXT CHECK(result IN ('succeeded','failed','unverified')),PRIMARY KEY(plan_id,step_index),UNIQUE(plan_id,operation_id))"

    init(directory url: URL, createNew: Bool) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.pathComponents.contains("..") else { throw JournalError.unsafeStorage }
        directory = url.path
        do {
            directoryFD = try Self.openDirectory(directory)
            let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC
            fileFD = openat(directoryFD, fileName, createNew ? flags | O_CREAT | O_EXCL : flags, 0o600)
            let created = createNew
            guard fileFD >= 0 else { throw JournalError.unsafeStorage }
            try checkIdentity()
            let sqliteFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
            guard sqlite3_open_v2(directory + "/" + fileName, &db, sqliteFlags, nil) == SQLITE_OK else { throw JournalError.storageFailure }
            guard sqlite3_busy_timeout(db, 2000) == SQLITE_OK else { throw JournalError.storageFailure }
            try execute("PRAGMA trusted_schema=OFF")
            try execute("PRAGMA foreign_keys=ON")
            // Refuse unknown journals before changing their SQLite journaling mode.
            if !created {
                guard try integer("PRAGMA user_version") == 1,
                      try integer("PRAGMA application_id") == 1380403780 else { throw JournalError.unsupportedSchema }
                guard try rows("SELECT sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name") == [[Self.planSchema], [Self.stepSchema]] else {
                    throw JournalError.unsupportedSchema
                }
            }
            guard try rows("PRAGMA journal_mode=DELETE") == [["delete"]] else { throw JournalError.storageFailure }
            try execute("PRAGMA synchronous=FULL")
            try execute("PRAGMA fullfsync=ON")
            guard try integer("PRAGMA synchronous") == 2,
                  try integer("PRAGMA fullfsync") == 1,
                  try integer("PRAGMA foreign_keys") == 1 else { throw JournalError.storageFailure }
            if created {
                try transaction {
                    try execute(Self.planSchema)
                    try execute(Self.stepSchema)
                    try execute("PRAGMA application_id=1380403780")
                    try execute("PRAGMA user_version=1")
                }
                guard fsync(directoryFD) == 0 else { throw JournalError.storageFailure }
            }
            guard try integer("PRAGMA user_version") == 1,
                  try integer("PRAGMA application_id") == 1380403780 else { throw JournalError.unsupportedSchema }
            guard try rows("PRAGMA integrity_check") == [["ok"]],
                  try rows("PRAGMA foreign_key_check").isEmpty else { throw JournalError.storageFailure }
            guard try rows("SELECT sql FROM sqlite_schema WHERE sql IS NOT NULL ORDER BY name") == [[Self.planSchema], [Self.stepSchema]] else {
                throw JournalError.unsupportedSchema
            }
            // Preparing these statements detects a missing/changed schema without recreating tables.
            _ = try rows("SELECT plan_id,digest,nonce,finished FROM plans LIMIT 0")
            _ = try rows("SELECT plan_id,step_index,operation_id,result FROM steps LIMIT 0")
            try checkIdentity()
        } catch {
            if db != nil { sqlite3_close_v2(db); db = nil }
            if fileFD >= 0 { close(fileFD); fileFD = -1 }
            if directoryFD >= 0 { close(directoryFD); directoryFD = -1 }
            throw error
        }
    }

    deinit {
        if db != nil { sqlite3_close_v2(db) }
        if fileFD >= 0 { close(fileFD) }
        if directoryFD >= 0 { close(directoryFD) }
    }

    static func openDirectory(_ path: String) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw JournalError.unsafeStorage }
        do {
            let parts = path.split(separator: "/")
            guard !parts.isEmpty else { throw JournalError.unsafeStorage }
            for (index, component) in parts.enumerated() {
                guard component != ".", component != ".." else { throw JournalError.unsafeStorage }
                let next = openat(fd, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw JournalError.unsafeStorage }
                close(fd); fd = next
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_uid == geteuid() || info.st_uid == 0 else { throw JournalError.unsafeStorage }
                if index == parts.count - 1 {
                    guard info.st_uid == geteuid(), info.st_mode & 0o7777 == 0o700 else { throw JournalError.unsafeStorage }
                    try requireNoACL(fd)
                } else if info.st_mode & 0o022 != 0 {
                    guard info.st_uid == 0, info.st_mode & S_ISVTX != 0 else { throw JournalError.unsafeStorage }
                }
            }
            return fd
        } catch { close(fd); throw error }
    }

    private static func requireNoACL(_ fd: Int32) throws {
        guard let acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED) else {
            // Darwin reports ENOENT for the absent extended ACL on an open, validated fd.
            guard errno == ENOENT else { throw JournalError.unsafeStorage }
            return
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        // macOS returns 0 for an entry and -1 with EINVAL when no entry exists.
        errno = 0
        let result = acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry)
        guard result == -1, errno == EINVAL else { throw JournalError.unsafeStorage }
    }

    func checkIdentity() throws {
        guard !poisoned else { throw JournalError.storageFailure }
        do {
            let fresh = try Self.openDirectory(directory)
            defer { close(fresh) }
            var expected = stat(), actual = stat()
            guard fstat(directoryFD, &expected) == 0, fstat(fresh, &actual) == 0,
                  expected.st_dev == actual.st_dev, expected.st_ino == actual.st_ino else { throw JournalError.unsafeStorage }
            guard fstat(fileFD, &expected) == 0,
                  fstatat(directoryFD, fileName, &actual, AT_SYMLINK_NOFOLLOW) == 0,
                  expected.st_dev == actual.st_dev, expected.st_ino == actual.st_ino,
                  actual.st_mode & S_IFMT == S_IFREG, actual.st_mode & 0o7777 == 0o600,
                  actual.st_uid == geteuid(), actual.st_nlink == 1 else { throw JournalError.unsafeStorage }
            try Self.requireNoACL(fileFD)
            for suffix in ["-journal", "-wal", "-shm"] {
                var sidecar = stat()
                if fstatat(directoryFD, fileName + suffix, &sidecar, AT_SYMLINK_NOFOLLOW) == 0 {
                    guard suffix == "-journal", sidecar.st_mode & S_IFMT == S_IFREG,
                          sidecar.st_mode & 0o7777 == 0o600, sidecar.st_uid == geteuid(), sidecar.st_nlink == 1 else { throw JournalError.unsafeStorage }
                    // SQLite may remove its transient journal on another connection between probes.
                    let sidecarFD = openat(directoryFD, fileName + suffix, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                    if sidecarFD >= 0 {
                        defer { close(sidecarFD) }
                        try Self.requireNoACL(sidecarFD)
                    } else if errno != ENOENT { throw JournalError.unsafeStorage }
                } else if errno != ENOENT { throw JournalError.unsafeStorage }
            }
        } catch { poisoned = true; throw error }
    }

    func snapshot<T>(_ body: () throws -> T) throws -> T {
        try checkIdentity()
        try execute("BEGIN DEFERRED")
        do {
            let value = try body()
            try checkIdentity()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try checkIdentity()
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try checkIdentity()
            try execute("COMMIT")
            try checkIdentity()
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, _ arguments: [String] = []) throws { _ = try rows(sql, arguments) }
    func integer(_ sql: String, _ arguments: [String] = []) throws -> Int {
        guard let first = try rows(sql, arguments).first?.first, let text = first, let value = Int(text) else { throw JournalError.storageFailure }
        return value
    }
    func rows(_ sql: String, _ arguments: [String] = []) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { poisoned = true; throw JournalError.storageFailure }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, argument) in arguments.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), argument, -1, transient) == SQLITE_OK else { poisoned = true; throw JournalError.storageFailure }
        }
        var result: [[String?]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
            case SQLITE_DONE: return result
            default: poisoned = true; throw JournalError.storageFailure
            }
        }
    }
}

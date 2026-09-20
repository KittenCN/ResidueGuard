import Darwin
import Foundation
import Testing
@testable import ResiduePreferences

private struct Fixture {
    let parent: URL
    var folder: URL { parent.appendingPathComponent("ResidueGuard") }
    var file: URL { folder.appendingPathComponent("retention.json") }
    var lock: URL { folder.appendingPathComponent("retention.lock") }
    init() throws {
        parent = URL(fileURLWithPath: "/private/tmp/ResiduePreferenceTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    func store() throws -> RetentionPreferenceStore { try .init(applicationSupportDirectory: parent) }
    func clean() { try? FileManager.default.removeItem(at: parent) }
}

@Test func initialReadDoesNotCreateThenSaveReopenAndUpdate() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store()
    #expect(try store.read() == nil)
    #expect(!FileManager.default.fileExists(atPath: f.folder.path))
    let first = try store.save(data: Data("first".utf8), expectedRevision: nil)
    #expect(try f.store().read() == first)
    let second = try f.store().save(data: Data("second".utf8), expectedRevision: first.revision)
    #expect(try store.read() == second)
    #expect(first.revision != second.revision)
    var dir = stat(), file = stat()
    #expect(lstat(f.folder.path, &dir) == 0 && dir.st_mode & 0o7777 == 0o700)
    #expect(lstat(f.file.path, &file) == 0 && file.st_mode & 0o7777 == 0o600 && file.st_nlink == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).sorted() == ["retention.json", "retention.lock"])
}
@Test func staleRevisionAndCreateOverExistingNeverOverwrite() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), a = try store.save(data: Data([1]), expectedRevision: nil)
    let b = try store.save(data: Data([2]), expectedRevision: a.revision)
    #expect(throws: RetentionPreferenceError.conflict) { try store.save(data: Data([3]), expectedRevision: a.revision) }
    #expect(throws: RetentionPreferenceError.conflict) { try store.save(data: Data([3]), expectedRevision: nil) }
    #expect(try store.read() == b)
}
@Test func concurrentInstancesOnlyOneExpectedRevisionWins() async throws {
    let f = try Fixture(); defer { f.clean() }
    let a = try f.store(), b = try f.store()
    let prior = try a.save(data: Data([0]), expectedRevision: nil)
    let wins = await withTaskGroup(of: Bool.self) { group in
        for (index, store) in [a, b].enumerated() {
            group.addTask {
                do { _ = try store.save(data: Data([UInt8(index + 1)]), expectedRevision: prior.revision); return true }
                catch RetentionPreferenceError.conflict { return false }
                catch { Issue.record("Unexpected concurrent write error: \(error)"); return false }
            }
        }
        var count = 0; for await success in group { if success { count += 1 } }; return count
    }
    #expect(wins == 1)
    #expect(try a.read()?.data != prior.data)
}
@Test func ancestorAndChildDirectoryLinksAreRejected() throws {
    let f = try Fixture(); defer { f.clean() }
    let real = f.parent.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let alias = f.parent.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try RetentionPreferenceStore(applicationSupportDirectory: alias) }
    try FileManager.default.createSymbolicLink(at: f.folder, withDestinationURL: real)
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try f.store().read() }
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try f.store().save(data: Data(), expectedRevision: nil) }
}
@Test(arguments: ["retention.json", "retention.lock"])
func leafLinksAndHardlinksAreRejected(name: String) throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(); _ = try store.save(data: Data([1]), expectedRevision: nil)
    let target = f.folder.appendingPathComponent(name), backup = f.folder.appendingPathComponent("original")
    try FileManager.default.moveItem(at: target, to: backup)
    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: backup)
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try store.read() }
    try FileManager.default.removeItem(at: target)
    #expect(link(backup.path, target.path) == 0)
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try store.read() }
}
@Test(arguments: ["directory", "file", "lock", "parent"])
func unsafeModesRejectWithoutRepairingThem(location: String) throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(); _ = try store.save(data: Data([1]), expectedRevision: nil)
    let url = location == "directory" ? f.folder : location == "file" ? f.file : location == "lock" ? f.lock : f.parent
    #expect(chmod(url.path, location == "directory" ? 0o755 : location == "parent" ? 0o777 : 0o644) == 0)
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try store.read() }
}
@Test func oversizeDataDoesNotCreateAndOversizeEnvelopeIsNotMissing() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store()
    #expect(throws: RetentionPreferenceError.oversized) { try store.save(data: Data(repeating: 0, count: 131_073), expectedRevision: nil) }
    #expect(!FileManager.default.fileExists(atPath: f.folder.path))
    _ = try store.save(data: Data(), expectedRevision: nil)
    try Data(repeating: 32, count: 180_001).write(to: f.file)
    #expect(throws: RetentionPreferenceError.oversized) { try store.read() }
}
@Test func maximumOpaquePayloadRoundTripsWithoutInterpretation() throws {
    let f = try Fixture(); defer { f.clean() }
    let data = Data(repeating: 255, count: 131_072)
    let snapshot = try f.store().save(data: data, expectedRevision: nil)
    #expect(try f.store().read() == snapshot)
}
@Test func corruptionAndUnknownVersionAreErrorsInsteadOfDefaults() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(); _ = try store.save(data: Data([1]), expectedRevision: nil)
    try Data("broken".utf8).write(to: f.file)
    #expect(throws: RetentionPreferenceError.corrupt) { try store.read() }
    #expect(throws: RetentionPreferenceError.corrupt) { try store.save(data: Data([2]), expectedRevision: nil) }
    try Data(#"{"version":99,"revision":"x","data":""}"#.utf8).write(to: f.file)
    #expect(throws: RetentionPreferenceError.unsupportedVersion) { try store.read() }
}
@Test func cancellationBeforeRenameLeavesPreviousData() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), prior = try store.save(data: Data([1]), expectedRevision: nil)
    #expect(throws: CancellationError.self) {
        try store.save(data: Data([2]), expectedRevision: prior.revision) { phase in if phase == .beforeRename { throw CancellationError() } }
    }
    #expect(try store.read() == prior)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path).count == 2)
}
@Test(arguments: ["cancel", "sync"])
func failureAfterRenameIsExplicitlyUnknownAndRequiresReread(kind: String) throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), prior = try store.save(data: Data([1]), expectedRevision: nil)
    #expect(throws: RetentionPreferenceError.writeOutcomeUnknown) {
        try store.save(data: Data([2]), expectedRevision: prior.revision) { phase in
            if kind == "cancel", phase == .afterRename { throw CancellationError() }
            if kind == "sync", phase == .beforeDirectorySync { throw RetentionPreferenceError.ioFailure }
        }
    }
    #expect(try store.read()?.data == Data([2]))
    #expect(throws: RetentionPreferenceError.conflict) { try store.save(data: Data([3]), expectedRevision: prior.revision) }
}
@Test func lockTimeoutIsBoundedAndDoesNotChangeValue() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), prior = try store.save(data: Data([1]), expectedRevision: nil)
    let fd = open(f.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    #expect(fd >= 0); defer { flock(fd, LOCK_UN); close(fd) }
    #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
    let start = Date()
    #expect(throws: RetentionPreferenceError.busy) { try store.save(data: Data([2]), expectedRevision: prior.revision) }
    #expect(Date().timeIntervalSince(start) < 3)
}
@Test func taskCancelledBeforeSaveDoesNotCreateDirectory() async throws {
    let f = try Fixture(); defer { f.clean() }; let store = try f.store()
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try store.save(data: Data([1]), expectedRevision: nil)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: f.folder.path))
}
@Test func extendedACLIsRejected() throws {
    let f = try Fixture(); defer { f.clean() }; let store = try f.store()
    _ = try store.save(data: Data([1]), expectedRevision: nil)
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/chmod")
    process.arguments = ["+a", "everyone allow read", f.file.path]
    try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try store.read() }
}
@Test func missingParentAndNulPathsAreRejected() throws {
    let f = try Fixture(); defer { f.clean() }
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try RetentionPreferenceStore(applicationSupportDirectory: f.parent.appendingPathComponent("missing")) }
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try RetentionPreferenceStore(applicationSupportDirectory: URL(fileURLWithPath: f.parent.path + "\0suffix")) }
}

@Test func cancellationWhileWaitingForLockStopsWithoutWriting() async throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), prior = try store.save(data: Data([1]), expectedRevision: nil)
    let fd = open(f.lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    #expect(fd >= 0); defer { flock(fd, LOCK_UN); close(fd) }
    #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
    let task = Task.detached { try store.save(data: Data([2]), expectedRevision: prior.revision) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}
@Test func directoryReplacementBeforeCommitCannotRedirectWrite() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), prior = try store.save(data: Data([1]), expectedRevision: nil)
    let original = try Data(contentsOf: f.file)
    let moved = f.parent.appendingPathComponent("moved")
    #expect(throws: RetentionPreferenceError.unsafeStorage) {
        try store.save(data: Data([2]), expectedRevision: prior.revision) { phase in
            if phase == .beforeRename {
                try FileManager.default.moveItem(at: f.folder, to: moved)
                try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
        }
    }
    #expect(try Data(contentsOf: moved.appendingPathComponent("retention.json")) == original)
    #expect(!FileManager.default.fileExists(atPath: f.file.path))
}
@Test func lockReplacementBeforeCommitIsRejected() throws {
    let f = try Fixture(); defer { f.clean() }
    let store = try f.store(), prior = try store.save(data: Data([1]), expectedRevision: nil)
    #expect(throws: RetentionPreferenceError.unsafeStorage) {
        try store.save(data: Data([2]), expectedRevision: prior.revision) { phase in
            if phase == .beforeRename {
                try FileManager.default.moveItem(at: f.lock, to: f.folder.appendingPathComponent("old-lock"))
                let fd = open(f.lock.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
                #expect(fd >= 0); close(fd)
            }
        }
    }
    #expect(try store.read() == prior)
}

@Test func freshSandboxReadDoesNotCreateAndExplicitSaveBootstrapsOnlySupport() throws {
    let f = try Fixture(); defer { f.clean() }
    let support = f.parent.appendingPathComponent("Application Support")
    #expect(try RetentionPreferenceStore.read(sandboxLibraryDirectory: f.parent) == nil)
    #expect(!FileManager.default.fileExists(atPath: support.path))
    let saved = try RetentionPreferenceStore.save(data: Data([7]), expectedRevision: nil, sandboxLibraryDirectory: f.parent)
    #expect(try RetentionPreferenceStore.read(sandboxLibraryDirectory: f.parent) == saved)
    var info = stat()
    #expect(lstat(support.path, &info) == 0 && info.st_mode & 0o7777 == 0o700)
    let updated = try RetentionPreferenceStore.save(data: Data([8]), expectedRevision: saved.revision, sandboxLibraryDirectory: f.parent)
    #expect(try RetentionPreferenceStore.read(sandboxLibraryDirectory: f.parent) == updated)
    #expect(throws: RetentionPreferenceError.conflict) {
        try RetentionPreferenceStore.save(data: Data([9]), expectedRevision: saved.revision, sandboxLibraryDirectory: f.parent)
    }
}

@Test(arguments: ["link", "unsafeMode", "file"])
func sandboxBootstrapRejectsUnsafeSupport(kind: String) throws {
    let f = try Fixture(); defer { f.clean() }
    let support = f.parent.appendingPathComponent("Application Support")
    switch kind {
    case "link": try FileManager.default.createSymbolicLink(at: support, withDestinationURL: f.parent)
    case "file": try Data().write(to: support)
    default: try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o777])
    }
    if kind == "unsafeMode" { #expect(chmod(support.path, 0o777) == 0) }
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try RetentionPreferenceStore.read(sandboxLibraryDirectory: f.parent) }
    #expect(throws: RetentionPreferenceError.unsafeStorage) {
        try RetentionPreferenceStore.save(data: Data([1]), expectedRevision: nil, sandboxLibraryDirectory: f.parent)
    }
    #expect(!FileManager.default.fileExists(atPath: f.folder.path))
}

@Test func sandboxBootstrapNeverCreatesMissingLibraryOrFollowsAncestor() throws {
    let f = try Fixture(); defer { f.clean() }
    let missing = f.parent.appendingPathComponent("missing/Library")
    #expect(throws: RetentionPreferenceError.unsafeStorage) { try RetentionPreferenceStore.read(sandboxLibraryDirectory: missing) }
    #expect(throws: RetentionPreferenceError.unsafeStorage) {
        try RetentionPreferenceStore.save(data: Data(), expectedRevision: nil, sandboxLibraryDirectory: missing)
    }
    #expect(!FileManager.default.fileExists(atPath: f.parent.appendingPathComponent("missing").path))
    let alias = f.parent.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.parent)
    #expect(throws: RetentionPreferenceError.unsafeStorage) {
        try RetentionPreferenceStore.save(data: Data(), expectedRevision: nil, sandboxLibraryDirectory: alias)
    }
}

@Test func sandboxOversizeAndCancelledSaveDoNotBootstrap() async throws {
    let f = try Fixture(); defer { f.clean() }
    #expect(throws: RetentionPreferenceError.oversized) {
        try RetentionPreferenceStore.save(data: Data(repeating: 0, count: RetentionPreferenceStore.maximumDataBytes + 1), expectedRevision: nil, sandboxLibraryDirectory: f.parent)
    }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) {
            try RetentionPreferenceStore.save(data: Data(), expectedRevision: nil, sandboxLibraryDirectory: f.parent)
        }
    }
    await task.value
    #expect(!FileManager.default.fileExists(atPath: f.parent.appendingPathComponent("Application Support").path))
}

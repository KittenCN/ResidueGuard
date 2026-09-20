import CSQLite
import Darwin
import Foundation
import Testing
@testable import ResiduePersistence

private func fixture() throws -> URL {
    let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("ResidueJournalTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    _ = try TransactionJournal(directory: url, createNew: true)
    return url
}

private func sql(_ directory: URL, _ statement: String) throws {
    var db: OpaquePointer?
    #expect(sqlite3_open(directory.appendingPathComponent("journal.sqlite").path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
}

@Test func persistedPreparationAndResultsSurviveReopen() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    var journal: TransactionJournal? = try TransactionJournal(directory: directory)
    try await journal!.claim(planID: "plan", digest: "digest", nonce: "nonce")
    try await journal!.prepare(planID: "plan", operationID: "quarantine")
    journal = nil
    let reopened = try TransactionJournal(directory: directory)
    var entries = try await reopened.unfinishedEntries()
    #expect(entries.count == 1)
    #expect(entries[0].digest == "digest")
    #expect(entries[0].steps == [JournalStep(index: 0, operationID: "quarantine", result: nil)])
    try await reopened.recordResult(planID: "plan", operationID: "quarantine", result: .succeeded)
    entries = try await TransactionJournal(directory: directory).unfinishedEntries()
    #expect(entries[0].steps[0].result == .succeeded)
    try await reopened.finish(planID: "plan")
    #expect(try await reopened.unfinishedEntries().isEmpty)
}

@Test func planAndNonceCannotReplayAcrossReopenOrCompletion() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try TransactionJournal(directory: directory)
    try await journal.claim(planID: "plan", digest: "digest", nonce: "nonce")
    try await journal.finish(planID: "plan")
    let reopened = try TransactionJournal(directory: directory)
    await #expect(throws: JournalError.replay) { try await reopened.claim(planID: "plan", digest: "changed", nonce: "new") }
    await #expect(throws: JournalError.replay) { try await reopened.claim(planID: "other", digest: "digest", nonce: "nonce") }
    // Rejected claims must not consume otherwise-unused identifiers.
    try await reopened.claim(planID: "other", digest: "digest", nonce: "new")
}

@Test func invalidOrderCannotAdvance() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try TransactionJournal(directory: directory)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: "missing", operationID: "a") }
    try await journal.claim(planID: "plan", digest: "digest", nonce: "nonce")
    await #expect(throws: JournalError.invalidTransition) { try await journal.recordResult(planID: "plan", operationID: "a", result: .succeeded) }
    try await journal.prepare(planID: "plan", operationID: "a")
    await #expect(throws: JournalError.invalidTransition) { try await journal.finish(planID: "plan") }
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: "plan", operationID: "b") }
    try await journal.recordResult(planID: "plan", operationID: "a", result: .failed)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: "plan", operationID: "b") }
    await #expect(throws: JournalError.invalidTransition) { try await journal.recordResult(planID: "plan", operationID: "a", result: .succeeded) }
    try await journal.finish(planID: "plan")
    await #expect(throws: JournalError.invalidTransition) { try await journal.finish(planID: "plan") }
}

@Test func successfulStepsAreOrderedAndCannotRepeat() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try TransactionJournal(directory: directory)
    try await journal.claim(planID: "plan", digest: "digest", nonce: "nonce")
    try await journal.prepare(planID: "plan", operationID: "a")
    try await journal.recordResult(planID: "plan", operationID: "a", result: .succeeded)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: "plan", operationID: "a") }
    try await journal.prepare(planID: "plan", operationID: "b")
    try await journal.recordResult(planID: "plan", operationID: "b", result: .unverified)
    #expect(try await journal.unfinishedEntries()[0].steps.map(\.index) == [0, 1])
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: "plan", operationID: "c") }
}

@Test func independentConnectionsAtomicallyClaimNonce() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let one = try TransactionJournal(directory: directory)
    let two = try TransactionJournal(directory: directory)
    let successes = await withTaskGroup(of: Bool.self) { group in
        for (index, journal) in [one, two].enumerated() {
            group.addTask {
                do { try await journal.claim(planID: "p\(index)", digest: "d", nonce: "same"); return true }
                catch { return false }
            }
        }
        var total = 0
        for await success in group { if success { total += 1 } }
        return total
    }
    #expect(successes == 1)
    #expect(try await one.unfinishedEntries().count == 1)
}

@Test func refusesUnsafeModesAndPoisonsOpenHandle() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try TransactionJournal(directory: directory)
    let file = directory.appendingPathComponent("journal.sqlite").path
    #expect(chmod(file, 0o644) == 0)
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory) }
    await #expect(throws: JournalError.unsafeStorage) { try await journal.claim(planID: "p", digest: "d", nonce: "n") }
    #expect(chmod(file, 0o600) == 0)
    await #expect(throws: JournalError.storageFailure) { try await journal.claim(planID: "p", digest: "d", nonce: "n") }
    #expect(chmod(directory.path, 0o755) == 0)
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory) }
}

@Test func refusesSymlinkHardlinkAndReplacedFile() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try TransactionJournal(directory: directory)
    let file = directory.appendingPathComponent("journal.sqlite")
    let alias = directory.appendingPathComponent("alias")
    #expect(link(file.path, alias.path) == 0)
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory) }
    try FileManager.default.removeItem(at: alias)
    try FileManager.default.moveItem(at: file, to: alias)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: alias)
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory) }
    await #expect(throws: JournalError.unsafeStorage) { try await journal.unfinishedEntries() }
}

@Test func refusesSymlinkDirectoryAndSidecar() throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let child = directory.appendingPathComponent("child")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let alias = directory.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: child)
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: alias) }
    _ = try TransactionJournal(directory: child, createNew: true)
    try FileManager.default.createSymbolicLink(at: child.appendingPathComponent("journal.sqlite-journal"), withDestinationURL: directory.appendingPathComponent("absent"))
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: child) }
}

@Test func refusesUnknownSchemaAndCorruption() throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = try TransactionJournal(directory: directory)
    try sql(directory, "PRAGMA user_version=42")
    #expect(throws: JournalError.unsupportedSchema) { try TransactionJournal(directory: directory) }
    try Data("not a database".utf8).write(to: directory.appendingPathComponent("journal.sqlite"))
    #expect(throws: JournalError.storageFailure) { try TransactionJournal(directory: directory) }
}

@Test func rejectsInvalidInputAndKeepsJournalUsable() async throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = try TransactionJournal(directory: directory)
    for invalid in ["", "bad\0tail", String(repeating: "x", count: 1025)] {
        await #expect(throws: JournalError.invalidInput) { try await journal.claim(planID: invalid, digest: "d", nonce: "n") }
    }
    try await journal.claim(planID: "'quoted", digest: "d", nonce: "n")
    #expect(try await journal.unfinishedEntries()[0].planID == "'quoted")
}

@Test func explicitProvisioningNeverResetsExistingOrMissingJournal() throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory, createNew: true) }
    try FileManager.default.removeItem(at: directory.appendingPathComponent("journal.sqlite"))
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory) }
}

@Test func rejectsModifiedSchemaEvenWithCorrectVersion() throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    try sql(directory, "CREATE TRIGGER discard_claim AFTER INSERT ON plans BEGIN DELETE FROM plans WHERE plan_id=NEW.plan_id; END")
    #expect(throws: JournalError.unsupportedSchema) { try TransactionJournal(directory: directory) }
}

@Test func renamedDirectoryInvalidatesExistingHandle() async throws {
    let directory = try fixture()
    let moved = directory.appendingPathExtension("moved")
    defer {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: moved)
    }
    let journal = try TransactionJournal(directory: directory)
    try FileManager.default.moveItem(at: directory, to: moved)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    await #expect(throws: JournalError.unsafeStorage) { try await journal.claim(planID: "p", digest: "d", nonce: "n") }
}

@Test func foreignOwnedLeafIsRejected() throws {
    // /private/tmp is root owned; no ownership of real files is changed by this test.
    if geteuid() != 0 {
        #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: URL(fileURLWithPath: "/private/tmp")) }
    }
}

@Test func addedAccessControlEntryIsRejected() throws {
    let directory = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("journal.sqlite")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/chmod")
    process.arguments = ["+a", "everyone allow read", file.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(throws: JournalError.unsafeStorage) { try TransactionJournal(directory: directory) }
}

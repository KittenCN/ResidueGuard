import CSQLite
import Darwin
import Foundation
import CryptoKit
import Testing
@testable import ResiduePersistence

private struct ExperimentFixture {
    let directory: URL
    let fd: Int32
    let date = Date(timeIntervalSince1970: 1000)
    let plan: OwnedFixtureExperimentPlan
    let backup: OwnedFixtureBackupEvidence
    init() throws {
        directory = URL(fileURLWithPath: "/private/tmp/OwnedExperimentTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw JournalError.unsafeStorage }
        let file = OwnedFixtureFileIdentity(device: 1, inode: 2, owner: geteuid(), group: getegid(), mode: 0o100600, size: 10,
            modifiedSeconds: 1, modifiedNanos: 0, changedSeconds: 1, changedNanos: 0, sha256: String(repeating: "a", count: 64), extendedAttributes: [:])
        plan = .init(id: UUID(), userID: geteuid(), osBuild: "26A428", createdAt: date, expiresAt: date.addingTimeInterval(120),
            source: file, quarantineRoot: .init(device: 1, inode: 3, owner: geteuid()), sourceRoot: .init(device: 1, inode: 4, owner: geteuid()), program: file)
        let metadataEncoder = JSONEncoder(); metadataEncoder.outputFormatting = [.sortedKeys]
        let metadataDigest = SHA256.hash(data: try metadataEncoder.encode(file)).map { String(format: "%02x", $0) }.joined()
        let rootID = UUID()
        backup = .init(backupID: UUID(), planID: plan.id, root: .init(rootID: rootID, directoryName: "ResidueGuard-VM-VerifiedBackup-" + rootID.uuidString, parentDevice: 1, parentInode: 5, device: 1, inode: 6, owner: geteuid()), contentSHA256: file.sha256, metadataSHA256: metadataDigest, manifestSHA256: String(repeating: "c", count: 64), observedAt: date)
    }
    func cleanup() { close(fd); try? FileManager.default.removeItem(at: directory) }
    func open(_ create: Bool = false) throws -> OwnedFixtureExperimentJournal { try .init(directoryFD: fd, createNew: create) }
    func sql(_ command: String) throws {
        var db: OpaquePointer?; defer { sqlite3_close(db) }
        guard sqlite3_open(directory.appendingPathComponent("owned-fixture-experiment.sqlite").path, &db) == SQLITE_OK,
              sqlite3_exec(db, command, nil, nil, nil) == SQLITE_OK else { throw JournalError.storageFailure }
    }
}
@Test func ownedExperimentReopensCompleteEvidenceWithoutExecutionAuthority() async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    do {
        let journal = try f.open(true)
        try await journal.create(plan: f.plan)
        try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: f.backup, at: f.date)
    }
    let second = try f.open()
    let pending = try await second.entries()
    #expect(pending.count == 1 && pending[0].steps[0].actionOutcomeUnknown)
    #expect(!pending[0].authorizesMutation)
    #expect(pending[0].plan == f.plan && pending[0].steps[0].backup == f.backup)
    try await second.recordResult(planID: f.plan.id, phase: .isolation,
        effects: .init(file: .quarantinedVerified, runtime: .observedRegisteredNotRunning, quarantineObject: f.plan.source), at: f.date)
    try await second.prepare(planID: f.plan.id, phase: .restoration, backup: f.backup, at: f.date)
    // Expiry cannot prevent an already performed outcome from being recorded.
    try await second.recordResult(planID: f.plan.id, phase: .restoration,
        effects: .init(file: .restoredVerified, runtime: .observedRegisteredNotRunning, sourceObject: f.plan.source), at: f.date.addingTimeInterval(500))
    let complete = try await f.open().entries()
    #expect(complete[0].steps.count == 2 && complete[0].steps[1].effects?.sourceObject == f.plan.source)
    #expect(complete[0].steps[1].effects?.registration == "noMutation")
    await #expect(throws: JournalError.replay) { try await second.create(plan: f.plan) }
}
@Test(arguments: [OwnedFixtureFileEffect.notMoved, .movedUnverified, .quarantinedVerified])
func ownedExperimentUnsuccessfulOrUnknownRuntimeBlocksRestoration(effect: OwnedFixtureFileEffect) async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: f.plan.id, phase: .restoration, backup: f.backup, at: f.date) }
    await #expect(throws: JournalError.invalidTransition) { try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: effect, runtime: .unknown, quarantineObject: effect == .quarantinedVerified ? f.plan.source : nil), at: f.date) }
    try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: f.backup, at: f.date)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: f.plan.id, phase: .restoration, backup: f.backup, at: f.date) }
    try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: effect, runtime: .unknown, quarantineObject: effect == .quarantinedVerified ? f.plan.source : nil), at: f.date)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: f.plan.id, phase: .restoration, backup: f.backup, at: f.date) }
    await #expect(throws: JournalError.invalidTransition) { try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: .quarantinedVerified, runtime: .observedRegisteredNotRunning, quarantineObject: f.plan.source), at: f.date) }
}
@Test func ownedExperimentRejectsExpiredPreparationAndMismatchedBackupAtomically() async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    await #expect(throws: JournalError.invalidTransition) { try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: f.backup, at: f.date.addingTimeInterval(121)) }
    let bad = OwnedFixtureBackupEvidence(backupID: f.backup.backupID, planID: UUID(), root: f.backup.root, contentSHA256: f.backup.contentSHA256, metadataSHA256: f.backup.metadataSHA256, manifestSHA256: f.backup.manifestSHA256, observedAt: f.date)
    await #expect(throws: JournalError.invalidInput) { try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: bad, at: f.date) }
    #expect(try await journal.entries()[0].steps.isEmpty)
}
@Test(arguments: ["version", "payload", "oversize", "extraSchema"])
func ownedExperimentDamagedOrUnknownStorageRejects(fault: String) async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    switch fault {
    case "version": try f.sql("PRAGMA user_version=99")
    case "payload": try f.sql("UPDATE experiments SET payload='{}'")
    case "oversize": try f.sql("UPDATE experiments SET payload=hex(zeroblob(70000))")
    default: try f.sql("CREATE TABLE unexpected(value TEXT)")
    }
    await #expect(throws: (any Error).self) { try await journal.entries() }
    if fault == "version" || fault == "extraSchema" { #expect(throws: JournalError.unsupportedSchema) { try f.open() } }
}
@Test func ownedExperimentMissingStorageDoesNotCreateAndUnsafeFileIsRejected() async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    #expect(throws: JournalError.unsafeStorage) { try f.open() }
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    let path = f.directory.appendingPathComponent("owned-fixture-experiment.sqlite").path
    #expect(chmod(path, 0o644) == 0)
    await #expect(throws: JournalError.unsafeStorage) { try await journal.entries() }
}

@Test func ownedExperimentFreshBackupObservationAndReadOnlyReopen() async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: f.backup, at: f.date)
    try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: .quarantinedVerified, runtime: .observedRegisteredNotRunning, quarantineObject: f.plan.source), at: f.date)
    let later = f.date.addingTimeInterval(1)
    let fresh = OwnedFixtureBackupEvidence(backupID: f.backup.backupID, planID: f.plan.id, root: f.backup.root, contentSHA256: f.backup.contentSHA256,
        metadataSHA256: f.backup.metadataSHA256, manifestSHA256: f.backup.manifestSHA256, observedAt: later)
    try await journal.prepare(planID: f.plan.id, phase: .restoration, backup: fresh, at: later)
    let readonly = try OwnedFixtureExperimentJournal(directoryFD: f.fd, readOnly: true)
    #expect(try await readonly.entries()[0].steps[1].backup.observedAt == later)
    await #expect(throws: JournalError.invalidTransition) { try await readonly.recordResult(planID: f.plan.id, phase: .restoration, effects: .init(file: .restoredVerified, runtime: .observedRegisteredNotRunning), at: later) }
}

@Test(arguments: ["osBuild", "sourceMode", "sourceDevice", "rootDevice", "metadataDigest", "rootName"])
func ownedExperimentRejectsUnsupportedBindings(field: String) async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true)
    var plan = f.plan, backup = f.backup
    if ["osBuild", "sourceMode", "sourceDevice", "rootDevice"].contains(field) {
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        if field == "osBuild" { value["osBuild"] = "unknown-build" }
        else {
            let key = field == "rootDevice" ? "quarantineRoot" : "source"
            var nested = try #require(value[key] as? [String: Any])
            nested[field == "sourceMode" ? "mode" : "device"] = field == "sourceMode" ? 0o100666 : 999
            value[key] = nested
        }
        plan = try JSONDecoder().decode(OwnedFixtureExperimentPlan.self, from: JSONSerialization.data(withJSONObject: value))
        let invalid = plan
        await #expect(throws: JournalError.invalidInput) { try await journal.create(plan: invalid) }
        #expect(try await journal.entries().isEmpty)
    } else {
        try await journal.create(plan: plan)
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(backup)) as? [String: Any])
        if field == "metadataDigest" { value["metadataSHA256"] = String(repeating: "d", count: 64) }
        else {
            var root = try #require(value["root"] as? [String: Any]); root["directoryName"] = "arbitrary"; value["root"] = root
        }
        backup = try JSONDecoder().decode(OwnedFixtureBackupEvidence.self, from: JSONSerialization.data(withJSONObject: value))
        let invalid = backup
        await #expect(throws: JournalError.invalidInput) { try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: invalid, at: f.date) }
        #expect(try await journal.entries()[0].steps.isEmpty)
    }
}

@Test(arguments: ["symlink", "hardlink", "directoryMode", "fifo"])
func ownedExperimentStorageLinksAndUnsafeRootReject(kind: String) async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    let path = f.directory.appendingPathComponent("owned-fixture-experiment.sqlite").path
    if kind == "directoryMode" { #expect(chmod(f.directory.path, 0o755) == 0) }
    else if kind == "hardlink" { #expect(link(path, path + ".other") == 0) }
    else if kind == "fifo" { #expect(unlink(path) == 0); #expect(mkfifo(path, 0o600) == 0) }
    else {
        #expect(rename(path, path + ".original") == 0)
        #expect(symlink(path + ".original", path) == 0)
    }
    await #expect(throws: JournalError.unsafeStorage) { try await journal.entries() }
    #expect(throws: JournalError.unsafeStorage) { try f.open() }
    #expect(throws: JournalError.unsafeStorage) { try OwnedFixtureExperimentJournal(directoryFD: f.fd, readOnly: true) }
}

@Test func ownedExperimentResourceBoundRejectsBeforeDecodingRows() async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true)
    try f.sql("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<129) INSERT INTO experiments SELECT 'seed-'||x,'{}','invalid' FROM n")
    await #expect(throws: JournalError.resourceLimit) { try await journal.entries() }
}

@Test func ownedExperimentVerifiedEffectRequiresMatchingObservedObject() async throws {
    let f = try ExperimentFixture(); defer { f.cleanup() }
    let journal = try f.open(true); try await journal.create(plan: f.plan)
    try await journal.prepare(planID: f.plan.id, phase: .isolation, backup: f.backup, at: f.date)
    await #expect(throws: JournalError.invalidInput) { try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: .quarantinedVerified, runtime: .observedRegisteredNotRunning), at: f.date) }
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.plan.source)) as? [String: Any])
    json["inode"] = 999
    let swapped = try JSONDecoder().decode(OwnedFixtureFileIdentity.self, from: JSONSerialization.data(withJSONObject: json))
    await #expect(throws: JournalError.invalidInput) { try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: .quarantinedVerified, runtime: .observedRegisteredNotRunning, quarantineObject: swapped), at: f.date) }
    #expect(try await journal.entries()[0].steps[0].actionOutcomeUnknown)
    // Preserve observed unexpected identity on an unverified result; never promote it.
    try await journal.recordResult(planID: f.plan.id, phase: .isolation, effects: .init(file: .movedUnverified, runtime: .unknown, quarantineObject: swapped), at: f.date)
    #expect(try await journal.entries()[0].steps[0].effects?.quarantineObject?.inode == 999)
}

import CSQLite
import CryptoKit
import Foundation
import Testing
import ResidueCore
import ResidueRecovery
@testable import ResiduePersistence

private let auditDate = Date(timeIntervalSince1970: 5000)
private func auditPlan() throws -> VerifiedTransactionPlan {
    try .validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID,
        createdAt: auditDate, expiresAt: auditDate.addingTimeInterval(120),
        steps: [.init(id: "stop", targetID: "fixture", action: .bootoutExactService, fingerprint: "fp"),
                .init(id: "isolate", targetID: "fixture", action: .quarantineLaunchConfiguration, fingerprint: "fp", dependencies: ["stop"])],
        targets: [.init(id: "fixture", displayName: "Synthetic", presence: .highConfidenceOrphan, fingerprint: "fp")], impactApproved: true)
}
private func receipt(_ plan: VerifiedTransactionPlan) -> [BackupAuditReceipt] {
    [.init(targetID: plan.targets[0].id, contentSHA256: String(repeating: "a", count: 64), metadataSHA256: String(repeating: "b", count: 64), observedAt: auditDate)]
}
private struct AuditFixture {
    let directory: URL
    let journal: TransactionJournal
    init(_ schema: JournalSchema = .auditV2) throws {
        directory = URL(fileURLWithPath: "/private/tmp/ResidueAuditJournalTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        journal = try TransactionJournal(directory: directory, createNew: true, schema: schema)
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
    func sql(_ statement: String, argument: String? = nil) throws {
        var db: OpaquePointer?; var query: OpaquePointer?
        #expect(sqlite3_open(directory.appendingPathComponent("journal.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_finalize(query); sqlite3_close(db) }
        #expect(sqlite3_prepare_v2(db, statement, -1, &query, nil) == SQLITE_OK)
        if let argument { #expect(sqlite3_bind_text(query, 1, argument, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK) }
        #expect(sqlite3_step(query) == SQLITE_DONE)
    }
}

@Test func schema2ExplicitCreationRoundTripsFullAuditAndEffects() async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let p = try auditPlan(), nonce = UUID()
    try await f.journal.claimAudited(nonce: nonce, plan: p)
    try await f.journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: receipt(p), at: auditDate)
    try await f.journal.recordAuditedResult(plan: p, step: p.steps[0], effects: .init(runtime: .succeeded, registration: .pendingSystemRefresh), at: auditDate.addingTimeInterval(1))
    let reopened = try TransactionJournal(directory: f.directory, schema: .auditV2)
    let entries = try await reopened.recoveryEntries()
    guard case .audit(let snapshot) = try #require(entries.first) else { Issue.record("Expected audit"); return }
    #expect(snapshot.plan.digest == p.digest)
    #expect(snapshot.plan.targets[0].displayName == "Synthetic")
    #expect(snapshot.backups.count == 1)
    #expect(snapshot.observations[0].effects?.registration == .pendingSystemRefresh)
    try await reopened.prepareAudited(plan: p, step: p.steps[1], backupReceipts: receipt(p), at: auditDate.addingTimeInterval(2))
    try await reopened.recordAuditedResult(plan: p, step: p.steps[1], effects: .init(file: .succeeded), at: auditDate.addingTimeInterval(3))
    try await reopened.finishAudited(plan: p)
    #expect(try await reopened.recoveryEntries().isEmpty)
    #expect(try await reopened.recoveryEntries(includeFinished: true).count == 1)
    await #expect(throws: JournalError.replay) { try await reopened.claimAudited(nonce: nonce, plan: auditPlan()) }
    #expect(throws: JournalError.unsupportedSchema) { try TransactionJournal(directory: f.directory) }
}

@Test func migrationPreservesLegacyStepsNoncesAndRejectsOldLiveConnection() async throws {
    let f = try AuditFixture(.legacyV1); defer { f.cleanup() }
    let nonce = UUID()
    try await f.journal.claim(planID: "legacy", digest: "legacy-digest", nonce: nonce.uuidString)
    try await f.journal.prepare(planID: "legacy", operationID: "prepared")
    #expect(throws: JournalError.unsupportedSchema) { try TransactionJournal(directory: f.directory, schema: .auditV2) }
    try TransactionJournal.migrateLegacyToAuditV2(directory: f.directory)
    await #expect(throws: JournalError.unsupportedSchema) { try await f.journal.claim(planID: "bypass", digest: "d", nonce: "new") }
    let migrated = try TransactionJournal(directory: f.directory, schema: .auditV2)
    guard case .legacyEvidenceUnavailable(let legacy) = try #require(try await migrated.recoveryEntries().first) else { Issue.record("Expected explicit legacy gap"); return }
    #expect(legacy.planID == "legacy" && legacy.digest == "legacy-digest")
    #expect(legacy.steps.first?.operationID == "prepared" && legacy.steps.first?.result == nil)
    await #expect(throws: JournalError.replay) { try await migrated.claimAudited(nonce: nonce, plan: auditPlan()) }
    #expect(throws: JournalError.unsupportedSchema) { try TransactionJournal.migrateLegacyToAuditV2(directory: f.directory) }
}

@Test func schema2RejectsAllLegacyMutationAPIs() async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let p = try auditPlan()
    try await f.journal.claimAudited(nonce: UUID(), plan: p)
    await #expect(throws: JournalError.unsupportedSchema) { try await f.journal.claim(planID: "bypass", digest: "d", nonce: "n") }
    await #expect(throws: JournalError.unsupportedSchema) { try await f.journal.prepare(planID: p.id.uuidString, operationID: "stop") }
    await #expect(throws: JournalError.unsupportedSchema) { try await f.journal.recordResult(planID: p.id.uuidString, operationID: "stop", result: .succeeded) }
    await #expect(throws: JournalError.unsupportedSchema) { try await f.journal.finish(planID: p.id.uuidString) }
}

@Test func failedAndOutOfScopeEffectsCannotAdvanceAuditedSteps() async throws {
    for effects in [StepEffects(runtime: .failed), StepEffects(runtime: .succeeded, permission: .succeeded)] {
        let f = try AuditFixture(); defer { f.cleanup() }
        let p = try auditPlan()
        try await f.journal.claimAudited(nonce: UUID(), plan: p)
        try await f.journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: receipt(p), at: auditDate)
        try await f.journal.recordAuditedResult(plan: p, step: p.steps[0], effects: effects, at: auditDate)
        await #expect(throws: JournalError.invalidTransition) { try await f.journal.prepareAudited(plan: p, step: p.steps[1], backupReceipts: receipt(p), at: auditDate) }
        try await f.journal.finishAudited(plan: p) // Closed audit is not a claim of successful effects.
        #expect(try await f.journal.recoveryEntries(includeFinished: true).count == 1)
    }
}

@Test func invalidPreparationIsAtomicAndDoesNotLoseClaim() async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let p = try auditPlan()
    try await f.journal.claimAudited(nonce: UUID(), plan: p)
    await #expect(throws: JournalError.invalidTransition) { try await f.journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: [], at: auditDate) }
    await #expect(throws: (any Error).self) { try await f.journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: receipt(p), at: auditDate.addingTimeInterval(-1)) }
    #expect(try await f.journal.unfinishedEntries()[0].steps.isEmpty)
    try await f.journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: receipt(p), at: auditDate)
    await #expect(throws: JournalError.invalidTransition) { try await f.journal.finishAudited(plan: p) }
    await #expect(throws: (any Error).self) { try await f.journal.recordAuditedResult(plan: p, step: p.steps[0], effects: .init(runtime: .succeeded), at: auditDate.addingTimeInterval(-1)) }
    #expect(try await f.journal.unfinishedEntries()[0].steps[0].result == nil)
}

@Test(arguments: ["missingAudit", "corruptEnvelope", "coarseMismatch", "version", "initialPlan"])
func schema2EveryReadRejectsInconsistentOrUnknownEvidence(fault: String) async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let p = try auditPlan()
    try await f.journal.claimAudited(nonce: UUID(), plan: p)
    switch fault {
    case "missingAudit": try f.sql("DELETE FROM audits")
    case "corruptEnvelope": try f.sql("UPDATE audits SET envelope='broken'")
    case "coarseMismatch": try f.sql("UPDATE plans SET digest='changed'")
    case "version": try f.sql("PRAGMA user_version=99")
    default: try f.sql("UPDATE audits SET plan_payload='{}'")
    }
    await #expect(throws: (any Error).self) { try await f.journal.recoveryEntries() }
    await #expect(throws: (any Error).self) { try await f.journal.unfinishedEntries() }
}

@Test func auditResourceLimitsRejectBeforeUnboundedRecoveryAndRollbackNewClaim() async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    try f.sql("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<512) INSERT INTO plans SELECT 'legacy-'||x,'d','nonce-'||x,0 FROM n")
    try f.sql("INSERT INTO legacy_plans SELECT plan_id FROM plans")
    #expect(try await f.journal.recoveryEntries().count == 512)
    let p = try auditPlan(), nonce = UUID()
    await #expect(throws: JournalError.resourceLimit) { try await f.journal.claimAudited(nonce: nonce, plan: p) }
    let reopened = try TransactionJournal(directory: f.directory, schema: .auditV2)
    #expect(try await reopened.recoveryEntries().count == 512) // Claim and envelope both rolled back.
}

@Test func overLimitLegacyMigrationDoesNotLoseDataOrChangeSchema() async throws {
    let f = try AuditFixture(.legacyV1); defer { f.cleanup() }
    try f.sql("WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<513) INSERT INTO plans SELECT 'legacy-'||x,'d','nonce-'||x,0 FROM n")
    #expect(throws: JournalError.resourceLimit) { try TransactionJournal.migrateLegacyToAuditV2(directory: f.directory) }
    let reopened = try TransactionJournal(directory: f.directory)
    #expect(try await reopened.unfinishedEntries().count == 513)
    await #expect(throws: JournalError.replay) { try await reopened.claim(planID: "new", digest: "d", nonce: "nonce-1") }
}

@Test func aggregateAuditSizeLimitPrecedesDecodingMalformedLargeRows() async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let p = try auditPlan()
    try await f.journal.claimAudited(nonce: UUID(), plan: p)
    try f.sql("UPDATE audits SET envelope=CAST(zeroblob(8388609) AS TEXT)")
    await #expect(throws: JournalError.resourceLimit) { try await f.journal.recoveryEntries() }
}

@Test func auditDatabaseFileLimitRejectsOversizedStorageBeforeSQLiteOpen() throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let handle = try FileHandle(forWritingTo: f.directory.appendingPathComponent("journal.sqlite"))
    try handle.truncate(atOffset: UInt64(Storage.maximumAuditDatabaseBytes + 1)); try handle.close()
    #expect(throws: JournalError.resourceLimit) { try TransactionJournal(directory: f.directory, schema: .auditV2) }
}

@Test func rehashedEnvelopeCannotReplaceOriginallyBoundPlanFields() async throws {
    let f = try AuditFixture(); defer { f.cleanup() }
    let p = try auditPlan()
    try await f.journal.claimAudited(nonce: UUID(), plan: p)
    guard case .audit(let snapshot) = try #require(try await f.journal.recoveryEntries().first) else { Issue.record("Expected audit"); return }
    var outer = try #require(JSONSerialization.jsonObject(with: RecoveryAudit.encode(snapshot)) as? [String: Any])
    let originalPayload = try #require(Data(base64Encoded: outer["payload"] as! String))
    var payload = try #require(JSONSerialization.jsonObject(with: originalPayload) as? [String: Any])
    var planFields = payload["plan"] as! [String: Any]
    var targets = planFields["targets"] as! [[String: Any]]
    targets[0]["displayName"] = "Changed without changing digest"
    planFields["targets"] = targets; payload["plan"] = planFields
    let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    outer["payload"] = bytes.base64EncodedString()
    outer["contentSHA256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let changed = try JSONSerialization.data(withJSONObject: outer, options: [.sortedKeys])
    _ = try RecoveryAudit.decode(changed) // Integrity alone accepts the recomputed hash.
    try f.sql("UPDATE audits SET envelope=?", argument: String(decoding: changed, as: UTF8.self))
    await #expect(throws: JournalError.storageFailure) { try await f.journal.recoveryEntries() }
    await #expect(throws: JournalError.storageFailure) { try await f.journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: receipt(p), at: auditDate) }
}

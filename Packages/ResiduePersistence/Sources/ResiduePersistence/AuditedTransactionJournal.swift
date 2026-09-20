import Foundation
import ResidueCore
import ResidueRecovery

public enum RecoveryJournalEntry: Sendable {
    case legacyEvidenceUnavailable(JournalEntry)
    case audit(RecoveryAuditSnapshot)
}

extension TransactionJournal {
    /// Explicit transaction-only migration; preserves every existing nonce, plan and step.
    /// Existing legacy handles fail their next schema check. No old evidence is invented.
    public static func migrateLegacyToAuditV2(directory: URL) throws {
        let legacy = try Storage(directory: directory, createNew: false, schema: .legacyV1)
        try legacy.migrateToAuditV2()
    }

    /// Records the caller's immutable in-process plan. No imported envelope write API exists.
    /// Authorization and fresh backup/system verification remain the caller's responsibility.
    public func claimAudited(nonce: UUID, plan: VerifiedTransactionPlan) throws {
        try requireAuditSchema()
        let snapshot = RecoveryAuditSnapshot(plan: .init(recording: plan), backups: [], observations: [])
        let envelope = try encoded(snapshot)
        try storage.transaction {
            try validateAuditConsistency()
            guard try storage.integer("SELECT count(*) FROM plans WHERE plan_id=? OR nonce=?", [plan.id.uuidString, nonce.uuidString]) == 0 else { throw JournalError.replay }
            try storage.execute("INSERT INTO plans(plan_id,digest,nonce,finished) VALUES(?,?,?,0)", [plan.id.uuidString, plan.digest, nonce.uuidString])
            try storage.execute("INSERT INTO audits(plan_id,plan_payload,envelope) VALUES(?,?,?)", [plan.id.uuidString, String(decoding: try canonical(snapshot.plan), as: UTF8.self), envelope])
            try validateAuditConsistency()
        }
    }

    /// Complete represented plan and historical backup receipts precede a prepared step.
    /// A receipt is a hash observation, not a promise that the backup is still verified.
    public func prepareAudited(plan: VerifiedTransactionPlan, step: TransactionStep,
                               backupReceipts: [BackupAuditReceipt], at date: Date) throws {
        try requireAuditSchema()
        try storage.transaction {
            try validateAuditConsistency()
            let existing = try boundSnapshot(plan)
            try requireOpen(plan.id.uuidString)
            let index = existing.observations.count
            guard index < plan.steps.count, plan.steps[index] == step,
                  existing.observations.allSatisfy({ observation in
                      guard let effects = observation.effects,
                            let prior = plan.steps.first(where: { $0.id == observation.stepID }) else { return false }
                      return Self.disposition(effects, action: prior.action) == .succeeded
                  }),
                  Set(backupReceipts.map(\.targetID)) == Set(plan.targets.map(\.id)),
                  backupReceipts.count == plan.targets.count,
                  backupReceipts.allSatisfy({ $0.observedAt <= date }) else { throw JournalError.invalidTransition }
            if !existing.observations.isEmpty {
                guard try canonical(existing.backups) == canonical(backupReceipts) else { throw JournalError.invalidTransition }
            }
            let next = RecoveryAuditSnapshot(plan: existing.plan, backups: backupReceipts,
                observations: existing.observations + [.init(stepID: step.id, preparedAt: date)])
            let envelope = try encoded(next)
            try storage.execute("INSERT INTO steps(plan_id,step_index,operation_id,result) VALUES(?,?,?,NULL)", [plan.id.uuidString, String(index), step.id])
            try storage.execute("UPDATE audits SET envelope=? WHERE plan_id=?", [envelope, plan.id.uuidString])
            try validateAuditConsistency()
        }
    }

    public func recordAuditedResult(plan: VerifiedTransactionPlan, step: TransactionStep,
                                    effects: StepEffects, at date: Date) throws {
        try requireAuditSchema()
        try storage.transaction {
            try validateAuditConsistency()
            let existing = try boundSnapshot(plan)
            try requireOpen(plan.id.uuidString)
            guard let last = existing.observations.last, last.stepID == step.id, last.effects == nil,
                  plan.steps.contains(step) else { throw JournalError.invalidTransition }
            let next = RecoveryAuditSnapshot(plan: existing.plan, backups: existing.backups,
                observations: existing.observations.dropLast() + [.init(stepID: step.id, preparedAt: last.preparedAt, resultAt: date, effects: effects)])
            let envelope = try encoded(next)
            let result = Self.disposition(effects, action: step.action)
            try storage.execute("UPDATE steps SET result=? WHERE plan_id=? AND operation_id=?", [result.rawValue, plan.id.uuidString, step.id])
            try storage.execute("UPDATE audits SET envelope=? WHERE plan_id=?", [envelope, plan.id.uuidString])
            try validateAuditConsistency()
        }
    }

    /// Closes audit bookkeeping, including an observed failed outcome. Not a success claim.
    public func finishAudited(plan: VerifiedTransactionPlan) throws {
        try requireAuditSchema()
        try storage.transaction {
            try validateAuditConsistency()
            let existing = try boundSnapshot(plan)
            try requireOpen(plan.id.uuidString)
            guard existing.observations.allSatisfy({ $0.effects != nil }) else { throw JournalError.invalidTransition }
            let next = RecoveryAuditSnapshot(plan: existing.plan, backups: existing.backups,
                observations: existing.observations, auditClosed: true)
            try storage.execute("UPDATE audits SET envelope=? WHERE plan_id=?", [try encoded(next), plan.id.uuidString])
            try storage.execute("UPDATE plans SET finished=1 WHERE plan_id=?", [plan.id.uuidString])
            try validateAuditConsistency()
        }
    }

    /// Local recovery observation only. Even valid content hashes are not authentication.
    public func recoveryEntries(includeFinished: Bool = false) throws -> [RecoveryJournalEntry] {
        try requireAuditSchema()
        return try storage.snapshot {
            try validateAuditConsistency()
            return try entries().filter { includeFinished || !$0.finished }.map { entry in
                if let snapshot = try auditSnapshot(entry.planID) { return .audit(snapshot) }
                return .legacyEvidenceUnavailable(entry)
            }
        }
    }

    func validateAuditConsistency() throws {
        do { try checkAuditConsistency() }
        catch { storage.poison(); throw error }
    }

    private func checkAuditConsistency() throws {
        try storage.requireAuditResourceBounds()
        guard storage.schema == .auditV2 else { throw JournalError.unsupportedSchema }
        guard try storage.rows("PRAGMA foreign_key_check").isEmpty else { throw JournalError.storageFailure }
        for entry in try entries() {
            let legacy = try storage.integer("SELECT count(*) FROM legacy_plans WHERE plan_id=?", [entry.planID])
            let snapshot = try auditSnapshot(entry.planID)
            guard (legacy == 1 && snapshot == nil) || (legacy == 0 && snapshot != nil) else { throw JournalError.storageFailure }
            guard let snapshot else { continue }
            guard snapshot.plan.id.uuidString == entry.planID, snapshot.plan.digest == entry.digest,
                  snapshot.auditClosed == entry.finished, snapshot.observations.count == entry.steps.count else { throw JournalError.storageFailure }
            for (index, pair) in zip(entry.steps, snapshot.observations).enumerated() {
                let (step, observation) = pair
                guard step.index == index, step.operationID == observation.stepID,
                      step.result == observation.effects.map({ Self.disposition($0, action: snapshot.plan.steps[index].action) }) else { throw JournalError.storageFailure }
            }
        }
    }

    private func requireAuditSchema() throws {
        guard storage.schema == .auditV2 else { throw JournalError.unsupportedSchema }
    }
    private func boundSnapshot(_ plan: VerifiedTransactionPlan) throws -> RecoveryAuditSnapshot {
        guard let existing = try auditSnapshot(plan.id.uuidString),
              try canonical(existing.plan) == canonical(AuditPlan(recording: plan)) else { throw JournalError.invalidTransition }
        return existing
    }
    private func auditSnapshot(_ id: String) throws -> RecoveryAuditSnapshot? {
        let rows = try storage.rows("SELECT CASE WHEN length(CAST(plan_payload AS BLOB))<=131072 THEN plan_payload END,CASE WHEN length(CAST(envelope AS BLOB))<=180000 THEN envelope END FROM audits WHERE plan_id=?", [id])
        guard !rows.isEmpty else { return nil }
        guard rows.count == 1, let original = rows[0][0], let text = rows[0][1],
              original.utf8.count <= RecoveryAudit.maximumPayloadBytes, text.utf8.count <= RecoveryAudit.maximumEnvelopeBytes else { throw JournalError.storageFailure }
        do {
            let snapshot = try RecoveryAudit.decode(Data(text.utf8))
            guard try canonical(snapshot.plan) == Data(original.utf8) else { throw JournalError.storageFailure }
            return snapshot
        }
        catch { throw JournalError.storageFailure }
    }
    private func entries() throws -> [JournalEntry] {
        try storage.rows("SELECT plan_id,digest,finished FROM plans ORDER BY rowid").map { row in
            guard let id = row[0], let digest = row[1], let finished = row[2], ["0", "1"].contains(finished) else { throw JournalError.storageFailure }
            let steps = try storage.rows("SELECT step_index,operation_id,result FROM steps WHERE plan_id=? ORDER BY step_index", [id]).map { item in
                guard let indexText = item[0], let index = Int(indexText), let operation = item[1] else { throw JournalError.storageFailure }
                let result = item[2].flatMap(StepResult.init(rawValue:))
                guard item[2] == nil || result != nil else { throw JournalError.storageFailure }
                return JournalStep(index: index, operationID: operation, result: result)
            }
            return JournalEntry(planID: id, digest: digest, steps: steps, finished: finished == "1")
        }
    }
    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func encoded(_ snapshot: RecoveryAuditSnapshot) throws -> String {
        String(decoding: try RecoveryAudit.encode(snapshot), as: UTF8.self)
    }
    private static func disposition(_ e: StepEffects, action: TransactionAction) -> StepResult {
        if [e.file, e.runtime, e.registration, e.permission].contains(.failed) { return .failed }
        return e.isVerified(for: action) ? .succeeded : .unverified
    }
}

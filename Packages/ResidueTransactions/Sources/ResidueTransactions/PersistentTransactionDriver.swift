import Foundation
import ResidueCore
import ResiduePersistence

/// A typed test integration seam; not an IPC API or a production execution gate.
public protocol TransactionOperations: Sendable {
    func authorize(plan: VerifiedTransactionPlan) async throws -> Bool
    func revalidate(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> Bool
    func prepareBackup(plan: VerifiedTransactionPlan, target: ImpactTarget) async throws -> VerifiedBackup
    func perform(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> StepEffects
}

public enum PersistentDriverError: Error { case invalidSequence, invalidReport }

/// One instance serves one claimed plan. SQLite owns durable replay protection.
/// Does not launch processes, mutate sources, authenticate callers or open any gate.
public actor PersistentTransactionDriver: TransactionDriver {
    private let journal: TransactionJournal
    private let operations: any TransactionOperations
    private var boundPlan: UUID?
    private var boundDigest: String?
    private var claimStarted = false
    private var nextIndex = 0
    private var prepared: TransactionStep?
    private var performed = false
    private var executing = false
    private var stopped = false
    private var results: [String: StepResult] = [:]

    public init(journal: TransactionJournal, operations: any TransactionOperations) {
        self.journal = journal; self.operations = operations
    }

    public func claim(nonce: UUID, plan: VerifiedTransactionPlan) async throws -> Bool {
        guard !claimStarted else { return false }
        claimStarted = true
        do { try await journal.claim(planID: plan.id.uuidString, digest: plan.digest, nonce: nonce.uuidString) }
        catch JournalError.replay { return false }
        boundPlan = plan.id; boundDigest = plan.digest
        return true
    }
    public func authorize(plan: VerifiedTransactionPlan) async throws -> Bool {
        try check(plan)
        return try await operations.authorize(plan: plan)
    }
    public func revalidate(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> Bool {
        try check(plan)
        guard plan.steps.contains(step) else { throw PersistentDriverError.invalidSequence }
        return try await operations.revalidate(plan: plan, step: step)
    }
    public func prepareBackup(plan: VerifiedTransactionPlan, target: ImpactTarget) async throws -> VerifiedBackup {
        try check(plan)
        guard plan.targets.contains(where: { $0.id == target.id && $0.fingerprint == target.fingerprint }) else {
            throw PersistentDriverError.invalidSequence
        }
        return try await operations.prepareBackup(plan: plan, target: target)
    }
    public func journalPrepared(plan: VerifiedTransactionPlan, step: TransactionStep) async throws {
        try check(plan)
        guard prepared == nil, nextIndex < plan.steps.count, plan.steps[nextIndex] == step else {
            throw PersistentDriverError.invalidSequence
        }
        // Reserve before suspension; another call cannot prepare/perform concurrently.
        stopped = true
        try await journal.prepare(planID: plan.id.uuidString, operationID: step.id)
        prepared = step; performed = false; stopped = false
    }
    public func perform(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> StepEffects {
        try check(plan)
        guard prepared == step, !performed, !executing else { throw PersistentDriverError.invalidSequence }
        executing = true
        defer { executing = false; performed = true }
        return try await operations.perform(plan: plan, step: step)
    }
    public func journalResult(plan: VerifiedTransactionPlan, result: TransactionStepResult) async throws {
        try check(plan)
        guard let step = prepared, step.id == result.stepID, performed, !executing else { throw PersistentDriverError.invalidSequence }
        let outcome = Self.classify(result.effects, for: step.action)
        stopped = true
        try await journal.recordResult(planID: plan.id.uuidString, operationID: step.id, result: outcome)
        results[step.id] = outcome
        prepared = nil; nextIndex += 1
        stopped = outcome != .succeeded
    }

    /// Invoke only after the coordinator returns completed. A failed/cancelled or
    /// uncertain report leaves the durable journal unfinished for read-only review.
    public func finalize(plan: VerifiedTransactionPlan, report: TransactionReport) async throws {
        try check(plan)
        guard report.planID == plan.id, report.completed, report.failure == nil,
              prepared == nil, nextIndex == plan.steps.count,
              report.results.map(\.stepID) == plan.steps.map(\.id),
              zip(plan.steps, report.results).allSatisfy({ Self.classify($1.effects, for: $0.action) == .succeeded }),
              results.count == plan.steps.count, results.values.allSatisfy({ $0 == .succeeded }) else {
            throw PersistentDriverError.invalidReport
        }
        stopped = true
        try await journal.finish(planID: plan.id.uuidString)
    }

    private func check(_ plan: VerifiedTransactionPlan) throws {
        guard !stopped, boundPlan == plan.id, boundDigest == plan.digest else { throw PersistentDriverError.invalidSequence }
    }
    private static func classify(_ effects: StepEffects, for action: TransactionAction) -> StepResult {
        let all = [effects.file, effects.runtime, effects.registration, effects.permission]
        if all.contains(.failed) { return .failed }
        guard effects.permission == .notAttempted,
              action != .bootoutExactService || effects.file == .notAttempted,
              action != .quarantineLaunchConfiguration || effects.runtime == .notAttempted else { return .unverified }
        let required = action == .bootoutExactService ? effects.runtime : effects.file
        guard required == .succeeded else { return .unverified }
        // Registration is observational: pending refresh is not a successful purge.
        // A genuinely unverified registration outcome cannot advance the saga.
        guard effects.registration != .unverified else { return .unverified }
        return .succeeded
    }
}

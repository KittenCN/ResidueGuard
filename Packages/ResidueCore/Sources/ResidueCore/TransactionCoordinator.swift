import Foundation

/// There is intentionally no production-enabled case in P3 preparation.
public enum TransactionGate: Sendable { case closed, syntheticTests }
public protocol TransactionDriver: Sendable {
    /// Must durably and atomically reject reused nonce OR plan ID/digest before any other stateful operation.
    func claim(nonce: UUID, plan: VerifiedTransactionPlan) async throws -> Bool
    /// Must authorize the whole plan before a subset can proceed.
    func authorize(plan: VerifiedTransactionPlan) async throws -> Bool
    /// Re-observe all impact, scope, profile and identity, not just a cached path string.
    func revalidate(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> Bool
    func prepareBackup(plan: VerifiedTransactionPlan, target: ImpactTarget) async throws -> VerifiedBackup
    func journalPrepared(plan: VerifiedTransactionPlan, step: TransactionStep) async throws
    /// Future implementation must validate an anchored handle at the effect boundary (TOCTOU).
    /// A thrown call may have partially changed state; the coordinator reports unverified.
    func perform(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> StepEffects
    func journalResult(plan: VerifiedTransactionPlan, result: TransactionStepResult) async throws
}

/// In-memory orchestration tested by fakes. It is not wired into the app and cannot open a production gate.
public actor TransactionCoordinator {
    private let gate: TransactionGate
    private let driver: any TransactionDriver
    private let now: @Sendable () -> Date
    private var consumed = Set<UUID>()
    private var consumedPlans = Set<UUID>()
    private var running = false
    public init(driver: any TransactionDriver, gate: TransactionGate = .closed, now: @escaping @Sendable () -> Date = { Date() }) {
        self.driver = driver; self.gate = gate; self.now = now
    }
    public func run(plan: VerifiedTransactionPlan, consent: TransactionConsent) async -> TransactionReport {
        var results: [TransactionStepResult] = []
        func report(_ failure: TransactionFailure?) -> TransactionReport {
            .init(planID: plan.id, completed: failure == nil, failure: failure, results: results)
        }
        guard gate == .syntheticTests else { return report(.gateClosed) }
        guard !running else { return report(.busy) }
        guard !consumed.contains(consent.nonce), !consumedPlans.contains(plan.id) else { return report(.replay) }
        guard consent.digest == plan.digest, consent.scope == plan.scope, consent.profileID == plan.profileID,
              consent.expiresAt <= plan.expiresAt, consent.expiresAt > plan.createdAt,
              consent.confirmationEvents.count == plan.requiredConfirmations,
              Set(consent.confirmationEvents).count == plan.requiredConfirmations else { return report(.invalidConsent) }
        running = true; defer { running = false }
        do {
            try checkTimeAndCancellation(plan, consent)
            consumed.insert(consent.nonce); consumedPlans.insert(plan.id)
            let claimed: Bool
            do { claimed = try await driver.claim(nonce: consent.nonce, plan: plan) }
            catch { throw TransactionFailure.journalFailed }
            guard claimed else { throw TransactionFailure.replay }
            try checkTimeAndCancellation(plan, consent)
            let authorized: Bool
            do { authorized = try await driver.authorize(plan: plan) }
            catch { throw TransactionFailure.authorizationDenied }
            guard authorized else { throw TransactionFailure.authorizationDenied }
            try checkTimeAndCancellation(plan, consent)
            // Prepare every backup before any source mutation; a later backup failure cannot leave a partial batch.
            for target in plan.targets {
                for step in plan.steps where step.targetID == target.id { try await validate(plan, step, consent) }
                let backup: VerifiedBackup
                do { backup = try await driver.prepareBackup(plan: plan, target: target) }
                catch { throw TransactionFailure.backupFailed }
                guard backup.verified, backup.targetID == target.id, backup.fingerprint == target.fingerprint else { throw TransactionFailure.backupFailed }
                try checkTimeAndCancellation(plan, consent)
            }
            for step in plan.steps {
                try await validate(plan, step, consent)
                do { try await driver.journalPrepared(plan: plan, step: step) }
                catch { throw TransactionFailure.journalFailed }
                // Revalidate after journal suspension; concrete driver must still close the final effect race.
                try await validate(plan, step, consent)
                let effects: StepEffects
                do { effects = try await driver.perform(plan: plan, step: step) }
                catch {
                    let uncertain = StepEffects(file: step.action == .quarantineLaunchConfiguration ? .unverified : .notAttempted,
                        runtime: step.action == .bootoutExactService ? .unverified : .notAttempted,
                        registration: .unverified)
                    let result = TransactionStepResult(stepID: step.id, effects: uncertain)
                    results.append(result)
                    do { try await driver.journalResult(plan: plan, result: result) }
                    catch { throw TransactionFailure.journalFailed }
                    throw TransactionFailure.outcomeUnverified
                }
                let result = TransactionStepResult(stepID: step.id, effects: effects); results.append(result)
                do { try await driver.journalResult(plan: plan, result: result) }
                catch { throw TransactionFailure.journalFailed }
                if effects.hasFailure { throw TransactionFailure.effectFailed }
                guard effects.isVerified(for: step.action) else { throw TransactionFailure.outcomeUnverified }
                try checkTimeAndCancellation(plan, consent)
            }
            return report(nil)
        } catch let error as TransactionFailure { return report(error) }
        catch { return report(.outcomeUnverified) }
    }
    private func validate(_ plan: VerifiedTransactionPlan, _ step: TransactionStep, _ consent: TransactionConsent) async throws {
        try checkTimeAndCancellation(plan, consent)
        let fresh: Bool
        do { fresh = try await driver.revalidate(plan: plan, step: step) }
        catch { throw TransactionFailure.revalidationFailed }
        guard fresh else { throw TransactionFailure.revalidationFailed }
        try checkTimeAndCancellation(plan, consent)
    }
    private func checkTimeAndCancellation(_ plan: VerifiedTransactionPlan, _ consent: TransactionConsent) throws {
        guard !Task.isCancelled else { throw TransactionFailure.cancelled }
        let date = now()
        guard date >= plan.createdAt, date < plan.expiresAt, date < consent.expiresAt else { throw TransactionFailure.expired }
    }
}

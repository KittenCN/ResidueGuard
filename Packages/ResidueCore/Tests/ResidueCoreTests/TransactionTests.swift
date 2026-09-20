import Foundation
import Testing
@testable import ResidueCore

private let transactionNow = Date(timeIntervalSince1970: 2000)
private func transactionPlan(present: Bool = false) throws -> VerifiedTransactionPlan {
    try .validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID, createdAt: transactionNow,
        expiresAt: transactionNow.addingTimeInterval(120),
        steps: [.init(id: "stop", targetID: "a", action: .bootoutExactService, fingerprint: "fp"),
                .init(id: "isolate", targetID: "a", action: .quarantineLaunchConfiguration, fingerprint: "fp", dependencies: ["stop"])],
        targets: [.init(id: "a", displayName: "Synthetic", presence: present ? .present : .highConfidenceOrphan, fingerprint: "fp")], impactApproved: true)
}
private func receipt(_ plan: VerifiedTransactionPlan, nonce: UUID = UUID()) -> TransactionConsent {
    .init(nonce: nonce, digest: plan.digest, scope: plan.scope, profileID: plan.profileID,
          expiresAt: plan.expiresAt, confirmationEvents: (0..<plan.requiredConfirmations).map { _ in UUID() })
}
private actor FakeTransactionDriver: TransactionDriver {
    enum Fault { case uncertainRegistrationStop, uncertainRegistrationLast, none, journalClaim, backup, journalPrepare, fingerprintAfterStop, service, uncertainService, resultJournal, authorization, unexpectedPermission }
    let fault: Fault
    var events: [String] = []
    var nonces = Set<UUID>()
    var planIDs = Set<UUID>()
    init(_ fault: Fault = .none) { self.fault = fault }
    func claim(nonce: UUID, plan: VerifiedTransactionPlan) throws -> Bool {
        events.append("claim")
        if fault == .journalClaim { throw TransactionFailure.journalFailed }
        let freshNonce = nonces.insert(nonce).inserted
        let freshPlan = planIDs.insert(plan.id).inserted
        return freshNonce && freshPlan
    }
    func authorize(plan: VerifiedTransactionPlan) -> Bool { events.append("authorize"); return fault != .authorization }
    func revalidate(plan: VerifiedTransactionPlan, step: TransactionStep) -> Bool {
        events.append("validate:\(step.id)")
        return !(fault == .fingerprintAfterStop && events.contains("perform:stop"))
    }
    func prepareBackup(plan: VerifiedTransactionPlan, target: ImpactTarget) -> VerifiedBackup {
        events.append("backup")
        return .init(targetID: target.id, fingerprint: target.fingerprint, verified: fault != .backup)
    }
    func journalPrepared(plan: VerifiedTransactionPlan, step: TransactionStep) throws {
        events.append("prepare:\(step.id)")
        if fault == .journalPrepare { throw TransactionFailure.journalFailed }
    }
    func perform(plan: VerifiedTransactionPlan, step: TransactionStep) throws -> StepEffects {
        events.append("perform:\(step.id)")
        if step.action == .bootoutExactService {
            if fault == .uncertainService { throw TransactionFailure.outcomeUnverified }
            return .init(runtime: fault == .service ? .failed : .succeeded, registration: fault == .uncertainRegistrationStop ? .unverified : .pendingSystemRefresh, permission: fault == .unexpectedPermission ? .succeeded : .notAttempted)
        }
        return .init(file: .succeeded, registration: fault == .uncertainRegistrationLast ? .unverified : .pendingSystemRefresh)
    }
    func journalResult(plan: VerifiedTransactionPlan, result: TransactionStepResult) throws {
        events.append("result:\(result.stepID)")
        if fault == .resultJournal { throw TransactionFailure.journalFailed }
    }
}
@Test func transactionProductionGateIsClosed() async throws {
    let p = try transactionPlan(); let driver = FakeTransactionDriver()
    let coordinator = TransactionCoordinator(driver: driver, now: { transactionNow })
    let report = await coordinator.run(plan: p, consent: receipt(p))
    #expect(report.failure == .gateClosed)
    let events = await driver.events; #expect(events.isEmpty)
}
@Test func transactionJournalBackupOrderingAndSeparateEffects() async throws {
    let p = try transactionPlan(); let driver = FakeTransactionDriver()
    let coordinator = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
    let report = await coordinator.run(plan: p, consent: receipt(p))
    #expect(report.completed)
    #expect(report.results.count == 2)
    #expect(report.results[0].effects.runtime == .succeeded)
    #expect(report.results[0].effects.file == .notAttempted)
    #expect(report.results[1].effects.file == .succeeded)
    #expect(report.results[1].effects.registration == .pendingSystemRefresh)
    let events = await driver.events
    #expect(events.firstIndex(of: "backup")! < events.firstIndex(of: "perform:stop")!)
    for id in ["stop", "isolate"] {
        #expect(events.firstIndex(of: "prepare:\(id)")! < events.firstIndex(of: "perform:\(id)")!)
        #expect(events.firstIndex(of: "perform:\(id)")! < events.firstIndex(of: "result:\(id)")!)
    }
}
@Test func transactionPreparationFailuresCauseZeroEffects() async throws {
    let p = try transactionPlan()
    for fault in [FakeTransactionDriver.Fault.journalClaim, .backup, .journalPrepare, .authorization] {
        let driver = FakeTransactionDriver(fault)
        let coordinator = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
        let report = await coordinator.run(plan: p, consent: receipt(p))
        #expect(!report.completed)
        let events = await driver.events; #expect(!events.contains { $0.hasPrefix("perform:") })
    }
}
@Test func transactionStopsAfterServiceFingerprintOrJournalFailure() async throws {
    let p = try transactionPlan()
    for fault in [FakeTransactionDriver.Fault.service, .uncertainService, .fingerprintAfterStop, .resultJournal, .unexpectedPermission] {
        let driver = FakeTransactionDriver(fault)
        let coordinator = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
        let report = await coordinator.run(plan: p, consent: receipt(p))
        #expect(!report.completed)
        let events = await driver.events; #expect(events.contains("perform:stop")); #expect(!events.contains("perform:isolate"))
        if fault == .uncertainService { #expect(report.results.first?.effects.runtime == .unverified) }
    }
}
@Test func transactionReplayPersistsAcrossCoordinatorsThroughDriver() async throws {
    let p = try transactionPlan(); let driver = FakeTransactionDriver(); let consent = receipt(p)
    let first = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
    let second = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
    _ = await first.run(plan: p, consent: consent)
    let replay = await first.run(plan: p, consent: consent)
    let otherReplay = await second.run(plan: p, consent: receipt(p))
    #expect(replay.failure == .replay); #expect(otherReplay.failure == .replay)
    let events = await driver.events; #expect(events.filter { $0 == "perform:stop" }.count == 1)
}
@Test func transactionExpiryAndMalformedConsentRejectBeforeDriver() async throws {
    let p = try transactionPlan(present: true); let driver = FakeTransactionDriver()
    let expired = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow.addingTimeInterval(120) })
    #expect(await expired.run(plan: p, consent: receipt(p)).failure == .expired)
    let coordinator = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
    let event = UUID()
    let invalid = TransactionConsent(nonce: UUID(), digest: p.digest, scope: p.scope, profileID: p.profileID,
        expiresAt: p.expiresAt, confirmationEvents: [event, event])
    #expect(await coordinator.run(plan: p, consent: invalid).failure == .invalidConsent)
    let events = await driver.events; #expect(events.isEmpty)
}
@Test func transactionCancelledBeforeEffects() async throws {
    let p = try transactionPlan(); let driver = FakeTransactionDriver()
    let coordinator = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await coordinator.run(plan: p, consent: receipt(p))
    }
    #expect(await task.value.failure == .cancelled)
    let events = await driver.events; #expect(events.isEmpty)
}
@Test func recoveryNeverOverwritesOrRestoresPermissionGrant() {
    #expect(RecoveryPolicy.evaluate(.init(backupVerified: true, destinationAbsent: false, softwareReinstalled: false, identityUnchanged: true, metadataCompatible: true, scopeVerified: true)) == .blockedConflict)
    #expect(RecoveryPolicy.evaluate(.init(backupVerified: true, destinationAbsent: true, softwareReinstalled: true, identityUnchanged: true, metadataCompatible: true, scopeVerified: true)) == .blockedConflict)
    #expect(RecoveryPolicy.evaluate(.init(backupVerified: false, destinationAbsent: true, softwareReinstalled: false, identityUnchanged: true, metadataCompatible: true, scopeVerified: true)) == .blockedUnverified)
    #expect(RecoveryPolicy.evaluate(.init(backupVerified: true, destinationAbsent: true, softwareReinstalled: false, identityUnchanged: true, metadataCompatible: true, scopeVerified: true, permissionGrant: true)) == .permissionGrantNotRestorable)
    #expect(RecoveryPolicy.evaluate(.init(backupVerified: true, destinationAbsent: true, softwareReinstalled: false, identityUnchanged: true, metadataCompatible: true, scopeVerified: true)) == .configurationOnlyRequiresNewPlan)
    #expect(!RecoveryPolicy.automaticServiceRestartAllowed)
}

@Test func transactionPlanRejectsUnsafeDependenciesAndUnknownImpact() {
    let target = ImpactTarget(id: "a", displayName: "Synthetic", presence: .highConfidenceOrphan, fingerprint: "fp")
    let isolate = TransactionStep(id: "isolate", targetID: "a", action: .quarantineLaunchConfiguration, fingerprint: "fp")
    #expect(throws: TransactionFailure.invalidPlan) {
        try VerifiedTransactionPlan.validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID, createdAt: transactionNow,
            expiresAt: transactionNow.addingTimeInterval(120), steps: [isolate], targets: [target], impactApproved: true)
    }
    let stop = TransactionStep(id: "stop", targetID: "a", action: .bootoutExactService, fingerprint: "fp")
    let unknown = ImpactTarget(id: "a", displayName: "Synthetic", presence: .unknown, fingerprint: "fp")
    #expect(throws: TransactionFailure.invalidPlan) {
        try VerifiedTransactionPlan.validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID, createdAt: transactionNow,
            expiresAt: transactionNow.addingTimeInterval(120), steps: [stop], targets: [unknown], impactApproved: true)
    }
}

@Test func transactionRejectsSharedScopeAndNonSyntheticProfile() {
    let target = ImpactTarget(id: "a", displayName: "Synthetic", presence: .highConfidenceOrphan, fingerprint: "fp")
    let stop = TransactionStep(id: "stop", targetID: "a", action: .bootoutExactService, fingerprint: "fp")
    for (scope, profile) in [("machine", VerifiedTransactionPlan.syntheticProfileID), ("unknown", VerifiedTransactionPlan.syntheticProfileID), ("currentUser", "production")] {
        #expect(throws: TransactionFailure.invalidPlan) {
            try VerifiedTransactionPlan.validate(scope: scope, profileID: profile, createdAt: transactionNow,
                expiresAt: transactionNow.addingTimeInterval(120), steps: [stop], targets: [target], impactApproved: true)
        }
    }
}

@Test func uncertainRegistrationCannotCompleteEvenOnFinalStep() async throws {
    for fault in [FakeTransactionDriver.Fault.uncertainRegistrationStop, .uncertainRegistrationLast] {
        let plan = try transactionPlan()
        let driver = FakeTransactionDriver(fault)
        let coordinator = TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { transactionNow })
        let result = await coordinator.run(plan: plan, consent: receipt(plan))
        #expect(!result.completed)
        #expect(result.failure == .outcomeUnverified)
        #expect(result.results.count == (fault == .uncertainRegistrationStop ? 1 : 2))
    }
}

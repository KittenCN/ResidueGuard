import Foundation
import Testing
import ResidueRecovery

private let start = Date(timeIntervalSince1970: 1000)
private func assessment(_ digit: String = "a", at: Date = start) throws -> SyntheticRecoveryAssessment {
    let h = String(repeating: digit, count: 64)
    return try .init(observedAt: at, sourceAbsenceSHA256: h, quarantineSHA256: h,
                     backupSHA256: h, programSHA256: h, runtimeSHA256: h, rootsSHA256: h)
}
@MainActor private func confirmed(_ session: SyntheticRecoverySession, _ a: SyntheticRecoveryAssessment) throws -> SyntheticRecoveryConsent {
    let first = try session.presentFirst(now: start, assessment: a)
    try session.acceptFirst(first, now: start, assessment: a)
    let second = try session.presentSecond(now: start, assessment: a)
    return try session.acceptSecond(second, riskPhrase: SyntheticRecoverySession.riskPhrase, now: start, assessment: a)
}

@Test @MainActor func completeSyntheticFlowIsSingleConsumptionAndNeverAuthority() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    let session = SyntheticRecoverySession(plan: plan), consent = try confirmed(session, a)
    let result = try session.consume(consent, now: start, assessment: a)
    #expect(!a.permitsMutation && !plan.permitsMutation && !session.permitsMutation && !consent.permitsMutation && !result.permitsMutation)
    #expect(plan.requiredConfirmations == 2)
    #expect(session.stage == .consumed)
    #expect(throws: (any Error).self) { try session.consume(consent, now: start, assessment: a) }
}
@Test func assessmentRejectsMalformedHashesAndNonfiniteTimes() throws {
    #expect(throws: (any Error).self) { try assessment("g") }
    #expect(throws: (any Error).self) { try assessment("A") }
    #expect(throws: (any Error).self) { try assessment("aa") }
    #expect(throws: (any Error).self) { try assessment(at: Date(timeIntervalSince1970: .nan)) }
    #expect(throws: (any Error).self) { try assessment(at: Date(timeIntervalSince1970: .infinity)) }
}
@Test func planAlwaysNewAndCannotExtendAssessmentLifetime() throws {
    let a = try assessment(), first = try SyntheticRecoveryPlan(assessment: a, now: start)
    let next = try SyntheticRecoveryPlan(assessment: a, now: start.addingTimeInterval(100))
    #expect(first.id != next.id && first.digest != next.digest)
    #expect(first.expiresAt == next.expiresAt && first.expiresAt == start.addingTimeInterval(120))
    for delta in [-1.0, 120, 121, .infinity, .nan] {
        #expect(throws: (any Error).self) { try SyntheticRecoveryPlan(assessment: a, now: start.addingTimeInterval(delta)) }
    }
}
@Test @MainActor func wrongPhraseAndOutOfOrderEventsInvalidate() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    let outOfOrder = SyntheticRecoverySession(plan: plan)
    #expect(throws: (any Error).self) { try outOfOrder.presentSecond(now: start, assessment: a) }
    #expect(outOfOrder.stage == .invalidated)
    let session = SyntheticRecoverySession(plan: plan)
    let first = try session.presentFirst(now: start, assessment: a)
    #expect(!first.permitsMutation)
    try session.acceptFirst(first, now: start, assessment: a)
    let second = try session.presentSecond(now: start, assessment: a)
    #expect(throws: (any Error).self) { try session.acceptSecond(second, riskPhrase: "同意", now: start, assessment: a) }
    #expect(session.stage == .invalidated)
}
@Test @MainActor func firstEventCannotServeAsSecondOrBeReplayed() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    let session = SyntheticRecoverySession(plan: plan)
    let first = try session.presentFirst(now: start, assessment: a)
    try session.acceptFirst(first, now: start, assessment: a)
    _ = try session.presentSecond(now: start, assessment: a)
    #expect(throws: (any Error).self) { try session.acceptSecond(first, riskPhrase: SyntheticRecoverySession.riskPhrase, now: start, assessment: a) }
    let another = SyntheticRecoverySession(plan: plan)
    _ = try another.presentFirst(now: start, assessment: a)
    #expect(throws: (any Error).self) { try another.acceptFirst(first, now: start, assessment: a) }
}
@Test @MainActor func expiryClockRegressionAndChangedAssessmentRevoke() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    for at in [start.addingTimeInterval(120), start.addingTimeInterval(-1), Date(timeIntervalSince1970: .nan)] {
        let session = SyntheticRecoverySession(plan: plan), consent = try confirmed(session, a)
        #expect(throws: (any Error).self) { try session.consume(consent, now: at, assessment: a) }
        #expect(session.stage == .invalidated)
    }
    let session = SyntheticRecoverySession(plan: plan), consent = try confirmed(session, a)
    let changed = try assessment("b")
    #expect(throws: (any Error).self) { try session.consume(consent, now: start, assessment: changed) }
    // Even identical supplied hash values with a new observation identity require a new plan.
    let again = SyntheticRecoverySession(plan: plan)
    #expect(throws: (any Error).self) { try again.presentFirst(now: start, assessment: assessment()) }
}
@Test @MainActor func replacementAndForeignSessionCannotReuseConsent() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    let session = SyntheticRecoverySession(plan: plan), consent = try confirmed(session, a)
    let foreign = SyntheticRecoverySession(plan: plan)
    _ = try confirmed(foreign, a)
    #expect(throws: (any Error).self) { try foreign.consume(consent, now: start, assessment: a) }
    try session.replacePlan(try SyntheticRecoveryPlan(assessment: a, now: start))
    #expect(throws: (any Error).self) { try session.consume(consent, now: start, assessment: a) }
}
@Test @MainActor func explicitCancellationAndReplacementRejectOldPresentation() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    let session = SyntheticRecoverySession(plan: plan)
    let old = try session.presentFirst(now: start, assessment: a)
    try session.replacePlan(try SyntheticRecoveryPlan(assessment: a, now: start))
    _ = try session.presentFirst(now: start, assessment: a)
    #expect(throws: (any Error).self) { try session.acceptFirst(old, now: start, assessment: a) }
    let cancelled = SyntheticRecoverySession(plan: plan), consent = try confirmed(cancelled, a)
    cancelled.invalidate()
    #expect(throws: (any Error).self) { try cancelled.consume(consent, now: start, assessment: a) }
}

@Test @MainActor func retiredPlansCannotBeReintroduced() throws {
    let a = try assessment(), original = try SyntheticRecoveryPlan(assessment: a, now: start)
    let session = SyntheticRecoverySession(plan: original)
    let consent = try confirmed(session, a)
    _ = try session.consume(consent, now: start, assessment: a)
    #expect(throws: (any Error).self) { try session.replacePlan(original) }
    #expect(session.stage == .invalidated)
}

@Test @MainActor func everyEvidenceDomainChangeInvalidates() throws {
    let a = try assessment(), plan = try SyntheticRecoveryPlan(assessment: a, now: start)
    for index in 0..<6 {
        var hashes = Array(repeating: String(repeating: "a", count: 64), count: 6)
        hashes[index] = String(repeating: "b", count: 64)
        let changed = try SyntheticRecoveryAssessment(observedAt: start, sourceAbsenceSHA256: hashes[0],
            quarantineSHA256: hashes[1], backupSHA256: hashes[2], programSHA256: hashes[3], runtimeSHA256: hashes[4], rootsSHA256: hashes[5])
        let session = SyntheticRecoverySession(plan: plan), consent = try confirmed(session, a)
        #expect(throws: (any Error).self) { try session.consume(consent, now: start, assessment: changed) }
    }
}

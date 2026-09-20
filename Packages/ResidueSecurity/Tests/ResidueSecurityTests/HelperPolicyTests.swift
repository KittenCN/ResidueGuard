import Foundation
import Testing
@testable import ResidueSecurity

private let time = Date(timeIntervalSince1970: 1_000_000)
private let profile = ClientProfile(bundleID: "test.client", teamID: "TESTTEAM", designatedRequirement: "test exact requirement", uid: 501, sessionID: 7)
private func caller(bundle: String = "test.client", uid: UInt32 = 501, session: UInt32 = 7, requirement: String = "test exact requirement") -> VerifiedCaller {
    VerifiedCaller(bundleID: bundle, teamID: "TESTTEAM", designatedRequirement: requirement, uid: uid, sessionID: session, connectionID: UUID())
}
private struct SyntheticTransport: CallerAuthenticating {
    let value: VerifiedCaller
    func verifiedCaller() async throws -> VerifiedCaller { value }
}
private func plan(scope: HelperScope = .currentUser, impact: ReviewedServerPlan.Impact = .boundedUserOrphans) -> ReviewedServerPlan {
    ReviewedServerPlan(id: UUID(), source: KnownSourceID(id: UUID(), kind: .launchAgentConfiguration), digest: String(repeating: "a", count: 64), scope: scope, impact: impact, createdAt: time)
}
@Test func defaultTransportNeverAuthenticates() async throws {
    let policy = HelperPolicy(profile: profile)
    let p = plan(); try await policy.registerForPolicyReview(p)
    await #expect(throws: SecurityFailure.transportUnavailable) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time) }
    #expect(await policy.executionAvailability() == .authorizationUnavailable)
}
@Test func sameTeamWrongBundleUserSessionOrRequirementRejected() async throws {
    for identity in [caller(bundle: "other.client"), caller(uid: 502), caller(session: 8), caller(requirement: "different requirement")] {
        let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: identity))
        let p = plan(); try await policy.registerForPolicyReview(p)
        await #expect(throws: SecurityFailure.callerRejected) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time) }
    }
}
@Test func expiredAndFuturePlansRejected() async throws {
    let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
    let p = plan(); try await policy.registerForPolicyReview(p)
    for now in [time.addingTimeInterval(-1), time.addingTimeInterval(120)] {
        await #expect(throws: SecurityFailure.expired) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: now) }
    }
    let token = try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time)
    await #expect(throws: SecurityFailure.expired) { try await policy.consumeForPolicyReview(token, now: time.addingTimeInterval(120)) }
}
@Test func replayAndSecondTokenForSamePlanRejected() async throws {
    let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
    let p = plan(); try await policy.registerForPolicyReview(p)
    let first = try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time)
    let second = try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time)
    _ = try await policy.consumeForPolicyReview(first, now: time)
    for token in [first, second] {
        await #expect(throws: SecurityFailure.replayed) { try await policy.consumeForPolicyReview(token, now: time) }
    }
    await #expect(throws: SecurityFailure.replayed) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time) }
}
@Test func tamperedDigestOrNonceRejected() async throws {
    let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
    let p = plan(); try await policy.registerForPolicyReview(p)
    let token = try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time)
    let badDigest = PlanToken(planID: token.planID, source: token.source, scope: token.scope, digest: String(repeating: "b", count: 64), nonce: token.nonce, expiresAt: token.expiresAt)
    await #expect(throws: SecurityFailure.tokenMismatch) { try await policy.consumeForPolicyReview(badDigest, now: time) }
    let unknown = PlanToken(planID: token.planID, source: token.source, scope: token.scope, digest: token.planDigest, nonce: UUID(), expiresAt: token.expiresAt)
    await #expect(throws: SecurityFailure.unknownToken) { try await policy.consumeForPolicyReview(unknown, now: time) }
}
@Test func versionsAndUnauthorizedScopeBlocked() async throws {
    let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
    let p = plan(scope: .sharedMachine); try await policy.registerForPolicyReview(p)
    await #expect(throws: SecurityFailure.unsupportedVersion) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 2, policyVersion: 1, now: time) }
    await #expect(throws: SecurityFailure.unsupportedVersion) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 2, now: time) }
    await #expect(throws: SecurityFailure.scopeBlocked) { try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time) }
    for impact in [ReviewedServerPlan.Impact.unknown, .protected, .shared] {
        let blocked = plan(impact: impact); try await policy.registerForPolicyReview(blocked)
        await #expect(throws: SecurityFailure.impactBlocked) { try await policy.preparePolicyReview(planID: blocked.id, protocolVersion: 1, policyVersion: 1, now: time) }
    }
}
@Test func requestsContainOnlyOpaqueIDs() throws {
    let request = HelperRequest.prepare(protocolVersion: 1, source: KnownSourceID(id: UUID(), kind: .launchAgentConfiguration), scope: .currentUser)
    let data = try JSONEncoder().encode(request)
    _ = try JSONDecoder().decode(HelperRequest.self, from: data)
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("path")); #expect(!json.contains("command")); #expect(!json.contains("executable"))
}

private actor ChangingTransport: CallerAuthenticating {
    var identity: VerifiedCaller
    init(_ identity: VerifiedCaller) { self.identity = identity }
    func change(_ identity: VerifiedCaller) { self.identity = identity }
    func verifiedCaller() async throws -> VerifiedCaller { identity }
}
@Test func tokenIsBoundToOriginalConnection() async throws {
    let transport = ChangingTransport(caller())
    let policy = HelperPolicy(profile: profile, authenticator: transport)
    let p = plan(); try await policy.registerForPolicyReview(p)
    let token = try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time)
    await transport.change(caller())
    await #expect(throws: SecurityFailure.tokenMismatch) { try await policy.consumeForPolicyReview(token, now: time) }
}
@Test func serverPlanChangeInvalidatesToken() async throws {
    let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
    let p = plan(); try await policy.registerForPolicyReview(p)
    let token = try await policy.preparePolicyReview(planID: p.id, protocolVersion: 1, policyVersion: 1, now: time)
    let changed = ReviewedServerPlan(id: p.id, source: p.source, digest: String(repeating: "b", count: 64), scope: p.scope, impact: .boundedUserOrphans, createdAt: time)
    try await policy.registerForPolicyReview(changed)
    await #expect(throws: SecurityFailure.tokenMismatch) { try await policy.consumeForPolicyReview(token, now: time) }
}

@Test func replacingReviewedPlanInvalidatesTokenEvenWhenDigestIsReused() async throws {
    // An integration error must not let a caller-supplied/reused digest conceal changed impact or freshness.
    for (changedImpact, changedCreation) in [(ReviewedServerPlan.Impact.containsInstalled, time),
                                              (.boundedUserOrphans, time.addingTimeInterval(1))] {
        let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
        let original = plan(); try await policy.registerForPolicyReview(original)
        let token = try await policy.preparePolicyReview(planID: original.id, protocolVersion: 1, policyVersion: 1, now: time)
        let replacement = ReviewedServerPlan(id: original.id, source: original.source, digest: original.digest,
            scope: original.scope, impact: changedImpact, createdAt: changedCreation)
        try await policy.registerForPolicyReview(replacement)
        await #expect(throws: SecurityFailure.tokenMismatch) {
            try await policy.consumeForPolicyReview(token, now: time.addingTimeInterval(2))
        }
    }
}

@Test func revertingServerPlanDoesNotReviveOldToken() async throws {
    let policy = HelperPolicy(profile: profile, authenticator: SyntheticTransport(value: caller()))
    let original = plan(); try await policy.registerForPolicyReview(original)
    let old = try await policy.preparePolicyReview(planID: original.id, protocolVersion: 1, policyVersion: 1, now: time)
    try await policy.registerForPolicyReview(original)
    await #expect(throws: SecurityFailure.tokenMismatch) { try await policy.consumeForPolicyReview(old, now: time) }
    let fresh = try await policy.preparePolicyReview(planID: original.id, protocolVersion: 1, policyVersion: 1, now: time)
    _ = try await policy.consumeForPolicyReview(fresh, now: time)
    #expect(await policy.executionAvailability() == .authorizationUnavailable)
}

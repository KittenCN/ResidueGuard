import Foundation

/// Trusted server-side planning input, deliberately unavailable to external/GUI construction.
/// Not Codable: it cannot be supplied as IPC input.
struct ReviewedServerPlan: Sendable {
    let id: UUID
    let source: KnownSourceID
    let digest: String
    let scope: HelperScope
    let impact: Impact
    let createdAt: Date
    enum Impact: Sendable { case boundedUserOrphans, containsInstalled, unknown, protected, shared }
}
public enum PolicyReviewOutcome: Sendable { case reviewOnlyValidated }

/// In-memory contract simulator, not a helper or executor. No filesystem/process/XPC operations.
/// Tokens intentionally die at process restart; durable execution journal is not implemented.
public actor HelperPolicy {
    private struct Issued: Sendable { let token: PlanToken; let caller: VerifiedCaller }
    private let profile: ClientProfile
    private let authenticator: any CallerAuthenticating
    private var plans: [UUID: ReviewedServerPlan] = [:]
    private var issued: [UUID: Issued] = [:]
    private var consumed: Set<UUID> = []
    private var consumedPlans: Set<UUID> = []
    public init(profile: ClientProfile, authenticator: any CallerAuthenticating = UnavailableTransportAuthenticator()) {
        self.profile = profile; self.authenticator = authenticator
    }
    // Future server-side planner integration only; not callable from an importing GUI module.
    func registerForPolicyReview(_ plan: ReviewedServerPlan) throws {
        guard plans.count < 1024 else { throw SecurityFailure.capacityExceeded }
        plans[plan.id] = plan
    }
    public func preparePolicyReview(planID: UUID, protocolVersion: Int, policyVersion: Int) async throws -> PlanToken {
        try await preparePolicyReview(planID: planID, protocolVersion: protocolVersion, policyVersion: policyVersion, now: nil)
    }
    func preparePolicyReview(planID: UUID, protocolVersion: Int, policyVersion: Int, now: Date?) async throws -> PlanToken {
        guard protocolVersion == 1, policyVersion == 1 else { throw SecurityFailure.unsupportedVersion }
        let caller = try await authenticator.verifiedCaller()
        let now = now ?? Date()
        guard profile.accepts(caller) else { throw SecurityFailure.callerRejected }
        guard !consumedPlans.contains(planID) else { throw SecurityFailure.replayed }
        guard let plan = plans[planID] else { throw SecurityFailure.unknownSource }
        guard plan.scope == .currentUser else { throw SecurityFailure.scopeBlocked }
        guard plan.impact == .boundedUserOrphans || plan.impact == .containsInstalled else { throw SecurityFailure.impactBlocked }
        guard plan.digest.count == 64, plan.digest.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw SecurityFailure.invalidDigest }
        let expiry = plan.createdAt.addingTimeInterval(120)
        guard now >= plan.createdAt, now < expiry else { throw SecurityFailure.expired }
        guard issued.count < 1024 else { throw SecurityFailure.capacityExceeded }
        let token = PlanToken(planID: plan.id, source: plan.source, scope: plan.scope, digest: plan.digest, nonce: UUID(), expiresAt: expiry)
        issued[token.nonce] = Issued(token: token, caller: caller)
        return token
    }
    public func consumeForPolicyReview(_ token: PlanToken) async throws -> PolicyReviewOutcome {
        try await consumeForPolicyReview(token, now: nil)
    }
    func consumeForPolicyReview(_ token: PlanToken, now: Date?) async throws -> PolicyReviewOutcome {
        guard token.protocolVersion == 1, token.policyVersion == 1 else { throw SecurityFailure.unsupportedVersion }
        let caller = try await authenticator.verifiedCaller()
        let now = now ?? Date()
        guard profile.accepts(caller) else { throw SecurityFailure.callerRejected }
        guard !consumed.contains(token.nonce), !consumedPlans.contains(token.planID) else { throw SecurityFailure.replayed }
        guard let original = issued[token.nonce] else { throw SecurityFailure.unknownToken }
        guard original.caller == caller, original.token == token else { throw SecurityFailure.tokenMismatch }
        guard let plan = plans[token.planID], plan.digest == token.planDigest, plan.source == token.source else { throw SecurityFailure.tokenMismatch }
        guard now >= plan.createdAt, now < token.expiresAt else { throw SecurityFailure.expired }
        guard plan.scope == .currentUser, token.scope == .currentUser else { throw SecurityFailure.scopeBlocked }
        guard plan.impact == .boundedUserOrphans || plan.impact == .containsInstalled else { throw SecurityFailure.impactBlocked }
        consumed.insert(token.nonce)
        consumedPlans.insert(token.planID)
        issued.removeValue(forKey: token.nonce)
        return .reviewOnlyValidated
    }
    /// Never turns successful pure policy checks into an OS authorization claim or actual action.
    public func executionAvailability() -> SecurityFailure { .authorizationUnavailable }
}

import Foundation

public enum ConsentStage: String, Sendable { case ready, firstPresented, firstConfirmed, secondPresented, complete, invalidated }
/// Demonstrates independent confirmation events for a dry-run; it cannot authorize real writes.
public struct ConsentSession: Sendable {
    public static let riskPhrase = "清理仍安装软件的设置"
    public let plan: DryRunPlan
    public private(set) var stage: ConsentStage = .ready
    private var presentationID: UUID?
    public init(plan: DryRunPlan) { self.plan = plan }
    public mutating func invalidate() { stage = .invalidated; presentationID = nil }
    @discardableResult
    public mutating func presentFirst(now: Date, currentDigest: String) -> UUID? {
        guard validate(now, currentDigest), stage == .ready else { return nil }
        guard plan.requirement == .one || plan.requirement == .two else { return nil }
        let id = UUID(); presentationID = id; stage = .firstPresented; return id
    }
    @discardableResult
    public mutating func confirmFirst(presentation: UUID, now: Date, currentDigest: String) -> Bool {
        guard validate(now, currentDigest), stage == .firstPresented, presentation == presentationID else { return false }
        presentationID = nil; stage = plan.requirement == .one ? .complete : .firstConfirmed; return true
    }
    public mutating func presentSecond(now: Date, currentDigest: String) -> UUID? {
        guard validate(now, currentDigest), stage == .firstConfirmed, plan.requirement == .two else { return nil }
        let id = UUID(); presentationID = id; stage = .secondPresented; return id
    }
    @discardableResult
    public mutating func confirmSecond(presentation: UUID, phrase: String, now: Date, currentDigest: String) -> Bool {
        guard validate(now, currentDigest), stage == .secondPresented, presentation == presentationID,
              phrase == Self.riskPhrase else { return false }
        presentationID = nil; stage = .complete; return true
    }
    private mutating func validate(_ now: Date, _ currentDigest: String) -> Bool {
        guard !plan.digest.isEmpty, currentDigest == plan.digest, now >= plan.createdAt, now < plan.expiresAt,
              plan.policyVersion == ConfirmationPolicy.version else { invalidate(); return false }
        return stage != .invalidated
    }
}

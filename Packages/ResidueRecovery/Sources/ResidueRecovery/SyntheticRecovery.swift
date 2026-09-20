import Foundation
import CryptoKit

public enum SyntheticRecoveryError: Error { case invalidEvidence, expiredOrChanged, invalidEvent, consumed }

/// Caller-supplied synthetic hashes. No filesystem, runtime, or historical authenticity verification.
public struct SyntheticRecoveryAssessment: Equatable, Sendable {
    public let id: UUID
    public let observedAt: Date
    public let sourceAbsenceSHA256: String
    public let quarantineSHA256: String
    public let backupSHA256: String
    public let programSHA256: String
    public let runtimeSHA256: String
    public let rootsSHA256: String
    public var permitsMutation: Bool { false }
    public init(observedAt: Date, sourceAbsenceSHA256: String, quarantineSHA256: String,
                backupSHA256: String, programSHA256: String, runtimeSHA256: String, rootsSHA256: String) throws {
        let hashes = [sourceAbsenceSHA256, quarantineSHA256, backupSHA256, programSHA256, runtimeSHA256, rootsSHA256]
        guard observedAt.timeIntervalSince1970.isFinite, hashes.allSatisfy({ h in
            h.utf8.count == 64 && h.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }) else { throw SyntheticRecoveryError.invalidEvidence }
        id = UUID(); self.observedAt = observedAt; self.sourceAbsenceSHA256 = sourceAbsenceSHA256
        self.quarantineSHA256 = quarantineSHA256; self.backupSHA256 = backupSHA256
        self.programSHA256 = programSHA256; self.runtimeSHA256 = runtimeSHA256; self.rootsSHA256 = rootsSHA256
    }
}

public struct SyntheticRecoveryPlan: Sendable {
    public let id: UUID
    public let assessment: SyntheticRecoveryAssessment
    public let createdAt: Date
    public let expiresAt: Date
    public let digest: String
    public var permitsMutation: Bool { false }
    public let requiredConfirmations = 2
    public let operation = "synthetic-owned-iso01-restore-file-only"
    public init(assessment: SyntheticRecoveryAssessment, now: Date) throws {
        guard now.timeIntervalSince1970.isFinite, now >= assessment.observedAt,
              now.timeIntervalSince(assessment.observedAt) < 120 else { throw SyntheticRecoveryError.expiredOrChanged }
        let id = UUID(), expiry = assessment.observedAt.addingTimeInterval(120)
        // Fixed schema and ordered JSON array avoid ambiguous concatenation; not an external wire format.
        let fields = ["synthetic-owned-iso01-restore-file-only-v1", "two-independent-events", "no-service-mutation",
            id.uuidString, assessment.id.uuidString, String(assessment.observedAt.timeIntervalSince1970),
            String(now.timeIntervalSince1970), String(expiry.timeIntervalSince1970), assessment.sourceAbsenceSHA256,
            assessment.quarantineSHA256, assessment.backupSHA256, assessment.programSHA256, assessment.runtimeSHA256, assessment.rootsSHA256]
        let data = try JSONSerialization.data(withJSONObject: fields)
        self.id = id; self.assessment = assessment; createdAt = now; expiresAt = expiry
        digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Opaque event handle, not proof of a real human interaction. No Codable or public initializer.
public struct SyntheticRecoveryPresentation: Sendable {
    fileprivate let nonce: UUID
    fileprivate let planID: UUID
    fileprivate let ordinal: Int
    public var permitsMutation: Bool { false }
}
public struct SyntheticRecoveryConsent: Sendable {
    fileprivate let nonce: UUID
    public let planID: UUID
    public let planDigest: String
    public var permitsMutation: Bool { false }
}
public struct SyntheticRecoveryConsumption: Sendable {
    public let planID: UUID
    public let planDigest: String
    public var permitsMutation: Bool { false }
}
public enum SyntheticRecoveryStage: Sendable { case ready, firstPresented, firstAccepted, secondPresented, complete, consumed, invalidated }

/// In-memory, serialized synthetic event model. Never executes or authorizes a file operation.
/// Reference semantics prevent copying an unconsumed session to replay its receipt.
@MainActor public final class SyntheticRecoverySession {
    public static let riskPhrase = "恢复仍安装软件的启动配置"
    public private(set) var plan: SyntheticRecoveryPlan
    public private(set) var stage: SyntheticRecoveryStage = .ready
    public var permitsMutation: Bool { false }
    private var presentation: SyntheticRecoveryPresentation?
    private var receiptNonce: UUID?
    private var seenPlanIDs: Set<UUID>
    private var lastTime: Date
    public init(plan: SyntheticRecoveryPlan) { self.plan = plan; lastTime = plan.createdAt; seenPlanIDs = [plan.id] }
    public func replacePlan(_ next: SyntheticRecoveryPlan) throws {
        invalidate()
        guard seenPlanIDs.count < 64, seenPlanIDs.insert(next.id).inserted else { throw SyntheticRecoveryError.invalidEvent }
        plan = next; lastTime = next.createdAt; stage = .ready
    }
    public func invalidate() { presentation = nil; receiptNonce = nil; stage = .invalidated }
    private func check(now: Date, assessment: SyntheticRecoveryAssessment) throws {
        guard stage != .consumed else { throw SyntheticRecoveryError.consumed }
        guard stage != .invalidated, now.timeIntervalSince1970.isFinite,
              now >= lastTime, now >= plan.createdAt, now < plan.expiresAt,
              assessment == plan.assessment else { invalidate(); throw SyntheticRecoveryError.expiredOrChanged }
        lastTime = now
    }
    public func presentFirst(now: Date, assessment: SyntheticRecoveryAssessment) throws -> SyntheticRecoveryPresentation {
        try check(now: now, assessment: assessment)
        guard stage == .ready else { invalidate(); throw SyntheticRecoveryError.invalidEvent }
        let event = SyntheticRecoveryPresentation(nonce: UUID(), planID: plan.id, ordinal: 1)
        presentation = event; stage = .firstPresented; return event
    }
    public func acceptFirst(_ event: SyntheticRecoveryPresentation, now: Date, assessment: SyntheticRecoveryAssessment) throws {
        try check(now: now, assessment: assessment)
        guard stage == .firstPresented, event.planID == plan.id, event.ordinal == 1,
              event.nonce == presentation?.nonce else { invalidate(); throw SyntheticRecoveryError.invalidEvent }
        presentation = nil; stage = .firstAccepted
    }
    public func presentSecond(now: Date, assessment: SyntheticRecoveryAssessment) throws -> SyntheticRecoveryPresentation {
        try check(now: now, assessment: assessment)
        guard stage == .firstAccepted else { invalidate(); throw SyntheticRecoveryError.invalidEvent }
        let event = SyntheticRecoveryPresentation(nonce: UUID(), planID: plan.id, ordinal: 2)
        presentation = event; stage = .secondPresented; return event
    }
    public func acceptSecond(_ event: SyntheticRecoveryPresentation, riskPhrase: String,
                             now: Date, assessment: SyntheticRecoveryAssessment) throws -> SyntheticRecoveryConsent {
        try check(now: now, assessment: assessment)
        guard stage == .secondPresented, event.planID == plan.id, event.ordinal == 2,
              event.nonce == presentation?.nonce, riskPhrase == Self.riskPhrase else { invalidate(); throw SyntheticRecoveryError.invalidEvent }
        presentation = nil; stage = .complete
        let nonce = UUID(); receiptNonce = nonce
        return SyntheticRecoveryConsent(nonce: nonce, planID: plan.id, planDigest: plan.digest)
    }
    public func consume(_ consent: SyntheticRecoveryConsent, now: Date,
                        assessment: SyntheticRecoveryAssessment) throws -> SyntheticRecoveryConsumption {
        try check(now: now, assessment: assessment)
        guard stage == .complete, consent.planID == plan.id, consent.planDigest == plan.digest,
              consent.nonce == receiptNonce else { invalidate(); throw SyntheticRecoveryError.invalidEvent }
        receiptNonce = nil; stage = .consumed
        return SyntheticRecoveryConsumption(planID: plan.id, planDigest: plan.digest)
    }
}

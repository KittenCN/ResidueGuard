import Foundation

/// Point-in-time observations, never execution authorization.
public enum RecoveryObjectState: String, Sendable {
    case absent, matchesReceipt, conflict, unverified
}
public enum RecoveryInspectionDecision: String, Sendable {
    case invalidPlan, unsafeStorage, invalidBackup, crossVolume
    case sourcePresentNoMoveRequired
    case restoreCandidateRequiresNewPlan
    case objectsMissing, conflict, unverified
}
public struct RecoveryInspection: Sendable {
    public let observedAt: Date
    public let source: RecoveryObjectState
    public let quarantined: RecoveryObjectState
    public let backupVerified: Bool
    public let decision: RecoveryInspectionDecision
    public let permitsMutation = false
    public let runtimeInspected = false
}

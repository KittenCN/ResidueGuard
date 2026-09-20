import Foundation
import CryptoKit

public enum TransactionAction: String, Codable, Sendable { case bootoutExactService, quarantineLaunchConfiguration }
public struct TransactionStep: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let targetID: String
    public let action: TransactionAction
    public let fingerprint: String
    public let dependencies: [String]
    public init(id: String, targetID: String, action: TransactionAction, fingerprint: String, dependencies: [String] = []) {
        self.id = id; self.targetID = targetID; self.action = action; self.fingerprint = fingerprint; self.dependencies = dependencies
    }
}
public enum TransactionFailure: String, Error, Sendable {
    case gateClosed, invalidPlan, invalidConsent, expired, replay, busy, cancelled
    case authorizationDenied, revalidationFailed, backupFailed, journalFailed, effectFailed, outcomeUnverified
}
/// Pure validation is not an OS trust boundary. No initializer from DryRunPlan exists.
/// A future platform executor must authenticate its caller and independently verify every claim.
public struct VerifiedTransactionPlan: Sendable {
    public static let syntheticProfileID = "synthetic-transaction-v1"
    public static let currentUserScope = "currentUser"
    public let id: UUID
    public let scope: String
    public let profileID: String
    public let createdAt: Date
    public let expiresAt: Date
    public let steps: [TransactionStep]
    public let targets: [ImpactTarget]
    public let requiredConfirmations: Int
    public let digest: String
    public static func validate(scope: String, profileID: String, createdAt: Date, expiresAt: Date,
                                steps: [TransactionStep], targets: [ImpactTarget], impactApproved: Bool) throws -> Self {
        guard scope == Self.currentUserScope, profileID == Self.syntheticProfileID, createdAt < expiresAt,
              expiresAt.timeIntervalSince(createdAt) <= 120, !steps.isEmpty,
              Set(steps.map(\.id)).count == steps.count,
              Set(targets.map(\.id)).count == targets.count,
              Set(steps.map(\.targetID)) == Set(targets.map(\.id)),
              targets.allSatisfy({ !$0.id.isEmpty && !$0.fingerprint.isEmpty }) else { throw TransactionFailure.invalidPlan }
        let requirement = ConfirmationPolicy.evaluate(.init(selectedRecordCount: steps.count,
            affectedPresence: targets.map { $0.presence.rawValue }, allOperationsSupported: true,
            hasProtectedOrManagedTarget: targets.contains(where: \.isProtectedOrManaged), scopeBounded: true,
            expandedImpactExplicitlyApproved: impactApproved, planFresh: true))
        guard requirement == .one || requirement == .two else { throw TransactionFailure.invalidPlan }
        var preceding: [String: TransactionStep] = [:]
        var actions = Set<String>()
        for step in steps {
            guard !step.id.isEmpty, !step.fingerprint.isEmpty,
                  targets.contains(where: { $0.id == step.targetID && $0.fingerprint == step.fingerprint }),
                  step.dependencies.allSatisfy({ preceding[$0] != nil }),
                  actions.insert(step.targetID + ":" + step.action.rawValue).inserted else { throw TransactionFailure.invalidPlan }
            if step.action == .quarantineLaunchConfiguration {
                guard step.dependencies.contains(where: { preceding[$0]?.targetID == step.targetID && preceding[$0]?.action == .bootoutExactService }) else { throw TransactionFailure.invalidPlan }
            }
            preceding[step.id] = step
        }
        struct Binding: Encodable {
            let id: UUID; let scope: String; let profileID: String; let createdAt: Date; let expiresAt: Date
            let steps: [TransactionStep]; let targets: [ImpactTarget]; let confirmations: Int; let policy: String
        }
        let id = UUID(); let count = requirement == .one ? 1 : 2
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Binding(id: id, scope: scope, profileID: profileID, createdAt: createdAt,
            expiresAt: expiresAt, steps: steps, targets: targets, confirmations: count, policy: ConfirmationPolicy.version))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Self(id: id, scope: scope, profileID: profileID, createdAt: createdAt, expiresAt: expiresAt,
            steps: steps, targets: targets, requiredConfirmations: count, digest: digest)
    }
}
/// Synthetic orchestration receipt; never a helper authorization credential.
public struct TransactionConsent: Sendable {
    public let nonce: UUID
    public let digest: String
    public let scope: String
    public let profileID: String
    public let expiresAt: Date
    public let confirmationEvents: [UUID]
    public init(nonce: UUID, digest: String, scope: String, profileID: String, expiresAt: Date, confirmationEvents: [UUID]) {
        self.nonce = nonce; self.digest = digest; self.scope = scope; self.profileID = profileID
        self.expiresAt = expiresAt; self.confirmationEvents = confirmationEvents
    }
}
public enum TransactionEffect: String, Codable, Sendable { case notAttempted, succeeded, failed, unverified, pendingSystemRefresh }
public struct StepEffects: Codable, Equatable, Sendable {
    public let file: TransactionEffect
    public let runtime: TransactionEffect
    public let registration: TransactionEffect
    public let permission: TransactionEffect
    public init(file: TransactionEffect = .notAttempted, runtime: TransactionEffect = .notAttempted,
                registration: TransactionEffect = .notAttempted, permission: TransactionEffect = .notAttempted) {
        self.file = file; self.runtime = runtime; self.registration = registration; self.permission = permission
    }
    var hasFailure: Bool { [file, runtime, registration, permission].contains(.failed) }
    /// Pending registration refresh is observational, never proof of a purge.
    public func isVerified(for action: TransactionAction) -> Bool {
        guard !hasFailure, permission == .notAttempted, registration != .unverified,
              action != .bootoutExactService || file == .notAttempted,
              action != .quarantineLaunchConfiguration || runtime == .notAttempted else { return false }
        return (action == .bootoutExactService ? runtime : file) == .succeeded
    }
}
public struct TransactionStepResult: Sendable { public let stepID: String; public let effects: StepEffects }
public struct TransactionReport: Sendable {
    public let planID: UUID
    public let completed: Bool
    public let failure: TransactionFailure?
    public let results: [TransactionStepResult]
}
public struct VerifiedBackup: Sendable {
    public let targetID: String
    public let fingerprint: String
    public let verified: Bool
    public init(targetID: String, fingerprint: String, verified: Bool) {
        self.targetID = targetID; self.fingerprint = fingerprint; self.verified = verified
    }
}

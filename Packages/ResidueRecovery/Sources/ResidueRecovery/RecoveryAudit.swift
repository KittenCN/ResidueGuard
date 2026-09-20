import CryptoKit
import Foundation
import ResidueCore

public enum RecoveryAuditError: Error, Equatable { case oversized, unsupportedVersion, corrupt, invalidSnapshot }

/// Historical data only. There is deliberately no conversion to an executable plan/token.
public struct AuditPlan: Codable, Sendable {
    public let id: UUID
    public let digest: String
    public let scope: String
    public let profileID: String
    public let policyVersion: String
    public let createdAt: Date
    public let expiresAt: Date
    public let requiredConfirmations: Int
    public let steps: [TransactionStep]
    public let targets: [ImpactTarget]
    public init(recording plan: VerifiedTransactionPlan) {
        id = plan.id; digest = plan.digest; scope = plan.scope; profileID = plan.profileID
        policyVersion = ConfirmationPolicy.version; createdAt = plan.createdAt; expiresAt = plan.expiresAt
        requiredConfirmations = plan.requiredConfirmations; steps = plan.steps; targets = plan.targets
    }
}

/// Hash binding of a historical observation, not proof a backup remains present/valid.
public struct BackupAuditReceipt: Codable, Sendable {
    public let targetID: String
    public let contentSHA256: String
    public let metadataSHA256: String
    public let observedAt: Date
    public init(targetID: String, contentSHA256: String, metadataSHA256: String, observedAt: Date) {
        self.targetID = targetID; self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256; self.observedAt = observedAt
    }
}

public struct StepAuditObservation: Codable, Sendable {
    public let stepID: String
    public let preparedAt: Date
    public let resultAt: Date?
    public let effects: StepEffects?
    public init(stepID: String, preparedAt: Date, resultAt: Date? = nil, effects: StepEffects? = nil) {
        self.stepID = stepID; self.preparedAt = preparedAt; self.resultAt = resultAt; self.effects = effects
    }
}

public struct RecoveryAuditSnapshot: Codable, Sendable {
    public let plan: AuditPlan
    public let backups: [BackupAuditReceipt]
    public let observations: [StepAuditObservation]
    public let auditClosed: Bool
    public init(plan: AuditPlan, backups: [BackupAuditReceipt], observations: [StepAuditObservation], auditClosed: Bool = false) {
        self.plan = plan; self.backups = backups; self.observations = observations; self.auditClosed = auditClosed
    }
}

/// Redacted by construction: no source IDs, display names, paths, digests or timestamps.
public struct RecoveryReviewSummary: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let index: Int
        public let action: TransactionAction
        public let effects: StepEffects?
    }
    public let targetCount: Int
    public let recordedBackupCount: Int
    public let plannedStepCount: Int
    public let steps: [Step]
    public let auditClosed: Bool
    public let requiresReadOnlyReview: Bool
    public let automaticExecutionAllowed = false
    public let backupReverificationRequired = true
    public let contentAuthenticityEstablished = false
}

public enum RecoveryAudit {
    public static let schemaVersion = 1 // Audit envelope version, not SQLite journal version.
    public static let maximumPayloadBytes = 131_072
    public static let maximumEnvelopeBytes = 180_000
    private struct Envelope: Codable {
        let schemaVersion: Int
        let contentSHA256: String
        let payload: Data
    }
    /// Callers that persist this sensitive envelope must enforce local 0600 storage.
    /// This package does not perform filesystem I/O or change journal schemas.
    public static func encode(_ snapshot: RecoveryAuditSnapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(snapshot)
        guard payload.count <= maximumPayloadBytes else { throw RecoveryAuditError.oversized }
        return try encoder.encode(Envelope(schemaVersion: schemaVersion, contentSHA256: hash(payload), payload: payload))
    }
    /// A content hash detects accidental corruption, not an attacker who can replace
    /// data and recompute its hash. Successful decoding never establishes trust.
    public static func decode(_ data: Data) throws -> RecoveryAuditSnapshot {
        guard data.count <= maximumEnvelopeBytes else { throw RecoveryAuditError.oversized }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == schemaVersion else { throw RecoveryAuditError.unsupportedVersion }
            guard envelope.payload.count <= maximumPayloadBytes else { throw RecoveryAuditError.oversized }
            guard validHash(envelope.contentSHA256), hash(envelope.payload) == envelope.contentSHA256 else { throw RecoveryAuditError.corrupt }
            let snapshot = try JSONDecoder().decode(RecoveryAuditSnapshot.self, from: envelope.payload)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(snapshot) == envelope.payload,
                  try encoder.encode(envelope) == data else { throw RecoveryAuditError.corrupt }
            try validate(snapshot)
            return snapshot
        } catch let error as RecoveryAuditError { throw error }
        catch { throw RecoveryAuditError.corrupt }
    }
    public static func summary(_ snapshot: RecoveryAuditSnapshot) throws -> RecoveryReviewSummary {
        try validate(snapshot)
        let steps = zip(snapshot.plan.steps, snapshot.observations).enumerated().map {
            RecoveryReviewSummary.Step(index: $0.offset, action: $0.element.0.action, effects: $0.element.1.effects)
        }
        return RecoveryReviewSummary(targetCount: snapshot.plan.targets.count, recordedBackupCount: snapshot.backups.count,
            plannedStepCount: snapshot.plan.steps.count, steps: steps, auditClosed: snapshot.auditClosed,
            requiresReadOnlyReview: true)
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validHash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private static func text(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 1024 && !value.contains("\0") }
    private static func date(_ value: Date) -> Bool { value.timeIntervalSince1970.isFinite }
    private static func validate(_ s: RecoveryAuditSnapshot) throws {
        let p = s.plan
        guard validHash(p.digest), text(p.scope), text(p.profileID), text(p.policyVersion),
              date(p.createdAt), date(p.expiresAt), p.createdAt < p.expiresAt,
              [1, 2].contains(p.requiredConfirmations),
              !p.steps.isEmpty, p.steps.count <= 256, !p.targets.isEmpty, p.targets.count <= 256,
              s.backups.count <= p.targets.count, s.observations.count <= p.steps.count,
              Set(p.targets.map(\.id)).count == p.targets.count,
              Set(p.steps.map(\.id)).count == p.steps.count,
              Set(s.backups.map(\.targetID)).count == s.backups.count,
              Set(p.steps.map(\.targetID)) == Set(p.targets.map(\.id)),
              p.targets.allSatisfy({ text($0.id) && text($0.displayName) && text($0.fingerprint) }) else { throw RecoveryAuditError.invalidSnapshot }
        var preceding = Set<String>()
        for step in p.steps {
            guard text(step.id), text(step.targetID), text(step.fingerprint), step.dependencies.count <= p.steps.count,
                  Set(step.dependencies).count == step.dependencies.count,
                  step.dependencies.allSatisfy({ preceding.contains($0) }),
                  p.targets.contains(where: { $0.id == step.targetID && $0.fingerprint == step.fingerprint }) else { throw RecoveryAuditError.invalidSnapshot }
            preceding.insert(step.id)
        }
        guard s.backups.allSatisfy({ b in p.targets.contains(where: { $0.id == b.targetID }) && validHash(b.contentSHA256) && validHash(b.metadataSHA256) && date(b.observedAt) }) else { throw RecoveryAuditError.invalidSnapshot }
        var previousResultAt = p.createdAt
        for (index, observation) in s.observations.enumerated() {
            guard observation.stepID == p.steps[index].id, date(observation.preparedAt), observation.preparedAt >= previousResultAt,
                  (observation.resultAt == nil) == (observation.effects == nil),
                  observation.resultAt != nil || index == s.observations.count - 1 else { throw RecoveryAuditError.invalidSnapshot }
            if let resultAt = observation.resultAt {
                guard date(resultAt), resultAt >= observation.preparedAt else { throw RecoveryAuditError.invalidSnapshot }
                previousResultAt = resultAt
            }
        }
        guard !s.auditClosed || s.observations.allSatisfy({ $0.effects != nil }) else { throw RecoveryAuditError.invalidSnapshot }
    }
}

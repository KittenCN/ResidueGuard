import Foundation
import CryptoKit

public struct ImpactTarget: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let presence: PresenceState
    public let isProtectedOrManaged: Bool
    public let fingerprint: String
    public init(id: String, displayName: String, presence: PresenceState, isProtectedOrManaged: Bool = false, fingerprint: String) {
        self.id = id; self.displayName = displayName; self.presence = presence
        self.isProtectedOrManaged = isProtectedOrManaged; self.fingerprint = fingerprint
    }
}
public struct PlanningRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let operation: CapabilityOperation
    public let operationKey: String
    public let affectedTargetIDs: [String]
    public let capability: CapabilityDescriptor
    public let scopeBounded: Bool
    public let fingerprint: String
    public init(id: String, operationKey: String, affectedTargetIDs: [String], capability: CapabilityDescriptor, scopeBounded: Bool = true, fingerprint: String, operation: CapabilityOperation = .removeRegistration) {
        self.operation = operation; self.id = id; self.operationKey = operationKey; self.affectedTargetIDs = affectedTargetIDs
        self.capability = capability; self.scopeBounded = scopeBounded; self.fingerprint = fingerprint
    }
}
public struct PlanSnapshot: Codable, Equatable, Sendable {
    public let generation: String
    public let osBuild: String
    public let observedAt: Date
    public let records: [PlanningRecord]
    public let targets: [ImpactTarget]
    public init(generation: String, osBuild: String, records: [PlanningRecord], targets: [ImpactTarget], observedAt: Date = Date()) {
        self.observedAt = observedAt; self.generation = generation; self.osBuild = osBuild; self.records = records; self.targets = targets
    }
}
/// Preview only. There is deliberately no executor, authorization token, or system operation API.
public struct DryRunPlan: Codable, Sendable {
    public let policyVersion: String
    public let snapshotGeneration: String
    public let createdAt: Date
    public let expiresAt: Date
    public let selectedRecordIDs: [String]
    public let operationKeys: [String]
    public let targets: [ImpactTarget]
    public let requirement: ConfirmationRequirement
    public let diagnostics: [String]
    public let digest: String
    public var isDryRun: Bool { true }
}
public enum DryRunPlanner {
    public static func makePlan(selectedRecordIDs: Set<String>, snapshot: PlanSnapshot,
                                expandedImpactApproved: Bool, now: Date) -> DryRunPlan {
        let selected = snapshot.records.filter { selectedRecordIDs.contains($0.id) }
        let keys = Set(selected.map(\.operationKey))
        // Every observation of a shared underlying action contributes impact and restrictions.
        let expandedRecords = snapshot.records.filter { keys.contains($0.operationKey) }
        let targetIDs = Set(expandedRecords.flatMap(\.affectedTargetIDs))
        let targets = snapshot.targets.filter { targetIDs.contains($0.id) }.sorted { $0.id < $1.id }
        let duplicateRecords = Set(snapshot.records.map(\.id)).count != snapshot.records.count
        let duplicateTargets = Set(snapshot.targets.map(\.id)).count != snapshot.targets.count
        let identitiesKnown = Set(selected.map(\.id)) == selectedRecordIDs && Set(targets.map(\.id)) == targetIDs
        let fingerprintsKnown = expandedRecords.allSatisfy { !$0.id.isEmpty && !$0.fingerprint.isEmpty && !$0.operationKey.isEmpty && !$0.affectedTargetIDs.isEmpty }
            && targets.allSatisfy { !$0.id.isEmpty && !$0.fingerprint.isEmpty }
        let consistentOperations = Dictionary(grouping: expandedRecords, by: \.operationKey).values.allSatisfy { Set($0.map(\.fingerprint)).count == 1 && Set($0.map(\.operation)).count == 1 }
        let fresh = now >= snapshot.observedAt && now.timeIntervalSince(snapshot.observedAt) < 120
        let bounded = !snapshot.generation.isEmpty && !snapshot.osBuild.isEmpty && consistentOperations && identitiesKnown && !duplicateRecords && !duplicateTargets && fingerprintsKnown && expandedRecords.allSatisfy(\.scopeBounded)
        let supported = expandedRecords.allSatisfy { $0.capability.permitsPlanning(for: $0.operation, on: snapshot.osBuild) }
        let requirement = ConfirmationPolicy.evaluate(.init(selectedRecordCount: selectedRecordIDs.count,
            affectedPresence: targets.map { $0.presence.rawValue }, allOperationsSupported: supported,
            hasProtectedOrManagedTarget: targets.contains(where: \.isProtectedOrManaged), scopeBounded: bounded,
            expandedImpactExplicitlyApproved: expandedImpactApproved, planFresh: fresh))
        var diagnostics: [String] = ["仅生成 dry-run 预览；未执行任何系统修改。"]
        if !fresh { diagnostics.append("扫描快照过期或来自未来，须重新复核。") }
        if !bounded { diagnostics.append("身份、指纹或实际影响范围无法完整核验。") }
        if !supported { diagnostics.append("当前 OS build 缺少经过验证的操作能力。") }
        if !expandedImpactApproved { diagnostics.append("实际影响集合尚未明确批准。") }
        if requirement == .blocked { diagnostics.append("计划被策略阻断，确认不能越过限制。") }
        struct Binding: Encodable {
            let policy: String; let snapshot: PlanSnapshot; let selection: [String]
            let approved: Bool; let createdAt: Date; let expiresAt: Date
        }
        let expiresAt = min(now.addingTimeInterval(120), snapshot.observedAt.addingTimeInterval(120))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Models have no non-finite numbers; fail closed if encoding nevertheless fails.
        let binding = Binding(policy: ConfirmationPolicy.version, snapshot: snapshot, selection: selectedRecordIDs.sorted(),
                              approved: expandedImpactApproved, createdAt: now, expiresAt: expiresAt)
        let encoded = try? encoder.encode(binding)
        let digest = encoded.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
        return DryRunPlan(policyVersion: ConfirmationPolicy.version, snapshotGeneration: snapshot.generation,
            createdAt: now, expiresAt: expiresAt, selectedRecordIDs: selectedRecordIDs.sorted(), operationKeys: keys.sorted(),
            targets: targets, requirement: encoded == nil ? .blocked : requirement, diagnostics: diagnostics, digest: digest)
    }
}

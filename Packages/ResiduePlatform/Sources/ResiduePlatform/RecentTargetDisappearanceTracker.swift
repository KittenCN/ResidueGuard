import Foundation
import ResidueCore

/// Session-local protective history, never an updater detector or an execution gate.
/// Entries are not evicted: at capacity new baselines are ignored rather than
/// forgetting a previously protected disappearance. No wall-clock expiry exists.
public struct RecentTargetDisappearanceTracker: Sendable {
    private struct Key: Hashable, Sendable {
        let id: RecordIdentity
        let hash: String
        let target: String
        let root: String
        let build: String
    }
    private struct Boundary: Hashable {
        let provider: String
        let scope: String
        let root: String
        let generation: String
    }
    private var history: [Key: Bool] = [:] // false: directly present; true: disappearance latched
    private var lastDate: Date?
    private var lastGeneration: String?
    private let limit: Int
    public init(limit: Int = 20_000) { self.limit = max(1, min(limit, 20_000)) }

    public mutating func apply(_ snapshot: ScanSnapshot, cancelled: Bool = false) -> ScanSnapshot {
        guard snapshot.rows.count <= 20_000, snapshot.coverage.count <= 128 else {
            // Do not drop protective history or re-expose a suspected state when
            // rejecting oversized input. Only project a more conservative result.
            let rows = snapshot.rows.map { row in
                guard row.presence == .suspectedOrphan else { return row }
                return ScanRow(record: row.record, presence: .unknown, capability: row.capability,
                    evidence: row.evidence + ["本次观察超出比较限额，无法核实目标状态；既有保护历史未更新。"],
                    directTargetObservation: row.directTargetObservation)
            }
            return ScanSnapshot(generation: snapshot.generation, observedAt: snapshot.observedAt,
                rows: rows, coverage: snapshot.coverage, applications: snapshot.applications,
                ownershipGraph: snapshot.ownershipGraph)
        }
        var boundaries: [Boundary: [ScanCoverage]] = [:]
        for coverage in snapshot.coverage where coverage.declaredRoots.count == 1 && coverage.userScopes.count == 1 {
            let boundary = Boundary(provider: coverage.providerID, scope: coverage.userScopes[0],
                root: coverage.declaredRoots[0], generation: coverage.generation)
            boundaries[boundary, default: []].append(coverage)
        }
        let fresh = UUID(uuidString: snapshot.generation) != nil
            && snapshot.generation != lastGeneration
            && (lastDate == nil || snapshot.observedAt > lastDate!)
        let canUpdate = fresh && !cancelled && !snapshot.isCancelled
        let duplicates = Dictionary(grouping: snapshot.rows, by: \.id)
        let rows = snapshot.rows.map { row -> ScanRow in
            let record = row.record
            let root = URL(fileURLWithPath: record.sourceArtifact).deletingLastPathComponent().path
            let matches = boundaries[Boundary(provider: record.id.providerID, scope: record.id.scope,
                root: root, generation: snapshot.generation)] ?? []
            guard duplicates[row.id]?.count == 1, record.generation == snapshot.generation,
                  record.parseWarnings.isEmpty, record.id.providerID == "launchd.configuration",
                  !record.id.scope.isEmpty, record.id.scope != "unknown", matches.count == 1,
                  let coverage = matches.first, !["", "unknown", "unverified"].contains(coverage.osBuild),
                  let hash = record.rawMetadata["contentSHA256"], hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  record.targetReferences.count == 1, let target = record.targetReferences.first,
                  target.hasPrefix("/") else { return row }
            let key = Key(id: row.id, hash: hash, target: target, root: root, build: coverage.osBuild)
            let complete = coverage.state == .completeWithinDeclaredScope
                && coverage.errors.isEmpty && coverage.skippedAreas.isEmpty
            if canUpdate && complete {
                switch row.directTargetObservation {
                case .executablePresent:
                    if history[key] != nil || history.count < limit { history[key] = false }
                case .missing:
                    if history[key] != nil { history[key] = true }
                case .unverified: break
                }
            }
            guard history[key] == true, row.directTargetObservation == .missing,
                  row.presence == .suspectedOrphan else { return row }
            return ScanRow(record: record, presence: .unknown, capability: row.capability,
                evidence: row.evidence + ["同一配置的直接目标曾存在，本次未找到；保持无法核实，直到再次直接观察到目标存在。"],
                directTargetObservation: row.directTargetObservation)
        }
        if canUpdate { lastDate = snapshot.observedAt; lastGeneration = snapshot.generation }
        return ScanSnapshot(generation: snapshot.generation, observedAt: snapshot.observedAt,
            rows: rows, coverage: snapshot.coverage, applications: snapshot.applications,
            ownershipGraph: snapshot.ownershipGraph)
    }
}

import Foundation

/// Exact observation boundary, not filesystem authority. Root strings are compared
/// literally; this model neither resolves paths nor grants directory access.
public struct SnapshotComparisonScope: Hashable, Sendable {
    public let providerID: String
    public let userScope: String
    public let declaredRoot: String
    public let osBuild: String
    public init(providerID: String, userScope: String, declaredRoot: String, osBuild: String) {
        self.providerID = providerID; self.userScope = userScope; self.declaredRoot = declaredRoot; self.osBuild = osBuild
    }
}
public struct ScopedSnapshotRecord: Sendable {
    public let record: SourceRecord
    public let scope: SnapshotComparisonScope
    public init(record: SourceRecord, scope: SnapshotComparisonScope) { self.record = record; self.scope = scope }
}
public struct SnapshotComparisonCoverage: Sendable {
    public let scope: SnapshotComparisonScope
    public let generation: String
    public let state: CoverageState
    public init(scope: SnapshotComparisonScope, generation: String, state: CoverageState) {
        self.scope = scope; self.generation = generation; self.state = state
    }
}
public struct ObservationSnapshot: Sendable {
    public let generation: String
    public let records: [ScopedSnapshotRecord]
    public let coverage: [SnapshotComparisonCoverage]
    public init(generation: String, records: [ScopedSnapshotRecord], coverage: [SnapshotComparisonCoverage]) {
        self.generation = generation; self.records = records; self.coverage = coverage
    }
}
public enum SnapshotComparisonDiagnostic: String, Hashable, Sendable {
    case invalidGeneration, invalidScope, invalidRecordBinding, conflictingCoverage, scopeChanged, incompleteCoverage, resourceLimit
}
public struct CoverageAwareSnapshotComparison: Sendable {
    /// First seen in these observations; never "newly installed".
    public let firstObserved: Set<RecordIdentity>
    public let changed: Set<RecordIdentity>
    /// Not observed in the same twice-complete declared scope; still not deletion evidence.
    public let notObserved: Set<RecordIdentity>
    public let ambiguous: Set<RecordIdentity>
    public let limitedScopes: Set<SnapshotComparisonScope>
    public let diagnostics: Set<SnapshotComparisonDiagnostic>
}

extension SnapshotComparison {
    private struct CheckedSnapshot {
        var records: [RecordIdentity: ScopedSnapshotRecord] = [:]
        var complete: Set<SnapshotComparisonScope> = []
        var scopes: Set<SnapshotComparisonScope> = []
        var ambiguous: Set<RecordIdentity> = []
        var limited: Set<SnapshotComparisonScope> = []
        var diagnostics: Set<SnapshotComparisonDiagnostic> = []
    }
    /// Keeps the older array-only comparison available for low-level comparisons.
    /// This overload tracks coverage explicitly and never mutates presence or capabilities.
    public static func compare(previous: ObservationSnapshot, current: ObservationSnapshot) -> CoverageAwareSnapshotComparison {
        let old = checked(previous), new = checked(current)
        let ambiguous = old.ambiguous.union(new.ambiguous)
        let oldIDs = Set(old.records.keys).subtracting(ambiguous), newIDs = Set(new.records.keys).subtracting(ambiguous)
        var limited = old.limited.union(new.limited)
        var diagnostics = old.diagnostics.union(new.diagnostics)
        let changedScopes = old.scopes.symmetricDifference(new.scopes)
        if !changedScopes.isEmpty { diagnostics.insert(.scopeChanged); limited.formUnion(changedScopes) }
        let comparable: Set<SnapshotComparisonScope>
        if previous.generation == current.generation {
            // Reused generation is not a second independent complete observation.
            comparable = []; diagnostics.insert(.invalidGeneration); limited.formUnion(old.scopes.union(new.scopes))
        } else { comparable = old.complete.intersection(new.complete) }
        var changed: Set<RecordIdentity> = []
        for id in oldIDs.intersection(newIDs) {
            guard let a = old.records[id], let b = new.records[id] else { continue }
            if a.scope != b.scope { limited.formUnion([a.scope, b.scope]); diagnostics.insert(.scopeChanged) }
            if !compare(previous: [a.record], current: [b.record]).changed.isEmpty { changed.insert(id) }
        }
        let missing = Set(oldIDs.subtracting(newIDs).filter {
            guard let scope = old.records[$0]?.scope else { return false }
            return comparable.contains(scope)
        })
        // A scope with any ambiguous identity cannot support negative observations.
        return .init(firstObserved: newIDs.subtracting(oldIDs), changed: changed, notObserved: missing,
                     ambiguous: ambiguous, limitedScopes: limited, diagnostics: diagnostics)
    }

    /// GUI may retain the last complete configuration snapshot while continuing to
    /// display partial current results. Unsupported unrelated providers are ignored.
    /// A full per-scope baseline cache can later call this policy for individual groups.
    public static func canUseAsBaseline(snapshot: ObservationSnapshot, providerIDs: Set<String>) -> Bool {
        guard !providerIDs.isEmpty else { return false }
        let selected = ObservationSnapshot(generation: snapshot.generation,
            records: snapshot.records.filter { providerIDs.contains($0.scope.providerID) || providerIDs.contains($0.record.id.providerID) },
            coverage: snapshot.coverage.filter { providerIDs.contains($0.scope.providerID) })
        let value = checked(selected)
        return !value.scopes.isEmpty && value.diagnostics.isEmpty && value.ambiguous.isEmpty
            && value.complete == value.scopes
            && providerIDs.isSubset(of: Set(value.scopes.map(\.providerID)))
    }

    private static func checked(_ input: ObservationSnapshot) -> CheckedSnapshot {
        var output = CheckedSnapshot()
        func known(_ value: String, limit: Int) -> Bool {
            !value.isEmpty && value.utf8.count <= limit && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && !["unknown", "unavailable", "unverified"].contains(value.lowercased())
                && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
        func valid(_ scope: SnapshotComparisonScope) -> Bool {
            known(scope.providerID, limit: 128) && known(scope.userScope, limit: 256)
                && known(scope.declaredRoot, limit: 4096) && scope.declaredRoot.hasPrefix("/")
                && !scope.declaredRoot.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
                && known(scope.osBuild, limit: 128)
        }
        guard input.records.count <= 20000, input.coverage.count <= 256 else {
            output.diagnostics.insert(.resourceLimit); return output
        }
        guard known(input.generation, limit: 256) else { output.diagnostics.insert(.invalidGeneration); return output }
        var coverageCounts: [SnapshotComparisonScope: Int] = [:]
        for item in input.coverage {
            guard valid(item.scope) else { output.diagnostics.insert(.invalidScope); continue }
            output.scopes.insert(item.scope); coverageCounts[item.scope, default: 0] += 1
            if item.generation != input.generation { output.diagnostics.insert(.invalidGeneration); output.limited.insert(item.scope) }
            else if item.state == .completeWithinDeclaredScope { output.complete.insert(item.scope) }
            else { output.diagnostics.insert(.incompleteCoverage); output.limited.insert(item.scope) }
        }
        for (scope, count) in coverageCounts where count != 1 {
            output.diagnostics.insert(.conflictingCoverage); output.limited.insert(scope)
        }
        var recordCounts: [RecordIdentity: Int] = [:]
        var recordScopes: [RecordIdentity: Set<SnapshotComparisonScope>] = [:]
        for item in input.records {
            let id = item.record.id
            recordCounts[id, default: 0] += 1
            recordScopes[id, default: []].insert(item.scope)
            guard valid(item.scope), output.scopes.contains(item.scope), item.scope.providerID == id.providerID,
                  item.scope.userScope == id.scope, known(id.nativeIdentity, limit: 8192) else {
                output.diagnostics.insert(.invalidRecordBinding); output.limited.insert(item.scope); continue
            }
            guard item.record.generation == input.generation else {
                output.diagnostics.insert(.invalidGeneration); output.limited.insert(item.scope); continue
            }
            output.records[id] = item
        }
        for (id, count) in recordCounts where count != 1 {
            output.ambiguous.insert(id)
            output.limited.formUnion(recordScopes[id] ?? [])
        }
        if output.diagnostics.contains(.invalidRecordBinding) || output.diagnostics.contains(.invalidScope) {
            output.limited.formUnion(output.scopes)
        }
        output.complete.subtract(output.limited)
        return output
    }
}

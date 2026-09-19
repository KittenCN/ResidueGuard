import Foundation

/// Missing observations are not evidence of deletion: the next scan may have less coverage.
public struct SnapshotComparison: Sendable {
    public let added: Set<RecordIdentity>
    public let changed: Set<RecordIdentity>
    public let notObserved: Set<RecordIdentity>
    public let ambiguous: Set<RecordIdentity>
    public static func compare(previous: [SourceRecord], current: [SourceRecord]) -> Self {
        let old = Dictionary(grouping: previous, by: \.id)
        let new = Dictionary(grouping: current, by: \.id)
        let ambiguous = Set(old.filter { $0.value.count != 1 }.keys).union(new.filter { $0.value.count != 1 }.keys)
        let oldIDs = Set(old.keys).subtracting(ambiguous), newIDs = Set(new.keys).subtracting(ambiguous)
        let changed = Set(oldIDs.intersection(newIDs).filter { id in
            guard let a = old[id]?.first, let b = new[id]?.first else { return false }
            return a.category != b.category || a.sourceArtifact != b.sourceArtifact || a.displayName != b.displayName ||
                a.declaredAppIDs != b.declaredAppIDs || a.targetReferences != b.targetReferences ||
                a.rawMetadata != b.rawMetadata || a.parseWarnings != b.parseWarnings
        })
        return Self(added: newIDs.subtracting(oldIDs), changed: changed, notObserved: oldIDs.subtracting(newIDs), ambiguous: ambiguous)
    }
}

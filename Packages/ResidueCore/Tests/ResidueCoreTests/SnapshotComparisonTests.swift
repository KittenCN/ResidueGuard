import Foundation
import Testing
@testable import ResidueCore

private func comparisonRecord(_ native: String, value: String, generation: String = "g", scope: String = "user") -> SourceRecord {
    .init(id: .init(providerID: "fixture", scope: scope, nativeIdentity: native), category: "launch", observedAt: .distantPast, generation: generation, sourceArtifact: "/Synthetic/\(native)", displayName: native, declaredAppIDs: [], targetReferences: [], rawMetadata: ["fingerprint": value], parseWarnings: [])
}
@Test func comparisonSeparatesMissingObservationFromDeletionAndIgnoresGeneration() {
    let previous = [comparisonRecord("same", value: "1"), comparisonRecord("missing", value: "1"), comparisonRecord("changed", value: "1")]
    let current = [comparisonRecord("same", value: "1", generation: "new"), comparisonRecord("changed", value: "2"), comparisonRecord("new", value: "1")]
    let difference = SnapshotComparison.compare(previous: previous, current: current)
    #expect(difference.added.count == 1)
    #expect(difference.changed.count == 1)
    #expect(difference.notObserved.count == 1)
    #expect(difference.ambiguous.isEmpty)
}
@Test func comparisonDoesNotCollapseConflictingIdentityOrScopes() {
    let a = comparisonRecord("same", value: "1")
    let b = comparisonRecord("same", value: "2")
    let differentScope = comparisonRecord("same", value: "1", scope: "shared")
    let difference = SnapshotComparison.compare(previous: [a], current: [a, b, differentScope])
    #expect(difference.ambiguous == [a.id])
    #expect(difference.added == [differentScope.id])
    #expect(difference.changed.isEmpty)
}

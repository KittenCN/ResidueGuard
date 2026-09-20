import Foundation
import Testing
@testable import ResidueCore

private func diffScope(root: String = "/Synthetic/LaunchAgents", build: String = "build-a", provider: String = "launchd.configuration", user: String = "currentUser") -> SnapshotComparisonScope {
    .init(providerID: provider, userScope: user, declaredRoot: root, osBuild: build)
}
private func observed(_ name: String, value: String = "a", generation: String = "g1", scope: SnapshotComparisonScope = diffScope()) -> ScopedSnapshotRecord {
    .init(record: .init(id: .init(providerID: scope.providerID, scope: scope.userScope, nativeIdentity: name), category: "launch", observedAt: .distantPast,
        generation: generation, sourceArtifact: scope.declaredRoot + "/" + name, displayName: name, declaredAppIDs: [], targetReferences: [], rawMetadata: ["contentSHA256": value], parseWarnings: []), scope: scope)
}
private func snapshot(_ rows: [ScopedSnapshotRecord], generation: String = "g1", scope: SnapshotComparisonScope = diffScope(), state: CoverageState = .completeWithinDeclaredScope) -> ObservationSnapshot {
    .init(generation: generation, records: rows, coverage: [.init(scope: scope, generation: generation, state: state)])
}
@Test func coverageAwareDifferenceUsesTwiceCompleteScopeAndCrossGenerationContent() {
    let old = snapshot([observed("same"), observed("changed"), observed("missing")])
    let new = snapshot([observed("same", generation: "g2"), observed("changed", value: "b", generation: "g2"), observed("first", generation: "g2")], generation: "g2")
    let diff = SnapshotComparison.compare(previous: old, current: new)
    #expect(diff.firstObserved == [observed("first").record.id])
    #expect(diff.changed == [observed("changed").record.id])
    #expect(diff.notObserved == [observed("missing").record.id])
    #expect(diff.limitedScopes.isEmpty && diff.diagnostics.isEmpty)
}
@Test(arguments: [CoverageState.cancelled, .partial, .permissionDenied, .failed, .unsupported])
func incompleteCoverageNeverMakesNegativeObservationOrBaseline(state: CoverageState) {
    let complete = snapshot([observed("old")])
    let limited = snapshot([], generation: "g2", state: state)
    #expect(SnapshotComparison.compare(previous: complete, current: limited).notObserved.isEmpty)
    #expect(SnapshotComparison.compare(previous: limited, current: complete).notObserved.isEmpty)
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: limited, providerIDs: ["launchd.configuration"]))
}
@Test(arguments: ["root", "build", "user"])
func changedObservationBoundaryLimitsComparison(boundary: String) {
    let other = diffScope(root: boundary == "root" ? "/Synthetic/Other" : "/Synthetic/LaunchAgents", build: boundary == "build" ? "build-b" : "build-a", user: boundary == "user" ? "shared" : "currentUser")
    let old = snapshot([observed("missing"), observed("same")])
    let current = snapshot([observed("same", value: "b", generation: "g2", scope: other)], generation: "g2", scope: other)
    let diff = SnapshotComparison.compare(previous: old, current: current)
    #expect(diff.notObserved.isEmpty)
    #expect(diff.diagnostics.contains(.scopeChanged))
    #expect(diff.limitedScopes.contains(diffScope()) && diff.limitedScopes.contains(other))
    if boundary != "user" { #expect(diff.changed == [observed("same").record.id]) }
}
@Test func unsupportedUnrelatedProviderDoesNotBlockConfigurationBaseline() {
    let scope = diffScope(), unsupported = diffScope(root: "/Synthetic/Unavailable", provider: "BTM")
    let input = ObservationSnapshot(generation: "g1", records: [observed("one")], coverage: [
        .init(scope: scope, generation: "g1", state: .completeWithinDeclaredScope),
        .init(scope: unsupported, generation: "g1", state: .unsupported)])
    #expect(SnapshotComparison.canUseAsBaseline(snapshot: input, providerIDs: ["launchd.configuration"]))
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: input, providerIDs: ["launchd.configuration", "BTM"]))
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: input, providerIDs: ["missing.provider"]))
}
@Test func mixedGenerationAndIncorrectBindingCannotHideMissingRecords() {
    let old = snapshot([observed("missing"), observed("present")])
    let mixed = snapshot([observed("present", generation: "g1")], generation: "g2")
    let diff = SnapshotComparison.compare(previous: old, current: mixed)
    #expect(diff.notObserved.isEmpty && diff.diagnostics.contains(.invalidGeneration))
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: mixed, providerIDs: ["launchd.configuration"]))
    let wrong = ScopedSnapshotRecord(record: observed("present").record, scope: diffScope(provider: "another.provider"))
    let malformed = snapshot([wrong])
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: malformed, providerIDs: ["launchd.configuration"]))
    #expect(SnapshotComparison.compare(previous: old, current: malformed).notObserved.isEmpty)
}
@Test func duplicateIdentityOrCoverageCannotSupportNegativeObservations() {
    let old = snapshot([observed("missing"), observed("conflict")])
    let duplicate = snapshot([observed("conflict"), observed("conflict", value: "b")])
    let diff = SnapshotComparison.compare(previous: old, current: duplicate)
    #expect(diff.ambiguous == [observed("conflict").record.id] && diff.notObserved.isEmpty)
    let repeated = ObservationSnapshot(generation: "g1", records: [], coverage: old.coverage + old.coverage)
    #expect(SnapshotComparison.compare(previous: old, current: repeated).notObserved.isEmpty)
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: repeated, providerIDs: ["launchd.configuration"]))
}
@Test func retainingCompleteBaselineAvoidsCancelThenReappearanceAsNewObservation() {
    let baseline = snapshot([observed("same")])
    let cancelled = snapshot([], generation: "g2", state: .cancelled)
    let retained = SnapshotComparison.canUseAsBaseline(snapshot: cancelled, providerIDs: ["launchd.configuration"]) ? cancelled : baseline
    let current = snapshot([observed("same", generation: "g3")], generation: "g3")
    #expect(SnapshotComparison.compare(previous: retained, current: current).firstObserved.isEmpty)
}
@Test func comparisonLimitsUnknownGenerationAndLargeInput() {
    let valid = snapshot([observed("same")])
    let reused = snapshot([])
    #expect(SnapshotComparison.compare(previous: valid, current: reused).notObserved.isEmpty)
    let unknown = snapshot([], generation: "unknown")
    #expect(SnapshotComparison.compare(previous: valid, current: unknown).notObserved.isEmpty)
    #expect(!SnapshotComparison.canUseAsBaseline(snapshot: unknown, providerIDs: ["launchd.configuration"]))
    let huge = snapshot(Array(repeating: observed("same"), count: 20001))
    #expect(SnapshotComparison.compare(previous: huge, current: valid).diagnostics.contains(.resourceLimit))
}

@Test func tenThousandRecordComparisonReportsActualObservationCounts() {
    // Only Core SourceRecord/ObservationSnapshot values are accepted here. Neither
    // input nor output has a presence classification, capability, or execution token.
    let previous = snapshot((0..<10000).map { observed("record-\($0)") })
    let current = snapshot((1000..<11000).map {
        observed("record-\($0)", value: $0 < 2000 ? "changed" : "a", generation: "g2")
    }, generation: "g2")
    let started = DispatchTime.now().uptimeNanoseconds
    let difference = SnapshotComparison.compare(previous: previous, current: current)
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    print("Synthetic snapshot comparison: previous=10000 current=10000 elapsedSeconds=\(elapsed) (Core comparison only; not scanning or GUI rendering)")
    #expect(difference.firstObserved == Set((10000..<11000).map { observed("record-\($0)").record.id }))
    #expect(difference.changed == Set((1000..<2000).map { observed("record-\($0)").record.id }))
    #expect(difference.notObserved == Set((0..<1000).map { observed("record-\($0)").record.id }))
    #expect(difference.ambiguous.isEmpty)
    #expect(difference.limitedScopes.isEmpty && difference.diagnostics.isEmpty)
    #expect(elapsed.isFinite && elapsed >= 0)
    // Observe elapsed time without an unreliable machine-specific speed threshold.
}

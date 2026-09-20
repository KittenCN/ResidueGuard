import Foundation
import Testing
import ResidueCore
@testable import ResiduePlatform

private func targetSnapshot(_ observation: DirectTargetObservation, time: Double, hash: String = String(repeating: "a", count: 64), build: String = "26A428", coverage: CoverageState = .completeWithinDeclaredScope, scope: String = "fixture", target: String = "/fixture/tool") -> ScanSnapshot {
    let generation = UUID().uuidString
    let record = SourceRecord(id: .init(providerID: "launchd.configuration", scope: scope, nativeIdentity: "fixture"), category: "launch", observedAt: Date(timeIntervalSince1970: time), generation: generation, sourceArtifact: "/fixture/a.plist", displayName: "fixture", declaredAppIDs: [], targetReferences: [target], rawMetadata: ["contentSHA256": hash], parseWarnings: [])
    return .init(generation: generation, observedAt: record.observedAt,
        rows: [.init(record: record, presence: observation == .executablePresent ? .present : .suspectedOrphan, capability: .init(profileID: "fixture", state: .readOnly, testedOSBuilds: [], reason: "fixture"), evidence: [], directTargetObservation: observation)],
        coverage: [.init(providerID: "launchd.configuration", state: coverage, declaredRoots: ["/fixture"], userScopes: [scope], osBuild: build, generation: generation)])
}
@Test func disappearanceLatchRequiresExactEvidenceAndDoesNotExpire() throws {
    var tracker = RecentTargetDisappearanceTracker()
    #expect(tracker.apply(targetSnapshot(.missing, time: 1)).rows[0].presence == .suspectedOrphan)
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 2))
    #expect(tracker.apply(targetSnapshot(.missing, time: 3)).rows[0].presence == .unknown)
    #expect(tracker.apply(targetSnapshot(.missing, time: 999999)).rows[0].presence == .unknown)
    #expect(tracker.apply(targetSnapshot(.missing, time: 1000000, hash: String(repeating: "b", count: 64))).rows[0].presence == .suspectedOrphan)
    #expect(tracker.apply(targetSnapshot(.missing, time: 1000001, build: "different")).rows[0].presence == .suspectedOrphan)
    #expect(tracker.apply(targetSnapshot(.missing, time: 1000002, scope: "other")).rows[0].presence == .suspectedOrphan)
    #expect(tracker.apply(targetSnapshot(.missing, time: 1000003, target: "/fixture/other")).rows[0].presence == .suspectedOrphan)
    #expect(tracker.apply(targetSnapshot(.missing, time: 1000004)).rows[0].presence == .unknown)
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 1000005))
    #expect(tracker.apply(targetSnapshot(.missing, time: 1000006)).rows[0].presence == .unknown)
}
@Test func incompleteCancelledAndStaleObservationsCannotSeedOrClearHistory() {
    for state in [CoverageState.partial, .cancelled, .permissionDenied, .failed] {
        var tracker = RecentTargetDisappearanceTracker()
        _ = tracker.apply(targetSnapshot(.executablePresent, time: 1, coverage: state))
        #expect(tracker.apply(targetSnapshot(.missing, time: 2)).rows[0].presence == .suspectedOrphan)
    }
    var tracker = RecentTargetDisappearanceTracker()
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 1), cancelled: true)
    #expect(tracker.apply(targetSnapshot(.missing, time: 2)).rows[0].presence == .suspectedOrphan)
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 1)) // stale
    #expect(tracker.apply(targetSnapshot(.missing, time: 3)).rows[0].presence == .suspectedOrphan)
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 4))
    _ = tracker.apply(targetSnapshot(.missing, time: 5))
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 6), cancelled: true)
    #expect(tracker.apply(targetSnapshot(.missing, time: 7)).rows[0].presence == .unknown)
}
@Test func independentCollectorsShareWorkspaceStyleProtectiveHistory() async throws {
    let root = URL(fileURLWithPath: "/private/tmp/ResidueDisappearance-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let program = root.appendingPathComponent("tool")
    try Data("not executed".utf8).write(to: program)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: program.path)
    try PropertyListSerialization.data(fromPropertyList: ["Label": "fixture", "Program": program.path], format: .xml, options: 0).write(to: root.appendingPathComponent("fixture.plist"))
    let configuration = ScanConfiguration(launchRoots: [.init(url: root, scope: "fixture")], applicationRoots: [])
    var tracker = RecentTargetDisappearanceTracker()
    let first = tracker.apply(await ScanService(configuration: configuration).scan())
    #expect(first.rows.count == 1)
    #expect(try #require(first.rows.first).presence == .present)
    try FileManager.default.removeItem(at: program)
    let missing = tracker.apply(await ScanService(configuration: configuration).scan())
    #expect(missing.rows.count == 1)
    #expect(try #require(missing.rows.first).presence == .unknown)
    #expect(missing.rows[0].capability.state == .readOnly)
    try Data("not executed again".utf8).write(to: program)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: program.path)
    let restored = tracker.apply(await ScanService(configuration: configuration).scan())
    #expect(restored.rows.count == 1)
    #expect(try #require(restored.rows.first).presence == .present)
}

@Test func disappearanceHistoryBoundsDoNotEvictLatchedProtection() {
    var tracker = RecentTargetDisappearanceTracker(limit: 1)
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 1))
    _ = tracker.apply(targetSnapshot(.missing, time: 2))
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 3, target: "/fixture/other"))
    #expect(tracker.apply(targetSnapshot(.missing, time: 4, target: "/fixture/other")).rows[0].presence == .suspectedOrphan)
    _ = tracker.apply(targetSnapshot(.unverified, time: 5))
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 6, coverage: .partial))
    #expect(tracker.apply(targetSnapshot(.missing, time: 7)).rows[0].presence == .unknown)
}
@Test func duplicateBoundariesRecordsAndUnknownHashesCannotSeedDisappearance() {
    let valid = targetSnapshot(.executablePresent, time: 1)
    let inputs = [
        ScanSnapshot(generation: valid.generation, observedAt: valid.observedAt, rows: valid.rows, coverage: valid.coverage + valid.coverage),
        ScanSnapshot(generation: valid.generation, observedAt: valid.observedAt, rows: valid.rows + valid.rows, coverage: valid.coverage),
        targetSnapshot(.executablePresent, time: 1, hash: "unknown"),
        targetSnapshot(.executablePresent, time: 1, build: "unverified")
    ]
    for input in inputs {
        var tracker = RecentTargetDisappearanceTracker()
        _ = tracker.apply(input)
        #expect(tracker.apply(targetSnapshot(.missing, time: 2)).rows[0].presence == .suspectedOrphan)
    }
}

@Test func oversizedComparisonCannotExposePreviouslyProtectedSuspectedState() {
    var tracker = RecentTargetDisappearanceTracker()
    _ = tracker.apply(targetSnapshot(.executablePresent, time: 1))
    let missing = targetSnapshot(.missing, time: 2)
    let oversized = ScanSnapshot(generation: missing.generation, observedAt: missing.observedAt,
        rows: missing.rows, coverage: Array(repeating: missing.coverage[0], count: 129))
    #expect(tracker.apply(oversized).rows[0].presence == .unknown)
    #expect(tracker.apply(targetSnapshot(.missing, time: 3)).rows[0].presence == .unknown)
}

import Foundation
import Testing
import ResidueCore
@testable import ResiduePlatform

private func ownershipFixtureRoot() throws -> URL {
    let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("ResidueOwnership-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}
private func writeOwnershipApp(_ path: URL, bundleID: String) throws {
    let contents = path.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
}
@Test func scanOwnershipGraphRetainsMultipleApplicationsWithoutChangingClassification() async throws {
    let root = try ownershipFixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let apps = root.appendingPathComponent("Apps"), agents = root.appendingPathComponent("Agents")
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    try writeOwnershipApp(apps.appendingPathComponent("A.app"), bundleID: "example.owner")
    try writeOwnershipApp(apps.appendingPathComponent("B.app"), bundleID: "example.owner")
    try PropertyListSerialization.data(fromPropertyList: ["Label": "fixture.owner", "Program": root.appendingPathComponent("missing-program").path, "AssociatedBundleIdentifiers": "example.owner"], format: .xml, options: 0)
        .write(to: agents.appendingPathComponent("fixture.plist"))
    let launches = [ScanRoot(url: agents, scope: "fixture")]
    let withoutIndex = await ScanService(configuration: .init(launchRoots: launches, applicationRoots: [])).scan()
    let indexed = await ScanService(configuration: .init(launchRoots: launches, applicationRoots: [apps])).scan()
    #expect(indexed.applications.count == 2)
    #expect(indexed.applications.allSatisfy { $0.generation == indexed.generation })
    #expect(indexed.ownershipGraph.applications.count == 2)
    #expect(indexed.ownershipGraph.edges.count == 2)
    #expect(indexed.ownershipGraph.edges.allSatisfy { $0.reasons == [.declaredBundleIdentifier] })
    #expect(indexed.ownershipGraph.issues.contains { $0.kind == .duplicateBundleIdentifier })
    #expect(indexed.rows.map(\.presence) == withoutIndex.rows.map(\.presence))
    #expect(indexed.rows.map(\.capability) == withoutIndex.rows.map(\.capability))
    #expect(indexed.rows.allSatisfy { $0.presence != .highConfidenceOrphan })
    #expect(indexed.ownershipGraph.isPartial)
    #expect(!indexed.ownershipGraph.ownershipVerified)
}
@Test func scanOwnershipGraphDeduplicatesOverlappingRootsAndKeepsFailedRows() async throws {
    let root = try ownershipFixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
    try writeOwnershipApp(root.appendingPathComponent("A.app"), bundleID: "example.owner")
    try Data("not a plist".utf8).write(to: root.appendingPathComponent("bad.plist"))
    let snapshot = await ScanService(configuration: .init(launchRoots: [.init(url: root, scope: "fixture")], applicationRoots: [root, root])).scan()
    #expect(snapshot.applications.count == 2)
    #expect(snapshot.ownershipGraph.applications.count == 1)
    #expect(snapshot.ownershipGraph.applications[0].observations.count == 2)
    #expect(snapshot.rows.count == 1)
    #expect(snapshot.ownershipGraph.edges.isEmpty)
    #expect(snapshot.ownershipGraph.issues.contains { $0.kind == .unparsedRecord })
    #expect(snapshot.rows[0].presence == .unknown)
}
@Test func scanSnapshotDefaultGraphDoesNotTurnUnknownCoverageIntoCompleteOwnership() {
    let snapshot = ScanSnapshot(generation: "unknown", observedAt: Date(), rows: [], coverage: [])
    #expect(snapshot.ownershipGraph.isPartial)
    #expect(snapshot.ownershipGraph.issues.contains { $0.kind == .unknownGeneration })
    #expect(!snapshot.ownershipGraph.ownershipVerified)
}

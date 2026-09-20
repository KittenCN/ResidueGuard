import Foundation
import Testing
import ResidueCore
@testable import ResiduePlatform

/// Own temporary filesystem observations, not signed-app or VM acceptance.
@Test func indexTracksMovedInstallationAndDoesNotReuseStaleGeneration() async throws {
    let root = URL(fileURLWithPath: "/private/tmp/ResidueIndexMatrix-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("First"), second = root.appendingPathComponent("Second")
    let agents = root.appendingPathComponent("Agents")
    for directory in [first, second, agents] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let original = first.appendingPathComponent("Same.app"), moved = second.appendingPathComponent("Renamed.app")
    try FileManager.default.createDirectory(at: original.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "example.matrix"], format: .xml, options: 0)
        .write(to: original.appendingPathComponent("Contents/Info.plist"))
    try PropertyListSerialization.data(fromPropertyList: ["Label": "example.matrix.service", "AssociatedBundleIdentifiers": "example.matrix", "Program": original.appendingPathComponent("Contents/MacOS/missing").path], format: .xml, options: 0)
        .write(to: agents.appendingPathComponent("fixture.plist"))
    let service = ScanService(configuration: .init(launchRoots: [.init(url: agents, scope: "fixture")], applicationRoots: [first, second]))
    let before = await service.scan()
    try FileManager.default.moveItem(at: original, to: moved)
    let after = await service.scan()
    #expect(before.rows.count == 1 && after.rows.count == 1)
    let beforeRow = try #require(before.rows.first)
    let afterRow = try #require(after.rows.first)
    #expect(beforeRow.presence != .highConfidenceOrphan && beforeRow.capability.state == .readOnly)
    #expect(before.applications.count == 1 && after.applications.count == 1)
    #expect(before.applications.first?.fileIdentity == after.applications.first?.fileIdentity)
    #expect(before.applications.first?.volumeIdentity == after.applications.first?.volumeIdentity)
    #expect(after.applications.first?.path == moved.path)
    #expect(before.generation != after.generation)
    #expect(after.ownershipGraph.edges.count == 1)
    #expect(after.ownershipGraph.edges.first?.reasons == [.declaredBundleIdentifier])
    #expect(afterRow.presence != .highConfidenceOrphan)
    #expect(afterRow.capability.state == .readOnly)

    // Simulate the observation window of an update, without inferring an updater.
    try FileManager.default.moveItem(at: moved, to: root.appendingPathComponent("OutsideIndexedScope.app"))
    let gap = await service.scan()
    #expect(gap.rows.count == 1)
    let gapRow = try #require(gap.rows.first)
    #expect(gap.applications.isEmpty && gap.ownershipGraph.edges.isEmpty)
    #expect(gap.ownershipGraph.isPartial && !gap.ownershipGraph.ownershipVerified)
    #expect(gapRow.presence != .highConfidenceOrphan)
    #expect(gapRow.capability.state == .readOnly)
    #expect(gap.coverage.filter { $0.providerID == "applications.index" }.allSatisfy { $0.state == .partial })
    try FileManager.default.moveItem(at: root.appendingPathComponent("OutsideIndexedScope.app"), to: moved)
    let restored = await service.scan()
    #expect(restored.rows.count == 1)
    let restoredRow = try #require(restored.rows.first)
    #expect(restoredRow.capability.state == .readOnly)
    #expect(restored.applications.count == 1 && restored.ownershipGraph.edges.count == 1)
    #expect(restored.generation != gap.generation)
    #expect(restoredRow.presence != .highConfidenceOrphan)
}

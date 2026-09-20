import Foundation
import Testing
@testable import ResidueCore

private let ownershipDate = Date(timeIntervalSince1970: 1000)
private func installation(_ inode: String, bundle: String = "example.a", volume: String = "vol1", path: String = "/Applications/A.app", generation: String = "g", team: String? = nil, signingIdentifier: String? = nil) -> OwnershipApplicationObservation {
    .init(generation: generation, volumeIdentity: volume, fileIdentity: inode, path: path,
          declaredBundleID: bundle, signingIdentifier: signingIdentifier, signingStatus: "metadataPresentUnverified",
          teamID: team, designatedRequirement: "metadata-not-verified", observedAt: ownershipDate)
}
private func source(_ native: String = "record", ids: [String] = ["example.a"], targets: [String] = [], generation: String = "g", scope: String = "user", warnings: [String] = []) -> SourceRecord {
    .init(id: .init(providerID: "fixture", scope: scope, nativeIdentity: native), category: "launch", observedAt: ownershipDate,
          generation: generation, sourceArtifact: "/Fixture/\(native).plist", displayName: "example.a", declaredAppIDs: ids,
          targetReferences: targets, rawMetadata: [:], parseWarnings: warnings)
}
private func graph(_ records: [SourceRecord], _ applications: [OwnershipApplicationObservation], limits: CandidateOwnershipLimits = .init()) -> CandidateOwnershipGraph {
    CandidateOwnershipGraphBuilder.build(records: records, applications: applications,
        sourceCoverage: [.init(providerID: "fixture", state: .completeWithinDeclaredScope, declaredRoots: ["/Fixture"], generation: "g")],
        generation: "g", limits: limits)
}
@Test func ownershipRetainsDifferentInstallationsAndVolumeQualifiedIdentity() {
    let result = graph([source()], [installation("1"), installation("2", path: "/Other/A.app"), installation("1", volume: "vol2", path: "/Volumes/Fixture/A.app")])
    #expect(result.applications.count == 3)
    #expect(result.edges.count == 3)
    #expect(result.issues.contains { $0.kind == .duplicateBundleIdentifier })
    #expect(!result.ownershipVerified)
    #expect(result.edges.allSatisfy { $0.reasons == [.declaredBundleIdentifier] })
}
@Test func ownershipMergesDuplicateObservationsWithoutLosingAliases() {
    let result = graph([source()], [installation("1"), installation("1"), installation("1", path: "/Alias/A.app")])
    #expect(result.applications.count == 1)
    #expect(result.applications[0].observations.count == 3)
    #expect(result.edges.count == 1)
    #expect(!result.issues.contains { $0.kind == .duplicateBundleIdentifier })
}
@Test func ownershipConflictingPhysicalIdentityDoesNotPickAnArbitraryClaim() {
    let result = graph([source()], [installation("1"), installation("1", bundle: "example.other")])
    #expect(result.applications.count == 1)
    #expect(result.applications[0].observations.count == 2)
    #expect(result.edges.isEmpty)
    #expect(result.issues.contains { $0.kind == .conflictingInstanceObservations })
    #expect(result.isPartial)
}
@Test func ownershipNeverGuessesFromLabelTeamOrUnverifiedRequirement() {
    let result = graph([source(ids: [], targets: [])], [installation("1", team: "SAME", signingIdentifier: "example.a"), installation("2", bundle: "example.b", path: "/Applications/B.app", team: "SAME")])
    #expect(result.edges.isEmpty)
    #expect(result.applications.count == 2)
    #expect(!result.ownershipVerified)
    let declared = graph([source()], [installation("1", team: "SAME", signingIdentifier: "different")])
    #expect(declared.edges.count == 1)
    #expect(declared.edges[0].reasons == [.declaredBundleIdentifier])
    #expect(declared.issues.contains { $0.kind == .differingIdentityHints })
}
@Test func ownershipPathHintsRespectComponentsCaseAndTraversal() {
    let valid = graph([source(ids: [], targets: ["/Applications/A.app/Contents/MacOS/tool"])], [installation("1")])
    #expect(valid.edges.first?.reasons == [.lexicalTargetWithinBundle])
    for path in ["/Applications/A.app.other/tool", "/Applications/a.app/tool", "/Applications/A.app/../Other/tool", "relative/tool", "/Applications/A.app"] {
        #expect(graph([source(ids: [], targets: [path])], [installation("1")]).edges.isEmpty)
    }
}
@Test func ownershipKeepsContradictoryHintsAndPossibleSharedPayloadVisible() {
    let a = installation("1"), b = installation("2", bundle: "example.b", path: "/Applications/B.app")
    let conflict = graph([source(ids: ["example.a"], targets: ["/Applications/B.app/Contents/MacOS/tool"])], [a, b])
    #expect(conflict.edges.count == 2)
    #expect(conflict.issues.contains { $0.kind == .differingIdentityHints })
    let shared = graph([source("first", targets: ["/usr/local/bin/shared"]), source("second", ids: ["example.b"], targets: ["/usr/local/bin/shared"])], [a, b])
    let issue = shared.issues.first { $0.kind == .possibleSharedPayload }
    #expect(issue?.relatedRecordIDs.count == 2)
    #expect(issue?.applicationNodeIDs.count == 2)
    let multipleOwners = graph([source(ids: ["example.a", "example.b"])], [a, b])
    #expect(multipleOwners.issues.contains { $0.kind == .possibleSharedPayload && $0.recordID == source().id })
}
@Test func ownershipRejectsUnknownOrStaleGenerationsAndIdentities() {
    for app in [installation("", generation: "g"), installation("1", generation: "old"), installation("unknown"), installation("1", volume: "unverified")] {
        let result = graph([source()], [app])
        #expect(result.applications.count == 1)
        #expect(result.edges.isEmpty)
        #expect(result.isPartial)
    }
    #expect(graph([source(generation: "old")], [installation("1")]).edges.isEmpty)
    #expect(graph([source(scope: "unknown")], [installation("1")]).edges.isEmpty)
    let unknown = CandidateOwnershipGraphBuilder.build(records: [source(generation: "unknown")], applications: [installation("1", generation: "unknown")], sourceCoverage: [], generation: "unknown")
    #expect(unknown.edges.isEmpty)
    #expect(unknown.isPartial)
}
@Test func ownershipDuplicateRecordOrParseFailureCannotCreateAssociations() {
    #expect(graph([source(), source()], [installation("1")]).edges.isEmpty)
    #expect(graph([source(warnings: ["ambiguousPayload"])], [installation("1")]).edges.isEmpty)
    let scoped = graph([source(scope: "user"), source(scope: "shared")], [installation("1")])
    #expect(scoped.edges.count == 2)
}
@Test func ownershipBoundsEdgesInputsWorkAndDiagnosticsExplicitly() {
    let apps = (0..<30).map { installation(String($0), path: "/Applications/A\($0).app") }
    let limited = graph([source()], apps, limits: .init(maximumEdges: 3))
    #expect(limited.edges.count == 3)
    #expect(limited.isPartial)
    #expect(limited.issues.contains { $0.kind == .inputLimit })
    let work = graph([source()], apps, limits: .init(maximumWork: 2))
    #expect(work.edges.count == 2)
    #expect(work.isPartial)
    let input = graph([source(), source("other")], apps, limits: .init(maximumRecords: 1, maximumApplications: 2, maximumIssues: 1))
    #expect(input.applications.count == 2)
    #expect(input.issues.count == 1)
    #expect(input.isPartial)
}
@Test func ownershipPreservesCoverageGapsAndDoesNotDeclareMissingApplicationsRemoved() {
    let result = CandidateOwnershipGraphBuilder.build(records: [source()], applications: [], sourceCoverage: [.init(providerID: "applications.index", state: .permissionDenied, declaredRoots: [], generation: "g")], generation: "g")
    #expect(result.edges.isEmpty)
    #expect(result.isPartial)
    #expect(result.issues.contains { $0.kind == .insufficientCoverage })
    #expect(!result.ownershipVerified)
}

@Test func ownershipSameDisplayNameAndDifferentSignatureHintsNeverMergeInstallations() {
    let first = installation("one", path: "/First/Same.app", team: "TEAM_A", signingIdentifier: "signed.a")
    let second = installation("two", path: "/Second/Same.app", team: "TEAM_B", signingIdentifier: "signed.b")
    let result = graph([source()], [first, second])
    #expect(result.applications.count == 2 && result.edges.count == 2)
    #expect(result.edges.allSatisfy { $0.reasons == [.declaredBundleIdentifier] })
    #expect(result.issues.contains { $0.kind == .duplicateBundleIdentifier })
    #expect(result.issues.contains { $0.kind == .differingIdentityHints })
    #expect(!result.ownershipVerified)
    // A name or signing hint alone cannot select either installation.
    #expect(graph([source(ids: [])], [first, second]).edges.isEmpty)
}

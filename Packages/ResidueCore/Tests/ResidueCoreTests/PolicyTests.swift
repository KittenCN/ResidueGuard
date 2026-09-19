import Foundation
import Testing
@testable import ResidueCore

@Test func suppliedConfirmationFixtures() throws {
    struct Case: Decodable { let id: String; let expected: ConfirmationRequirement }
    struct Envelope<T: Decodable>: Decodable { let cases: [T] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("fixtures/confirmation-cases.json"))
    let inputs = try JSONDecoder().decode(Envelope<ConfirmationInput>.self, from: data).cases
    let expectations = try JSONDecoder().decode(Envelope<Case>.self, from: data).cases
    #expect(inputs.count == 24)
    for (input, fixture) in zip(inputs, expectations) {
        #expect(ConfirmationPolicy.evaluate(input) == fixture.expected, "Fixture \(fixture.id)")
    }
}
private let now = Date(timeIntervalSince1970: 1_000)
private let capability = CapabilityDescriptor(profileID: "synthetic", state: .supportedVerified, testedOSBuilds: ["synthetic"], reason: "合成测试，不是平台验证", operations: [.removeRegistration: .supportedVerified])
private func snapshot(presence: PresenceState = .highConfidenceOrphan, fingerprint: String = "v1", extra: Bool = false) -> PlanSnapshot {
    let a = ImpactTarget(id: "a", displayName: "合成 A", presence: presence, fingerprint: fingerprint)
    let b = ImpactTarget(id: "b", displayName: "合成 B", presence: .present, fingerprint: "b1")
    let r = PlanningRecord(id: "r", operationKey: "same-object", affectedTargetIDs: ["a"], capability: capability, fingerprint: "r1")
    let r2 = PlanningRecord(id: "r2", operationKey: "same-object", affectedTargetIDs: ["b"], capability: capability, fingerprint: "r1")
    return .init(generation: "g1", osBuild: "synthetic", records: extra ? [r, r2] : [r], targets: extra ? [a, b] : [a], observedAt: now)
}
private func plan(_ s: PlanSnapshot, approved: Bool = true) -> DryRunPlan {
    DryRunPlanner.makePlan(selectedRecordIDs: ["r"], snapshot: s, expandedImpactApproved: approved, now: now)
}
@Test func impactExpansionAndDeduplication() {
    let expanded = plan(snapshot(extra: true))
    #expect(expanded.targets.count == 2)
    #expect(expanded.operationKeys.count == 1)
    #expect(expanded.requirement == .two)
    #expect(plan(snapshot(extra: true), approved: false).requirement == .blocked)
}
@Test func unknownBuildMissingSelectionAndDuplicateIdentityBlock() {
    let s = snapshot()
    #expect(plan(.init(generation: s.generation, osBuild: "new-build", records: s.records, targets: s.targets, observedAt: now)).requirement == .blocked)
    #expect(DryRunPlanner.makePlan(selectedRecordIDs: ["missing"], snapshot: s, expandedImpactApproved: true, now: now).requirement == .blocked)
    #expect(plan(.init(generation: s.generation, osBuild: s.osBuild, records: s.records, targets: s.targets + s.targets, observedAt: now)).requirement == .blocked)
    #expect(plan(snapshot(fingerprint: "")).requirement == .blocked)
}
@Test func independentConfirmationsRejectReplayAndWrongPhrase() throws {
    let p = plan(snapshot(presence: .present))
    var session = ConsentSession(plan: p)
    let eventResult1 = session.presentFirst(now: now, currentDigest: p.digest)
    let first = try #require(eventResult1)
    let eventResult2 = session.confirmFirst(presentation: first, now: now, currentDigest: p.digest)
    #expect(eventResult2)
    let eventResult3 = !session.confirmFirst(presentation: first, now: now, currentDigest: p.digest)
    #expect(eventResult3)
    #expect(session.stage == .firstConfirmed)
    let eventResult4 = session.presentSecond(now: now, currentDigest: p.digest)
    let second = try #require(eventResult4)
    let eventResult5 = !session.confirmSecond(presentation: first, phrase: ConsentSession.riskPhrase, now: now, currentDigest: p.digest)
    #expect(eventResult5)
    let eventResult6 = !session.confirmSecond(presentation: second, phrase: "", now: now, currentDigest: p.digest)
    #expect(eventResult6)
    let eventResult7 = session.confirmSecond(presentation: second, phrase: ConsentSession.riskPhrase, now: now, currentDigest: p.digest)
    #expect(eventResult7)
    #expect(session.stage == .complete)
    let eventResult8 = !session.confirmSecond(presentation: second, phrase: ConsentSession.riskPhrase, now: now, currentDigest: p.digest)
    #expect(eventResult8)
}
@Test func expiryAndFingerprintChangesInvalidate() throws {
    let p = plan(snapshot())
    var expired = ConsentSession(plan: p)
    let eventResult9 = expired.presentFirst(now: p.expiresAt, currentDigest: p.digest) == nil
    #expect(eventResult9)
    #expect(expired.stage == .invalidated)
    var changed = ConsentSession(plan: p)
    let eventResult10 = changed.presentFirst(now: now, currentDigest: p.digest)
    let first = try #require(eventResult10)
    let changedPlan = plan(snapshot(fingerprint: "reinstalled"))
    #expect(changedPlan.digest != p.digest)
    let eventResult11 = !changed.confirmFirst(presentation: first, now: now, currentDigest: changedPlan.digest)
    #expect(eventResult11)
    #expect(changed.stage == .invalidated)
}
@Test func conservativePresence() {
    var e = PresenceEvidence()
    e.identityVerified = true; e.coverageComplete = true; e.allDeclaredTargetsMissing = true; e.evidenceIDs = ["synthetic-proof"]
    #expect(OrphanClassifier.classify(e) != .highConfidenceOrphan)
    e.stableRecheckVerified = true
    #expect(OrphanClassifier.classify(e) == .highConfidenceOrphan)
    e.volumeOnline = false; #expect(OrphanClassifier.classify(e) == .volumeUnavailable)
    e.volumeOnline = true; e.accessDenied = true; #expect(OrphanClassifier.classify(e) == .permissionDenied)
    e.accessDenied = false; e.inTrash = true; #expect(OrphanClassifier.classify(e) == .inTrash)
    e.inTrash = false; e.runtimeActive = true; #expect(OrphanClassifier.classify(e) == .unknown)
    e.runtimeActive = false; e.validStandaloneExecutableExists = true; #expect(OrphanClassifier.classify(e) == .present)
    e.sharedOwnerExists = true; #expect(OrphanClassifier.classify(e) == .sharedComponentActive)
}
@Test func staleSnapshotAndConflictingUnderlyingIdentityBlock() {
    let s = snapshot(extra: true)
    #expect(plan(.init(generation: s.generation, osBuild: s.osBuild, records: s.records, targets: s.targets, observedAt: now.addingTimeInterval(-120))).requirement == .blocked)
    #expect(plan(.init(generation: s.generation, osBuild: s.osBuild, records: s.records, targets: s.targets, observedAt: now.addingTimeInterval(1))).requirement == .blocked)
    let conflict = PlanningRecord(id: "r2", operationKey: "same-object", affectedTargetIDs: ["b"], capability: capability, fingerprint: "different-file")
    #expect(plan(.init(generation: s.generation, osBuild: s.osBuild, records: [s.records[0], conflict], targets: s.targets, observedAt: now)).requirement == .blocked)
}
@Test func exactOperationCapabilityFailsClosed() {
    let s = snapshot()
    for states: [CapabilityOperation: CapabilityState] in [[:], [.removeRegistration: .blockedByPolicy], [.resetPermission: .supportedVerified]] {
        let cap = CapabilityDescriptor(profileID: "synthetic", state: .supportedVerified, testedOSBuilds: ["synthetic"], reason: "fixture", operations: states)
        let record = PlanningRecord(id: "r", operationKey: "same-object", affectedTargetIDs: ["a"], capability: cap, fingerprint: "r1")
        #expect(plan(.init(generation: s.generation, osBuild: s.osBuild, records: [record], targets: s.targets, observedAt: now)).requirement == .blocked)
    }
}
@Test func malformedIdentityAndConflictingActionBlock() {
    let s = snapshot()
    #expect(plan(.init(generation: "", osBuild: s.osBuild, records: s.records, targets: s.targets, observedAt: now)).requirement == .blocked)
    let emptyTarget = ImpactTarget(id: "", displayName: "fixture", presence: .highConfidenceOrphan, fingerprint: "a1")
    let emptyReference = PlanningRecord(id: "r", operationKey: "same-object", affectedTargetIDs: [""], capability: capability, fingerprint: "r1")
    #expect(plan(.init(generation: "g", osBuild: s.osBuild, records: [emptyReference], targets: [emptyTarget], observedAt: now)).requirement == .blocked)
    let emptyRecord = PlanningRecord(id: "", operationKey: "same-object", affectedTargetIDs: ["a"], capability: capability, fingerprint: "r1")
    #expect(DryRunPlanner.makePlan(selectedRecordIDs: [""], snapshot: .init(generation: "g", osBuild: s.osBuild, records: [emptyRecord], targets: s.targets, observedAt: now), expandedImpactApproved: true, now: now).requirement == .blocked)
    let multiCap = CapabilityDescriptor(profileID: "synthetic", state: .supportedVerified, testedOSBuilds: [s.osBuild], reason: "fixture", operations: [.removeRegistration: .supportedVerified, .resetPermission: .supportedVerified])
    let wrongAction = PlanningRecord(id: "r2", operationKey: "same-object", affectedTargetIDs: ["a"], capability: multiCap, fingerprint: "r1", operation: .resetPermission)
    #expect(plan(.init(generation: "g", osBuild: s.osBuild, records: s.records + [wrongAction], targets: s.targets, observedAt: now)).requirement == .blocked)
}

@Test func planCannotExtendSnapshotEvidenceLifetime() {
    let s = snapshot()
    let aging = PlanSnapshot(generation: s.generation, osBuild: s.osBuild, records: s.records, targets: s.targets, observedAt: now.addingTimeInterval(-119))
    #expect(plan(aging).expiresAt == now.addingTimeInterval(1))
}

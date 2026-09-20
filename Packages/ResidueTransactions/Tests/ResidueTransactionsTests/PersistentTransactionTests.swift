import Darwin
import Foundation
import Testing
import ResidueCore
import ResiduePersistence
import ResidueTransactions

private let now = Date(timeIntervalSince1970: 5000)
private func plan() throws -> VerifiedTransactionPlan {
    try .validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID,
        createdAt: now, expiresAt: now.addingTimeInterval(120),
        steps: [.init(id: "stop", targetID: "fixture", action: .bootoutExactService, fingerprint: "fp"),
                .init(id: "isolate", targetID: "fixture", action: .quarantineLaunchConfiguration, fingerprint: "fp", dependencies: ["stop"])],
        targets: [.init(id: "fixture", displayName: "Synthetic", presence: .highConfidenceOrphan, fingerprint: "fp")], impactApproved: true)
}
private func consent(_ plan: VerifiedTransactionPlan, nonce: UUID = UUID()) -> TransactionConsent {
    .init(nonce: nonce, digest: plan.digest, scope: plan.scope, profileID: plan.profileID,
          expiresAt: plan.expiresAt, confirmationEvents: [UUID()])
}
private struct Fixture {
    let directory: URL
    let journal: TransactionJournal
    init() throws {
        directory = URL(fileURLWithPath: "/private/tmp/ResidueTransactionsTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        journal = try TransactionJournal(directory: directory, createNew: true)
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}
private actor Operations: TransactionOperations {
    let journal: TransactionJournal
    let directory: URL
    let fault: String
    var calls: [String] = []
    var validationCount = 0
    init(_ fixture: Fixture, fault: String = "none") { journal = fixture.journal; directory = fixture.directory; self.fault = fault }
    func authorize(plan: VerifiedTransactionPlan) async throws -> Bool {
        let entries = try await journal.unfinishedEntries()
        #expect(entries.count == 1) // Claim must be durable before authorization.
        calls.append("authorize"); return true
    }
    func revalidate(plan: VerifiedTransactionPlan, step: TransactionStep) -> Bool {
        validationCount += 1
        if fault == "prepareIO", validationCount == 3 { chmod(directory.appendingPathComponent("journal.sqlite").path, 0o644) }
        return true
    }
    func prepareBackup(plan: VerifiedTransactionPlan, target: ImpactTarget) -> VerifiedBackup {
        calls.append("backup")
        return .init(targetID: target.id, fingerprint: target.fingerprint, verified: true)
    }
    func perform(plan: VerifiedTransactionPlan, step: TransactionStep) async throws -> StepEffects {
        let entry = try #require(try await journal.unfinishedEntries().first)
        #expect(entry.steps.last?.operationID == step.id)
        #expect(entry.steps.last?.result == nil) // Prepared transaction committed before fake effect.
        #expect(calls.contains("backup"))
        calls.append(step.id)
        if fault == "resultIO" { chmod(directory.appendingPathComponent("journal.sqlite").path, 0o644) }
        if fault == "throws" { throw TransactionFailure.outcomeUnverified }
        if step.action == .quarantineLaunchConfiguration { return .init(file: .succeeded, registration: .pendingSystemRefresh) }
        switch fault {
        case "failed": return .init(runtime: .failed)
        case "unverified": return .init(runtime: .unverified)
        case "missing": return .init()
        case "permission": return .init(runtime: .succeeded, permission: .succeeded)
        case "file": return .init(file: .succeeded, runtime: .succeeded)
        case "registration": return .init(runtime: .succeeded, registration: .unverified)
        default: return .init(runtime: .succeeded, registration: .pendingSystemRefresh)
        }
    }
}

@Test func durableBridgeOrdersStepsAndFinalizesOnlyCompletedReport() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let p = try plan(); let operations = Operations(fixture)
    let driver = PersistentTransactionDriver(journal: fixture.journal, operations: operations)
    let report = await TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { now }).run(plan: p, consent: consent(p))
    #expect(report.completed)
    #expect(try await fixture.journal.unfinishedEntries().first?.steps.map(\.result) == [.succeeded, .succeeded])
    try await driver.finalize(plan: p, report: report)
    #expect(try await fixture.journal.unfinishedEntries().isEmpty)
    #expect(await operations.calls == ["authorize", "backup", "stop", "isolate"])
}

@Test func durableReplayStopsNewCoordinatorAndDriver() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let p = try plan(), receipt = consent(p)
    let first = PersistentTransactionDriver(journal: fixture.journal, operations: Operations(fixture))
    let report = await TransactionCoordinator(driver: first, gate: .syntheticTests, now: { now }).run(plan: p, consent: receipt)
    try await first.finalize(plan: p, report: report)
    let reopened = try TransactionJournal(directory: fixture.directory)
    for (nextPlan, nonce) in [(p, UUID()), (try plan(), receipt.nonce)] {
        let operations = Operations(fixture)
        let driver = PersistentTransactionDriver(journal: reopened, operations: operations)
        let replay = await TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { now }).run(plan: nextPlan, consent: consent(nextPlan, nonce: nonce))
        #expect(replay.failure == .replay)
        #expect(await operations.calls.isEmpty)
    }
}

@Test(arguments: ["failed", "unverified", "missing", "permission", "file", "registration", "throws"])
func invalidEffectsNeverPersistSuccessOrAdvance(fault: String) async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let p = try plan(), operations = Operations(fixture, fault: fault)
    let driver = PersistentTransactionDriver(journal: fixture.journal, operations: operations)
    let report = await TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { now }).run(plan: p, consent: consent(p))
    #expect(!report.completed)
    #expect(!(await operations.calls).contains("isolate"))
    let entry = try #require(try await fixture.journal.unfinishedEntries().first)
    #expect(entry.steps.count == 1)
    #expect(entry.steps[0].result == (fault == "failed" ? .failed : .unverified))
    await #expect(throws: (any Error).self) { try await driver.finalize(plan: p, report: report) }
    await #expect(throws: (any Error).self) { try await driver.journalPrepared(plan: p, step: p.steps[1]) }
}

@Test(arguments: ["claimIO", "prepareIO", "resultIO"])
func storageErrorStopsEffects(fault: String) async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let p = try plan(), operations = Operations(fixture, fault: fault)
    if fault == "claimIO" { chmod(fixture.directory.appendingPathComponent("journal.sqlite").path, 0o644) }
    let driver = PersistentTransactionDriver(journal: fixture.journal, operations: operations)
    let report = await TransactionCoordinator(driver: driver, gate: .syntheticTests, now: { now }).run(plan: p, consent: consent(p))
    #expect(report.failure == .journalFailed)
    #expect(!(await operations.calls).contains("isolate"))
    #expect((await operations.calls).contains("stop") == (fault == "resultIO"))
    chmod(fixture.directory.appendingPathComponent("journal.sqlite").path, 0o600)
    let entry = try await TransactionJournal(directory: fixture.directory).unfinishedEntries().first
    if fault == "resultIO" { #expect(entry?.steps.first?.result == nil); #expect(entry?.steps.count == 1) }
}

@Test func defaultClosedGateDoesNotClaimOrDelegate() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let p = try plan(), operations = Operations(fixture)
    let driver = PersistentTransactionDriver(journal: fixture.journal, operations: operations)
    let report = await TransactionCoordinator(driver: driver, now: { now }).run(plan: p, consent: consent(p))
    #expect(report.failure == .gateClosed)
    #expect(await operations.calls.isEmpty)
    #expect(try await fixture.journal.unfinishedEntries().isEmpty)
}

@Test func bypassingPrepareAndReorderingAreRejected() async throws {
    let fixture = try Fixture(); defer { fixture.clean() }
    let p = try plan(), operations = Operations(fixture)
    let driver = PersistentTransactionDriver(journal: fixture.journal, operations: operations)
    #expect(try await driver.claim(nonce: UUID(), plan: p))
    await #expect(throws: (any Error).self) { _ = try await driver.perform(plan: p, step: p.steps[0]) }
    await #expect(throws: (any Error).self) { try await driver.journalPrepared(plan: p, step: p.steps[1]) }
    #expect(await operations.calls.isEmpty)
}

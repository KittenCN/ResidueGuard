import Foundation
import Darwin
import ResidueBackup
import ResiduePlatform

public enum OwnedFixtureProbePhase: String, Sendable {
    case beforeBackup, beforeIsolation, isolation, afterIsolation, recoveryInspection
    case beforeRestore, restoration, afterRestore, finalInspection
}
public struct OwnedFixtureProbeFailure: Error, Sendable {
    public let phase: OwnedFixtureProbePhase
    public let fileState: MoveState
    public let backupID: UUID?
}

extension QuarantineStore {
    /// Zero-argument, fixed signed ISO01 fixture only. This never changes runtime registration.
    public static func runISO01VirtualMachineProbe() async throws -> String {
        let context = try OwnedFixtureLabContext.createISO01()
        let expected = LaunchRuntimeIdentity(userID: getuid(), label: "example.residueguard.fixture.iso01",
            sourcePath: context.home + "/Library/LaunchAgents/" + context.sourceName,
            program: context.home + "/Library/ResidueGuard-VM-ISO01/fixture")
        let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile))
        let check = {
            let observation = await collector.collect(expected: expected, generation: UUID().uuidString)
            return observation.state == .registeredNotRunning
        }
        guard await check() else {
            throw OwnedFixtureProbeFailure(phase: .beforeBackup, fileState: .notMoved, backupID: nil)
        }
        let receipt = try context.backup.prepare(name: context.sourceName, expected: context.fingerprint, planID: UUID())
        let quarantineFD = try context.makeQuarantineDirectory()
        defer { close(quarantineFD) }
        let store = try QuarantineStore(testSourceFD: context.sourceFD, testQuarantineFD: quarantineFD, backup: context.backup)
        try await runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: check)
        return "PASS ISO01 backup/isolate/inspect/restore verified; runtime=registeredNotRunning; registration=observedRegisteredNotRunning; registrationMutations=none; productionGate=disabled; backupID=\(receipt.id.uuidString)"
    }

    /// Internal test seam. No paths or runtime runner can be injected through the public entry point.
    static func runOwnedFixtureScenario(store: QuarantineStore, receipt: BackupReceipt,
                                        runtimeCheck: () async -> Bool) async throws {
        func failure(_ phase: OwnedFixtureProbePhase, _ state: MoveState) -> OwnedFixtureProbeFailure {
            .init(phase: phase, fileState: state, backupID: receipt.id)
        }
        guard !Task.isCancelled, await runtimeCheck() else { throw failure(.beforeIsolation, .notMoved) }
        let isolation = store.isolate(receipt: receipt, planID: receipt.planID)
        guard isolation.state == .quarantinedVerified else { throw failure(.isolation, isolation.state) }
        guard !Task.isCancelled, await runtimeCheck() else { throw failure(.afterIsolation, .quarantinedVerified) }
        guard store.inspectRecovery(receipt: receipt, planID: receipt.planID).decision == .restoreCandidateRequiresNewPlan else {
            throw failure(.recoveryInspection, .quarantinedVerified)
        }
        // This restoration is the fixture experiment's explicitly planned next step, not error compensation.
        guard !Task.isCancelled, await runtimeCheck() else { throw failure(.beforeRestore, .quarantinedVerified) }
        let restoration = store.restore(receipt: receipt, planID: receipt.planID)
        guard restoration.state == .restoredVerified else {
            // Even a refused restore follows a successful isolation; never label the overall experiment "notMoved".
            throw failure(.restoration, .movedUnverified)
        }
        guard !Task.isCancelled, await runtimeCheck() else { throw failure(.afterRestore, .restoredVerified) }
        guard store.inspectRecovery(receipt: receipt, planID: receipt.planID).decision == .sourcePresentNoMoveRequired else {
            throw failure(.finalInspection, .restoredVerified)
        }
    }
}

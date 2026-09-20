import Foundation
import Darwin
import ResidueBackup
import ResiduePlatform

public enum OwnedFixtureProbePhase: String, Sendable {
    case createContext, backupPreparation, quarantinePreparation
    case beforeBackup, beforeIsolation, isolation, afterIsolation, recoveryInspection
    case beforeRestore, restoration, afterRestore, finalInspection
    case backupEvidenceBeforeIsolation, backupEvidenceAfterRestore
}
public enum OwnedFixtureProbeFailureReason: String, Sendable {
    case guardNotSatisfied, invalidLab, invalidName, unsafeFile, unsupportedMetadata, changed, io, invalidBackup, unknown
}
public struct OwnedFixtureProbeFailure: Error, Sendable {
    public let phase: OwnedFixtureProbePhase
    public let fileState: MoveState
    public let backupID: UUID?
    public let reason: OwnedFixtureProbeFailureReason
    init(phase: OwnedFixtureProbePhase, fileState: MoveState, backupID: UUID?, reason: OwnedFixtureProbeFailureReason = .guardNotSatisfied) {
        self.phase = phase; self.fileState = fileState; self.backupID = backupID; self.reason = reason
    }
}

extension QuarantineStore {
    /// Zero-argument, fixed signed ISO01 fixture only. This never changes runtime registration.
    public static func runISO01VirtualMachineProbe() async throws -> String {
        let context: OwnedFixtureLabContext
        do { context = try OwnedFixtureLabContext.createISO01() }
        catch VMLabProbeError.virtualMachineRequired { throw VMLabProbeError.virtualMachineRequired }
        catch { throw OwnedFixtureProbeFailure(phase: .createContext, fileState: .notMoved, backupID: nil, reason: probeReason(error)) }
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
        let receipt: BackupReceipt
        do { receipt = try context.backup.prepare(name: context.sourceName, expected: context.fingerprint, planID: UUID()) }
        catch { throw OwnedFixtureProbeFailure(phase: .backupPreparation, fileState: .notMoved, backupID: nil, reason: probeReason(error)) }
        let auditBefore: BackupAuditEvidence
        do { auditBefore = try context.backup.inspectAuditEvidence(receipt: receipt) }
        catch { throw OwnedFixtureProbeFailure(phase: .backupEvidenceBeforeIsolation, fileState: .notMoved, backupID: receipt.id, reason: probeReason(error)) }
        let quarantineFD: Int32
        do { quarantineFD = try context.makeQuarantineDirectory() }
        catch { throw OwnedFixtureProbeFailure(phase: .quarantinePreparation, fileState: .notMoved, backupID: receipt.id, reason: probeReason(error)) }
        defer { close(quarantineFD) }
        let store: QuarantineStore
        do { store = try QuarantineStore(testSourceFD: context.sourceFD, testQuarantineFD: quarantineFD, backup: context.backup) }
        catch { throw OwnedFixtureProbeFailure(phase: .quarantinePreparation, fileState: .notMoved, backupID: receipt.id, reason: probeReason(error)) }
        try await runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: check)
        do {
            let auditAfter = try context.backup.inspectAuditEvidence(receipt: receipt)
            guard auditBefore.backupID == auditAfter.backupID, auditBefore.planID == auditAfter.planID,
                  auditBefore.root == auditAfter.root, auditBefore.contentSHA256 == auditAfter.contentSHA256,
                  auditBefore.metadataSHA256 == auditAfter.metadataSHA256,
                  auditBefore.manifestSHA256 == auditAfter.manifestSHA256 else { throw BackupFailure.changed }
        } catch {
            throw OwnedFixtureProbeFailure(phase: .backupEvidenceAfterRestore, fileState: .restoredVerified, backupID: receipt.id, reason: probeReason(error))
        }
        return "PASS ISO01 backup/isolate/inspect/restore verified; backupAuditEvidence=verifiedBeforeAndAfter; persistentAudit=notIntegrated; runtime=registeredNotRunning; registration=observedRegisteredNotRunning; registrationMutations=none; productionGate=disabled; backupID=\(receipt.id.uuidString)"
    }

    private static func probeReason(_ error: any Error) -> OwnedFixtureProbeFailureReason {
        if error is VMLabProbeError { return .invalidLab }
        guard let failure = error as? BackupFailure else { return .unknown }
        switch failure {
        case .invalidName: return .invalidName
        case .unsafeFile: return .unsafeFile
        case .unsupportedMetadata: return .unsupportedMetadata
        case .changed: return .changed
        case .io: return .io
        case .invalidBackup: return .invalidBackup
        }
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

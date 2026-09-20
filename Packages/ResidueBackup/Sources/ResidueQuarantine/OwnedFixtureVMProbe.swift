import Foundation
import Darwin
import ResidueBackup
import ResiduePlatform
import ResiduePersistence

public enum OwnedFixtureProbePhase: String, Sendable {
    case createContext, backupPreparation, quarantinePreparation
    case beforeBackup, beforeIsolation, isolation, afterIsolation, recoveryInspection
    case beforeRestore, restoration, afterRestore, finalInspection
    case backupEvidenceBeforeIsolation, backupEvidenceAfterRestore
    case journalPreparation, journalBeforeIsolation, journalAfterIsolation, journalBeforeRestore, journalAfterRestore
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
        let journal: OwnedFixtureExperimentJournal
        let planCreatedAt = Date()
        let planExpiresAt = planCreatedAt.addingTimeInterval(120)
        do {
            journal = try OwnedFixtureExperimentJournal(directoryFD: context.labFD, createNew: true)
            let plan = try OwnedFixtureExperimentPlan(id: receipt.planID, userID: getuid(), osBuild: "26A428",
                createdAt: planCreatedAt, expiresAt: planExpiresAt, source: auditIdentity(context.fingerprint),
                quarantineRoot: auditDirectory(quarantineFD), sourceRoot: auditDirectory(context.sourceFD),
                program: auditIdentity(context.programFingerprint))
            try await journal.create(plan: plan)
        } catch {
            throw OwnedFixtureProbeFailure(phase: .journalPreparation, fileState: .notMoved, backupID: receipt.id)
        }
        try await runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: check,
            prepareAction: { restoring in
                let currentBackup = try context.backup.inspectAuditEvidence(receipt: receipt)
                try await journal.prepare(planID: receipt.planID, phase: restoring ? .restoration : .isolation,
                    backup: auditBackup(currentBackup))
            }, validateRuntime: check, validateAction: {
                try context.verifyProgram()
                guard Date() <= planExpiresAt else { throw BackupFailure.changed }
            }, recordAction: { restoring, state, known in
                let identity: OwnedFixtureFileIdentity?
                if state == .quarantinedVerified || state == .restoredVerified {
                    identity = auditSnapshot(try store.observeAuditObject(restored: restoring, receipt: receipt))
                } else { identity = nil }
                let effects = OwnedFixtureExperimentEffects(file: auditEffect(state),
                    runtime: known ? .observedRegisteredNotRunning : .unknown,
                    quarantineObject: restoring ? nil : identity, sourceObject: restoring ? identity : nil)
                try await journal.recordResult(planID: receipt.planID, phase: restoring ? .restoration : .isolation, effects: effects)
            })
        let reopened = try OwnedFixtureExperimentJournal(directoryFD: context.labFD, readOnly: true)
        let entries = try await reopened.entries()
        guard entries.count == 1, entries[0].plan.id == receipt.planID,
              entries[0].steps.count == 2,
              entries[0].steps.last?.effects?.file == .restoredVerified,
              entries[0].steps.allSatisfy({ !$0.actionOutcomeUnknown }) else {
            throw OwnedFixtureProbeFailure(phase: .journalAfterRestore, fileState: .restoredVerified, backupID: receipt.id)
        }
        do {
            let auditAfter = try context.backup.inspectAuditEvidence(receipt: receipt)
            guard auditBefore.backupID == auditAfter.backupID, auditBefore.planID == auditAfter.planID,
                  auditBefore.root == auditAfter.root, auditBefore.contentSHA256 == auditAfter.contentSHA256,
                  auditBefore.metadataSHA256 == auditAfter.metadataSHA256,
                  auditBefore.manifestSHA256 == auditAfter.manifestSHA256 else { throw BackupFailure.changed }
        } catch {
            throw OwnedFixtureProbeFailure(phase: .backupEvidenceAfterRestore, fileState: .restoredVerified, backupID: receipt.id, reason: probeReason(error))
        }
        return "PASS ISO01 backup/isolate/inspect/restore verified; backupAuditEvidence=verifiedBeforeAndAfter; persistentAudit=preparedRecordedAndReopened; runtime=registeredNotRunning; registration=observedRegisteredNotRunning; registrationMutations=none; productionGate=disabled; backupID=\(receipt.id.uuidString)"
    }

    private static func auditDirectory(_ fd: Int32) throws -> OwnedFixtureObjectIdentity {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw BackupFailure.unsafeFile }
        return .init(device: value.st_dev, inode: value.st_ino, owner: value.st_uid)
    }
    private static func auditIdentity(_ value: SourceFingerprint) -> OwnedFixtureFileIdentity {
        .init(device: value.device, inode: value.inode, owner: value.owner, group: value.group, mode: value.mode,
              size: value.size, modifiedSeconds: value.modifiedSeconds, modifiedNanos: value.modifiedNanos,
              changedSeconds: value.changedSeconds, changedNanos: value.changedNanos,
              sha256: value.sha256, extendedAttributes: value.extendedAttributes)
    }
    private static func auditSnapshot(_ value: Snapshot) -> OwnedFixtureFileIdentity {
        let info = value.info
        return .init(device: info.st_dev, inode: info.st_ino, owner: info.st_uid, group: info.st_gid, mode: info.st_mode,
              size: info.st_size, modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec),
              changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanos: Int64(info.st_ctimespec.tv_nsec),
              sha256: value.hash, extendedAttributes: value.attributes)
    }
    private static func auditBackup(_ value: BackupAuditEvidence) -> OwnedFixtureBackupEvidence {
        let root = value.root
        return .init(backupID: value.backupID, planID: value.planID,
            root: .init(rootID: root.rootID, directoryName: root.directoryName,
                parentDevice: root.parentDevice, parentInode: root.parentInode,
                device: root.device, inode: root.inode, owner: root.owner),
            contentSHA256: value.contentSHA256, metadataSHA256: value.metadataSHA256,
            manifestSHA256: value.manifestSHA256, observedAt: value.observedAt)
    }
    private static func auditEffect(_ state: MoveState) -> OwnedFixtureFileEffect {
        switch state {
        case .notMoved: .notMoved
        case .movedUnverified: .movedUnverified
        case .quarantinedVerified: .quarantinedVerified
        case .restoredVerified: .restoredVerified
        }
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
                                        runtimeCheck: () async -> Bool,
                                        prepareAction: (Bool) async throws -> Void = { _ in },
                                        validateRuntime: () async -> Bool = { true },
                                        validateAction: () throws -> Void = {},
                                        recordAction: (Bool, MoveState, Bool) async throws -> Void = { _, _, _ in }) async throws {
        func failure(_ phase: OwnedFixtureProbePhase, _ state: MoveState) -> OwnedFixtureProbeFailure {
            .init(phase: phase, fileState: state, backupID: receipt.id)
        }
        guard !Task.isCancelled, await runtimeCheck() else { throw failure(.beforeIsolation, .notMoved) }
        do { try await prepareAction(false) }
        catch { throw failure(.journalBeforeIsolation, .notMoved) }
        guard await validateRuntime(), !Task.isCancelled else { throw failure(.beforeIsolation, .notMoved) }
        do { try validateAction() }
        catch { throw OwnedFixtureProbeFailure(phase: .beforeIsolation, fileState: .notMoved, backupID: receipt.id, reason: probeReason(error)) }
        let isolation = store.isolate(receipt: receipt, planID: receipt.planID)
        let isolationRuntimeKnown = isolation.state == .quarantinedVerified ? await runtimeCheck() : false
        do { try await recordAction(false, isolation.state, isolationRuntimeKnown) }
        catch { throw failure(.journalAfterIsolation, isolation.state) }
        guard isolation.state == .quarantinedVerified else { throw failure(.isolation, isolation.state) }
        guard !Task.isCancelled, isolationRuntimeKnown else { throw failure(.afterIsolation, .quarantinedVerified) }
        guard store.inspectRecovery(receipt: receipt, planID: receipt.planID).decision == .restoreCandidateRequiresNewPlan else {
            throw failure(.recoveryInspection, .quarantinedVerified)
        }
        // This restoration is the fixture experiment's explicitly planned next step, not error compensation.
        guard !Task.isCancelled, await runtimeCheck() else { throw failure(.beforeRestore, .quarantinedVerified) }
        do { try await prepareAction(true) }
        catch { throw failure(.journalBeforeRestore, .quarantinedVerified) }
        guard await validateRuntime(), !Task.isCancelled else { throw failure(.beforeRestore, .quarantinedVerified) }
        do { try validateAction() }
        catch { throw OwnedFixtureProbeFailure(phase: .beforeRestore, fileState: .quarantinedVerified, backupID: receipt.id, reason: probeReason(error)) }
        let restoration = store.restore(receipt: receipt, planID: receipt.planID)
        let restoredState: MoveState = restoration.state == .restoredVerified ? .restoredVerified : .movedUnverified
        let restorationRuntimeKnown = restoration.state == .restoredVerified ? await runtimeCheck() : false
        do { try await recordAction(true, restoredState, restorationRuntimeKnown) }
        catch { throw failure(.journalAfterRestore, restoredState) }
        guard restoration.state == .restoredVerified else {
            // Even a refused restore follows a successful isolation; never label the overall experiment "notMoved".
            throw failure(.restoration, .movedUnverified)
        }
        guard !Task.isCancelled, restorationRuntimeKnown else { throw failure(.afterRestore, .restoredVerified) }
        guard store.inspectRecovery(receipt: receipt, planID: receipt.planID).decision == .sourcePresentNoMoveRequired else {
            throw failure(.finalInspection, .restoredVerified)
        }
    }
}

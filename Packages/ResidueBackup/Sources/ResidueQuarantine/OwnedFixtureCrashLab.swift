#if DEBUG
import Foundation
import Darwin
import ResidueBackup
import ResiduePersistence

package enum OwnedFixtureCrashPhase: String, CaseIterable {
    case afterPrepare, afterIsolateRename, afterIsolationResult, afterRestorePrepare, afterRestoreRename
}
package enum OwnedFixtureCrashLab {
    package static func run(phase: OwnedFixtureCrashPhase, token: UUID) async throws {
        let context = try OwnedFixtureCrashContext.open(token: token, create: true)
        let created = Date(), (backup, receipt) = try context.createFixtureAndBackup()
        let store = try QuarantineStore(testSourceFD: context.sourceFD, testQuarantineFD: context.quarantineFD, backup: backup)
        let journal = try OwnedFixtureExperimentJournal(directoryFD: context.backupFD, createNew: true)
        let file = identity(receipt.fingerprint)
        // Deliberately synthetic history: no fixture execution, runtime observation, or VM authorization.
        let plan = OwnedFixtureExperimentPlan(id: token, userID: getuid(), osBuild: "26A428", createdAt: created,
            expiresAt: created.addingTimeInterval(120), source: file, quarantineRoot: try directory(context.quarantineFD),
            sourceRoot: try directory(context.sourceFD), program: file)
        try await journal.create(plan: plan)
        try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { true }, prepareAction: { restoring in
            let e = try backup.inspectAuditEvidence(receipt: receipt), r = e.root
            let evidence = OwnedFixtureBackupEvidence(backupID: e.backupID, planID: e.planID,
                root: .init(rootID: r.rootID, directoryName: r.directoryName, parentDevice: r.parentDevice,
                    parentInode: r.parentInode, device: r.device, inode: r.inode, owner: r.owner),
                contentSHA256: e.contentSHA256, metadataSHA256: e.metadataSHA256, manifestSHA256: e.manifestSHA256, observedAt: e.observedAt)
            try await journal.prepare(planID: token, phase: restoring ? .restoration : .isolation, backup: evidence)
            if (!restoring && phase == .afterPrepare) || (restoring && phase == .afterRestorePrepare) { try context.checkpoint(phase.rawValue) }
        }, recordAction: { restoring, state, known in
            if (!restoring && phase == .afterIsolateRename) || (restoring && phase == .afterRestoreRename) { try context.checkpoint(phase.rawValue) }
            guard state == (restoring ? .restoredVerified : .quarantinedVerified), known else { throw BackupFailure.changed }
            let object = try store.observeAuditObject(restored: restoring, receipt: receipt)
            let info = object.info
            let file = OwnedFixtureFileIdentity(device: info.st_dev, inode: info.st_ino, owner: info.st_uid, group: info.st_gid,
                mode: info.st_mode, size: info.st_size, modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec),
                changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanos: Int64(info.st_ctimespec.tv_nsec), sha256: object.hash, extendedAttributes: object.attributes)
            try await journal.recordResult(planID: token, phase: restoring ? .restoration : .isolation,
                effects: .init(file: restoring ? .restoredVerified : .quarantinedVerified, runtime: .observedRegisteredNotRunning,
                    quarantineObject: restoring ? nil : file, sourceObject: restoring ? file : nil))
            if !restoring && phase == .afterIsolationResult { try context.checkpoint(phase.rawValue) }
        })
        throw BackupFailure.changed // Every selected phase must have stopped the worker before completion.
    }
    package static func verify(token: UUID) async throws -> String {
        let context = try OwnedFixtureCrashContext.open(token: token, create: false)
        // Never trigger recovery of a hot rollback journal or WAL in this observer.
        for name in ["owned-fixture-experiment.sqlite-journal", "owned-fixture-experiment.sqlite-wal", "owned-fixture-experiment.sqlite-shm"] {
            var value = stat()
            let status = fstatat(context.backupFD, name, &value, AT_SYMLINK_NOFOLLOW)
            guard status == -1 && errno == ENOENT else { throw BackupFailure.invalidBackup }
        }
        let journal = try OwnedFixtureExperimentJournal(directoryFD: context.backupFD, readOnly: true)
        let entries = try await journal.entries()
        guard entries.count == 1, let entry = entries.first, entry.plan.id == token,
              let last = entry.steps.last else { throw BackupFailure.invalidBackup }
        let source = try QuarantineStore.inspectAuditFile(directoryFD: context.sourceFD, name: entry.plan.sourceName, privateDirectory: false)
        let isolated = try QuarantineStore.inspectAuditFile(directoryFD: context.quarantineFD, name: last.backup.backupID.uuidString + ".plist", privateDirectory: true)
        func observation(_ value: QuarantineStore.Snapshot?) -> String {
            guard let value else { return "absent" }
            let expected = entry.plan.source, info = value.info
            // Rename legitimately changes ctime; all other captured identity/content/metadata must match.
            let matches = value.hash == expected.sha256 && info.st_ino == expected.inode && info.st_dev == expected.device
                && info.st_uid == expected.owner && info.st_gid == expected.group && info.st_mode == expected.mode
                && info.st_size == expected.size && Int64(info.st_mtimespec.tv_sec) == expected.modifiedSeconds
                && Int64(info.st_mtimespec.tv_nsec) == expected.modifiedNanos && value.attributes == expected.extendedAttributes
            return matches ? "matches" : "conflict"
        }
        let object: [String: Any] = ["syntheticRuntimeAndBuild": true, "authorizesMutation": false, "automaticRecovery": false,
            "stepCount": entry.steps.count, "lastPhase": last.phase.rawValue, "pending": last.actionOutcomeUnknown,
            "source": observation(source), "quarantine": observation(isolated), "lastEffect": last.effects?.file.rawValue ?? "none"]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
    private static func directory(_ fd: Int32) throws -> OwnedFixtureObjectIdentity {
        var s = stat(); guard fstat(fd, &s) == 0 else { throw BackupFailure.io }
        return .init(device: s.st_dev, inode: s.st_ino, owner: s.st_uid)
    }
    private static func identity(_ f: SourceFingerprint) -> OwnedFixtureFileIdentity {
        .init(device: f.device, inode: f.inode, owner: f.owner, group: f.group, mode: f.mode, size: f.size,
            modifiedSeconds: f.modifiedSeconds, modifiedNanos: f.modifiedNanos, changedSeconds: f.changedSeconds,
            changedNanos: f.changedNanos, sha256: f.sha256, extendedAttributes: f.extendedAttributes)
    }
}
#endif

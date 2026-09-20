import XCTest
import Darwin
import ResiduePersistence
@testable import ResidueBackup
@testable import ResidueQuarantine

final class OwnedFixtureJournalIntegrationTests: XCTestCase {
    struct Fixture {
        let store: QuarantineStore
        let backupStore: VerifiedBackup
        let receipt: BackupReceipt
        let journal: OwnedFixtureExperimentJournal
        let journalFD: Int32
        let source: URL
        let isolated: URL
        func backupEvidence() throws -> OwnedFixtureBackupEvidence {
            let value = try backupStore.inspectAuditEvidence(receipt: receipt), root = value.root
            // This is an explicit temporary-fixture historical mapping, not an owned-VM authorization.
            return .init(backupID: value.backupID, planID: value.planID,
                root: .init(rootID: root.rootID, directoryName: root.directoryName, parentDevice: root.parentDevice,
                    parentInode: root.parentInode, device: root.device, inode: root.inode, owner: root.owner),
                contentSHA256: value.contentSHA256, metadataSHA256: value.metadataSHA256,
                manifestSHA256: value.manifestSHA256, observedAt: value.observedAt)
        }
        func prepare(_ restoring: Bool) async throws {
            try await journal.prepare(planID: receipt.planID, phase: restoring ? .restoration : .isolation, backup: backupEvidence())
        }
        func record(_ restoring: Bool, _ state: MoveState, _ known: Bool) async throws {
            let snapshot = try store.observeAuditObject(restored: restoring, receipt: receipt)
            let s = snapshot.info
            let object = OwnedFixtureFileIdentity(device: s.st_dev, inode: s.st_ino, owner: s.st_uid, group: s.st_gid,
                mode: s.st_mode, size: s.st_size, modifiedSeconds: Int64(s.st_mtimespec.tv_sec), modifiedNanos: Int64(s.st_mtimespec.tv_nsec),
                changedSeconds: Int64(s.st_ctimespec.tv_sec), changedNanos: Int64(s.st_ctimespec.tv_nsec), sha256: snapshot.hash, extendedAttributes: snapshot.attributes)
            XCTAssertEqual(state, restoring ? .restoredVerified : .quarantinedVerified)
            try await journal.recordResult(planID: receipt.planID, phase: restoring ? .restoration : .isolation,
                effects: .init(file: restoring ? .restoredVerified : .quarantinedVerified,
                    runtime: known ? .observedRegisteredNotRunning : .unknown,
                    quarantineObject: restoring ? nil : object, sourceObject: restoring ? object : nil))
        }
        func inspect() async throws -> OwnedFixtureAuditSummary {
            let entry = try await reopen()
            let rootID = try XCTUnwrap(entry.steps.first?.backup.root.rootID)
            let fd = open(source.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard fd >= 0 else { throw BackupFailure.io }; defer { close(fd) }
            return try QuarantineStore.inspectHistoricalEntry(entry, rootID: rootID, rootFD: journalFD, sourceFD: fd)
        }
        func reopen() async throws -> OwnedFixtureExperimentEntry {
            let readOnly = try OwnedFixtureExperimentJournal(directoryFD: journalFD, readOnly: true)
            let entries = try await readOnly.entries()
            XCTAssertEqual(entries.count, 1)
            let entry = try XCTUnwrap(entries.first)
            XCTAssertFalse(entry.authorizesMutation)
            return entry
        }
    }
    private func fixture(_ body: (Fixture) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootID = UUID(), created = Date()
        let source = root.appendingPathComponent("source")
        let backup = root.appendingPathComponent("ResidueGuard-VM-VerifiedBackup-" + rootID.uuidString)
        let quarantine = backup.appendingPathComponent("quarantine")
        for url in [source, backup, quarantine] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let a = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), b = open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        let c = open(quarantine.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), p = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        defer { close(a); close(b); close(c); close(p) }
        let name = "example.residueguard.fixture.iso01.plist", original = source.appendingPathComponent(name)
        XCTAssertTrue(FileManager.default.createFile(atPath: original.path, contents: Data("<plist><dict/></plist>".utf8), attributes: [.posixPermissions: 0o600]))
        let backupStore = try VerifiedBackup(testSourceFD: a, testDestinationFD: b)
        try backupStore.bindAuditRootForTesting(parentFD: p, name: backup.lastPathComponent, id: rootID)
        let receipt = try backupStore.prepare(name: name, expected: backupStore.inspect(name: name), planID: UUID())
        let f = receipt.fingerprint
        let identity = OwnedFixtureFileIdentity(device: f.device, inode: f.inode, owner: f.owner, group: f.group, mode: f.mode, size: f.size,
            modifiedSeconds: f.modifiedSeconds, modifiedNanos: f.modifiedNanos, changedSeconds: f.changedSeconds,
            changedNanos: f.changedNanos, sha256: f.sha256, extendedAttributes: f.extendedAttributes)
        func directory(_ fd: Int32) throws -> OwnedFixtureObjectIdentity {
            var value = stat(); guard fstat(fd, &value) == 0 else { throw BackupFailure.io }
            return .init(device: value.st_dev, inode: value.st_ino, owner: value.st_uid)
        }
        let journal = try OwnedFixtureExperimentJournal(directoryFD: b, createNew: true)
        // Build/program/runtime are synthetic historical test inputs, never VM integration evidence.
        let plan = OwnedFixtureExperimentPlan(id: receipt.planID, userID: getuid(), osBuild: "26A428", createdAt: created,
            expiresAt: created.addingTimeInterval(120), source: identity, quarantineRoot: try directory(c),
            sourceRoot: try directory(a), program: identity)
        try await journal.create(plan: plan)
        let store = try QuarantineStore(testSourceFD: a, testQuarantineFD: c, backup: backupStore)
        try await body(Fixture(store: store, backupStore: backupStore, receipt: receipt, journal: journal, journalFD: b,
            source: original, isolated: quarantine.appendingPathComponent(receipt.id.uuidString + ".plist")))
    }
    func testRealRoundTripReopensTwoRecordedStepsReadOnly() async throws { try await fixture { f in
        try await QuarantineStore.runOwnedFixtureScenario(store: f.store, receipt: f.receipt, runtimeCheck: { true }, prepareAction: f.prepare, recordAction: f.record)
        let entry = try await f.reopen()
        XCTAssertEqual(entry.steps.count, 2)
        XCTAssertEqual(entry.steps.map(\.phase), [.isolation, .restoration])
        XCTAssertEqual(entry.steps.map { $0.effects?.file }, [.quarantinedVerified, .restoredVerified])
        XCTAssertTrue(entry.steps.allSatisfy { !$0.actionOutcomeUnknown })
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.isolated.path))
        let readOnly = try OwnedFixtureExperimentJournal(directoryFD: f.journalFD, readOnly: true)
        do { try await readOnly.create(plan: entry.plan); XCTFail("read-only journal must reject mutation") } catch {}
    } }
    func testResultWriteFailureLeavesPendingIsolationWithoutRestore() async throws { try await fixture { f in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: f.store, receipt: f.receipt, runtimeCheck: { true },
                prepareAction: f.prepare, recordAction: { _, _, _ in throw CocoaError(.fileWriteUnknown) })
            XCTFail("result write failure must stop")
        } catch let error as OwnedFixtureProbeFailure { XCTAssertEqual(error.phase, .journalAfterIsolation) }
        let entry = try await f.reopen()
        XCTAssertEqual(entry.steps.count, 1); XCTAssertTrue(entry.steps[0].actionOutcomeUnknown)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.isolated.path))
    } }
    func testCancellationAfterPrepareLeavesPendingWithoutMovingSource() async throws { try await fixture { f in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: f.store, receipt: f.receipt, runtimeCheck: { true }, prepareAction: { restoring in
                try await f.prepare(restoring)
                withUnsafeCurrentTask { $0?.cancel() }
            }, recordAction: f.record)
            XCTFail("cancellation must stop")
        } catch let error as OwnedFixtureProbeFailure { XCTAssertEqual(error.phase, .beforeIsolation) }
        let entry = try await f.reopen()
        XCTAssertEqual(entry.steps.count, 1); XCTAssertTrue(entry.steps[0].actionOutcomeUnknown)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.isolated.path))
    } }
    func testRestorePrepareFailureKeepsVerifiedIsolation() async throws { try await fixture { f in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: f.store, receipt: f.receipt, runtimeCheck: { true }, prepareAction: { restoring in
                if restoring { throw CocoaError(.fileWriteUnknown) }
                try await f.prepare(restoring)
            }, recordAction: f.record)
            XCTFail("restore prepare failure must stop")
        } catch let error as OwnedFixtureProbeFailure { XCTAssertEqual(error.phase, .journalBeforeRestore) }
        let entry = try await f.reopen()
        XCTAssertEqual(entry.steps.count, 1); XCTAssertFalse(entry.steps[0].actionOutcomeUnknown)
        XCTAssertEqual(entry.steps[0].effects?.file, .quarantinedVerified)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.isolated.path))
    } }
    func testIndependentReadOnlyObservationMatchesRestoredHistory() async throws { try await fixture { f in
        try await QuarantineStore.runOwnedFixtureScenario(store: f.store, receipt: f.receipt, runtimeCheck: { true }, prepareAction: f.prepare, recordAction: f.record)
        let result = try await f.inspect()
        XCTAssertEqual(result.source, "matchesHistory"); XCTAssertEqual(result.quarantined, "absent")
        XCTAssertFalse(result.pendingStep); XCTAssertFalse(result.authorizesMutation)
        XCTAssertFalse(result.backupFreshlyVerified); XCTAssertFalse(result.runtimeInspected)
    } }
    func testIndependentPendingInspectionDoesNotRecover() async throws { try await fixture { f in
        try await f.prepare(false)
        XCTAssertEqual(f.store.isolate(receipt: f.receipt, planID: f.receipt.planID).state, .quarantinedVerified)
        let result = try await f.inspect()
        XCTAssertTrue(result.pendingStep); XCTAssertEqual(result.recordedSteps, 0)
        XCTAssertEqual(result.source, "absent"); XCTAssertEqual(result.quarantined, "matchesHistory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.isolated.path))
    } }
    func testIndependentInspectionPreservesConflictingNewSource() async throws { try await fixture { f in
        try await QuarantineStore.runOwnedFixtureScenario(store: f.store, receipt: f.receipt, runtimeCheck: { true }, prepareAction: f.prepare, recordAction: f.record)
        let replacement = Data("new own temporary source".utf8)
        try replacement.write(to: f.source, options: .atomic)
        let result = try await f.inspect()
        XCTAssertEqual(result.source, "conflict")
        XCTAssertEqual(try Data(contentsOf: f.source), replacement)
    } }

}

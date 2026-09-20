import XCTest
import Darwin
@testable import ResidueBackup
@testable import ResidueQuarantine

final class OwnedFixtureScenarioTests: XCTestCase {
    private func fixture(_ body: (QuarantineStore, BackupReceipt, URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), backup = root.appendingPathComponent("backup"), quarantine = root.appendingPathComponent("quarantine")
        for url in [source, backup, quarantine] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let a = open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), b = open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW), c = open(quarantine.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        defer { close(a); close(b); close(c) }
        let original = source.appendingPathComponent("fixture.plist")
        XCTAssertTrue(FileManager.default.createFile(atPath: original.path, contents: Data("<plist><dict/></plist>".utf8), attributes: [.posixPermissions: 0o600]))
        let backupStore = try VerifiedBackup(testSourceFD: a, testDestinationFD: b)
        let receipt = try backupStore.prepare(name: "fixture.plist", expected: backupStore.inspect(name: "fixture.plist"), planID: UUID())
        let store = try QuarantineStore(testSourceFD: a, testQuarantineFD: c, backup: backupStore)
        try await body(store, receipt, original, quarantine.appendingPathComponent(receipt.id.uuidString + ".plist"))
    }
    func testPlannedRoundTripChecksEveryBoundary() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
            observations += 1; return true
        })
        XCTAssertEqual(observations, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.path))
        XCTAssertEqual(store.inspectRecovery(receipt: receipt, planID: receipt.planID).decision, .sourcePresentNoMoveRequired)
    } }
    func testRuntimeUnknownBeforeIsolationLeavesOriginal() async throws { try await fixture { store, receipt, original, isolated in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { false })
            XCTFail("unknown runtime must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .beforeIsolation); XCTAssertEqual(error.fileState, .notMoved)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testRuntimeUnknownAfterIsolationNeverCompensates() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                observations += 1; return observations == 1
            }); XCTFail("unknown runtime must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .afterIsolation); XCTAssertEqual(error.fileState, .quarantinedVerified)
            XCTAssertEqual(error.backupID, receipt.id)
        }
        XCTAssertEqual(observations, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testRuntimeUnknownBeforeRestoreNeverCompensates() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                observations += 1; return observations < 3
            }); XCTFail("unknown runtime must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .beforeRestore); XCTAssertEqual(error.fileState, .quarantinedVerified)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testRuntimeUnknownAfterRestoreReportsActualFileState() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                observations += 1; return observations < 4
            }); XCTFail("unknown runtime must not report PASS")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .afterRestore); XCTAssertEqual(error.fileState, .restoredVerified)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testIsolationUnverifiedStopsBeforeFurtherObservation() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        store.afterRenameForTesting = { throw CocoaError(.fileWriteUnknown) }
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                observations += 1; return true
            }); XCTFail("unverified move must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .isolation); XCTAssertEqual(error.fileState, .movedUnverified)
        }
        XCTAssertEqual(observations, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testNewSourceConflictStopsAtReadOnlyInspection() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                observations += 1
                if observations == 2 {
                    do { try Data("new source".utf8).write(to: original) }
                    catch { XCTFail("unable to create competing fixture"); return false }
                }
                return true
            }); XCTFail("new source cannot be overwritten")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .recoveryInspection)
        }
        XCTAssertEqual(try Data(contentsOf: original), Data("new source".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testRestoreConflictDoesNotClaimOverallNotMoved() async throws { try await fixture { store, receipt, original, isolated in
        var observations = 0
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                observations += 1
                if observations == 3 {
                    do { try Data("concurrent new source".utf8).write(to: original) }
                    catch { XCTFail("unable to create competing fixture"); return false }
                }
                return true
            }); XCTFail("restore conflict must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .restoration); XCTAssertEqual(error.fileState, .movedUnverified)
        }
        XCTAssertEqual(try Data(contentsOf: original), Data("concurrent new source".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }

    func testDurablePrepareFailurePreventsSourceMutation() async throws { try await fixture { store, receipt, original, isolated in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { true },
                prepareAction: { _ in throw CocoaError(.fileWriteUnknown) })
            XCTFail("prepare failure must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .journalBeforeIsolation)
            XCTAssertEqual(error.fileState, .notMoved)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testResultWriteFailureNeverCompensatesOrRestores() async throws { try await fixture { store, receipt, original, isolated in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { true },
                recordAction: { restoring, state, known in
                    XCTAssertFalse(restoring); XCTAssertEqual(state, .quarantinedVerified); XCTAssertTrue(known)
                    throw CocoaError(.fileWriteUnknown)
                })
            XCTFail("result failure must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .journalAfterIsolation)
            XCTAssertEqual(error.fileState, .quarantinedVerified)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testAuditOrderSurroundsActualMoves() async throws { try await fixture { store, receipt, original, isolated in
        var events: [String] = []
        try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { true },
            prepareAction: { restoring in
                events.append(restoring ? "prepareRestore" : "prepareIsolate")
                XCTAssertEqual(FileManager.default.fileExists(atPath: original.path), !restoring)
                XCTAssertEqual(FileManager.default.fileExists(atPath: isolated.path), restoring)
            }, recordAction: { restoring, state, known in
                events.append(restoring ? "resultRestore" : "resultIsolate")
                XCTAssertTrue(known)
                XCTAssertEqual(state, restoring ? .restoredVerified : .quarantinedVerified)
                XCTAssertEqual(FileManager.default.fileExists(atPath: original.path), restoring)
            })
        XCTAssertEqual(events, ["prepareIsolate", "resultIsolate", "prepareRestore", "resultRestore"])
    } }
    func testUnknownRuntimeIsRecordedAfterMoveBeforeStopping() async throws { try await fixture { store, receipt, original, isolated in
        var count = 0
        var recorded = false
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: {
                count += 1; return count == 1
            }, recordAction: { restoring, state, known in
                recorded = true; XCTAssertFalse(restoring); XCTAssertFalse(known)
                XCTAssertEqual(state, .quarantinedVerified)
            })
            XCTFail("unknown observation must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .afterIsolation)
        }
        XCTAssertTrue(recorded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.path))
    } }

    func testFinalSynchronousIdentityCheckFollowsLastRuntimeAwait() async throws { try await fixture { store, receipt, original, isolated in
        var events: [String] = []
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { true },
                prepareAction: { _ in events.append("prepared") },
                validateRuntime: { events.append("lastRuntime"); return true },
                validateAction: { events.append("identity"); throw BackupFailure.changed })
            XCTFail("changed program must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .beforeIsolation); XCTAssertEqual(error.reason, .changed)
        }
        XCTAssertEqual(events, ["prepared", "lastRuntime", "identity"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.path))
    } }
    func testFreshRuntimeFailureIsNotReportedAsJournalFailure() async throws { try await fixture { store, receipt, original, isolated in
        do {
            try await QuarantineStore.runOwnedFixtureScenario(store: store, receipt: receipt, runtimeCheck: { true }, validateRuntime: { false })
            XCTFail("fresh runtime unknown must stop")
        } catch let error as OwnedFixtureProbeFailure {
            XCTAssertEqual(error.phase, .beforeIsolation); XCTAssertEqual(error.fileState, .notMoved)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: isolated.path))
    } }

}

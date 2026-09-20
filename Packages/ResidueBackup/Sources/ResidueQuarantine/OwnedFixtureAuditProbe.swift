import Foundation
import Darwin
import ResidueBackup
import ResiduePersistence

public struct OwnedFixtureAuditSummary: Encodable, Sendable {
    public let planID: UUID
    public let pendingStep: Bool
    public let recordedSteps: Int
    public let source: String
    public let quarantined: String
    public let authorizesMutation = false
    public let backupFreshlyVerified = false
    public let runtimeInspected = false
}
public struct OwnedFixtureAuditReport: Encodable, Sendable {
    public let coverage: String
    public let refusedRoots: Int
    public let journalsAbsent: Int
    public let failedJournals: Int
    public let experiments: [OwnedFixtureAuditSummary]
    public let inspectionOnly = true
    public let mutationAvailable = false
}
extension QuarantineStore {
    /// Independent zero-input VM reader. Historical observations never become trusted receipts.
    public static func inspectISO01VirtualMachineExperiments() async throws -> OwnedFixtureAuditReport {
        let enumeration = try OwnedFixtureAuditLabReader.read()
        guard let sourceAnchor = enumeration.source else { throw BackupFailure.unsafeFile }
        var results: [OwnedFixtureAuditSummary] = [], absent = 0, failed = 0
        var coverage = enumeration.coverage.rawValue
        for anchor in enumeration.labs {
            do {
                let journal: OwnedFixtureExperimentJournal? = try anchor.withDirectoryFD { fd in
                    var info = stat()
                    if fstatat(fd, "owned-fixture-experiment.sqlite", &info, AT_SYMLINK_NOFOLLOW) != 0 {
                        guard errno == ENOENT else { throw BackupFailure.io }
                        return nil
                    }
                    return try OwnedFixtureExperimentJournal(directoryFD: fd, readOnly: true)
                }
                guard let journal else { absent += 1; continue }
                let entries = try await journal.entries()
                try anchor.revalidate()
                guard results.count + entries.count <= 128 else { coverage = "experimentRecordLimit"; break }
                var batch: [OwnedFixtureAuditSummary] = []
                for entry in entries {
                    let summary = try anchor.withDirectoryFD { root in
                        try sourceAnchor.withSourceDirectoryFD { sourceFD in
                            try inspectHistoricalEntry(entry, rootID: anchor.rootID, rootFD: root, sourceFD: sourceFD)
                        }
                    }
                    batch.append(summary)
                }
                try anchor.revalidate(); try sourceAnchor.revalidate()
                results.append(contentsOf: batch)
                if batch.contains(where: { $0.source == "unverified" || $0.quarantined == "unverified" }) { coverage = "partial" }
            } catch { failed += 1 }
        }
        if enumeration.refusedRootCount > 0 || failed > 0 { coverage = "partial" }
        return .init(coverage: coverage, refusedRoots: enumeration.refusedRootCount,
                     journalsAbsent: absent, failedJournals: failed, experiments: results)
    }
    static func inspectHistoricalEntry(_ entry: OwnedFixtureExperimentEntry, rootID: UUID,
                                      rootFD: Int32, sourceFD: Int32) throws -> OwnedFixtureAuditSummary {
        func directory(_ fd: Int32, matches expected: OwnedFixtureObjectIdentity) throws {
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_dev == expected.device, info.st_ino == expected.inode, info.st_uid == expected.owner else {
                throw BackupFailure.changed
            }
        }
        try directory(sourceFD, matches: entry.plan.sourceRoot)
        let quarantine = openat(rootFD, "quarantine", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard quarantine >= 0 else { throw BackupFailure.unsafeFile }
        defer { close(quarantine) }
        try directory(quarantine, matches: entry.plan.quarantineRoot)
        if let backup = entry.steps.last?.backup {
            guard backup.root.rootID == rootID else { throw BackupFailure.changed }
            try directory(rootFD, matches: .init(device: backup.root.device, inode: backup.root.inode, owner: backup.root.owner))
        }
        let sourceState = historicalObject(directoryFD: sourceFD, name: entry.plan.sourceName,
            privateDirectory: false, expected: entry.plan.source)
        let isolatedState: String
        if let backup = entry.steps.last?.backup {
            isolatedState = historicalObject(directoryFD: quarantine, name: backup.backupID.uuidString + ".plist",
                privateDirectory: true, expected: entry.plan.source)
        } else { isolatedState = "notRecorded" }
        return .init(planID: entry.plan.id, pendingStep: entry.steps.contains(where: \.actionOutcomeUnknown),
            recordedSteps: entry.steps.filter { $0.effects != nil }.count, source: sourceState, quarantined: isolatedState)
    }
    private static func historicalObject(directoryFD: Int32, name: String, privateDirectory: Bool,
                                         expected: OwnedFixtureFileIdentity) -> String {
        do {
            guard let observed = try inspectAuditFile(directoryFD: directoryFD, name: name, privateDirectory: privateDirectory) else { return "absent" }
            let s = observed.info
            // A rename can change ctime; this is historical comparison, never authorization.
            return s.st_dev == expected.device && s.st_ino == expected.inode && s.st_uid == expected.owner &&
                s.st_gid == expected.group && s.st_mode == expected.mode && s.st_size == expected.size &&
                Int64(s.st_mtimespec.tv_sec) == expected.modifiedSeconds && Int64(s.st_mtimespec.tv_nsec) == expected.modifiedNanos &&
                observed.hash == expected.sha256 && observed.attributes == expected.extendedAttributes ? "matchesHistory" : "conflict"
        } catch { return "unverified" }
    }
}

#if DEBUG
import Darwin
import Foundation
import CryptoKit
@testable import ResiduePersistence

enum OwnedExperimentCrashProbe {
    static func run(_ args: [String]) async throws {
        guard args.count == 4, ["writer", "verify"].contains(args[1]),
              ["owned-created", "owned-prepared", "owned-result", "owned-prepare-beforecommit", "owned-result-beforecommit"].contains(args[2]) else { exit(64) }
        let directory = URL(fileURLWithPath: args[3])
        guard directory.deletingLastPathComponent().path == "/private/tmp",
              directory.lastPathComponent.hasPrefix("ResidueJournalCrashTests-") else { exit(64) }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW); guard fd >= 0 else { exit(65) }; defer { close(fd) }
        let stage = args[2]
        if args[1] == "verify", stage.contains("beforecommit") {
            let rollbackURL = directory.appendingPathComponent("owned-fixture-experiment.sqlite-journal")
            let before = try Data(contentsOf: rollbackURL)
            do {
                let readonly = try OwnedFixtureExperimentJournal(directoryFD: fd, readOnly: true)
                _ = try await readonly.entries()
                exit(69)
            } catch { }
            guard try Data(contentsOf: rollbackURL) == before else { exit(69) }
        }
        let journal = try OwnedFixtureExperimentJournal(directoryFD: fd, createNew: args[1] == "writer")
        if args[1] == "verify" {
            let entries = try await journal.entries()
            guard entries.count == 1 else { exit(65) }
            let steps = entries[0].steps
            if ["owned-created", "owned-prepare-beforecommit"].contains(stage) { guard steps.isEmpty else { exit(65) } }
            else {
                guard steps.count == 1, steps[0].phase == .isolation,
                      steps[0].effects?.file == (stage == "owned-result" ? .quarantinedVerified : nil) else { exit(65) }
            }
            guard !entries[0].authorizesMutation else { exit(65) }
            guard try await journal.entries() == entries else { exit(65) }
            return
        }
        let date = Date(timeIntervalSince1970: 1000)
        let file = OwnedFixtureFileIdentity(device: 1, inode: 2, owner: geteuid(), group: getegid(), mode: 0o100600, size: 10,
            modifiedSeconds: 1, modifiedNanos: 0, changedSeconds: 1, changedNanos: 0, sha256: String(repeating: "a", count: 64), extendedAttributes: [:])
        let plan = OwnedFixtureExperimentPlan(id: UUID(), userID: geteuid(), osBuild: "26A428", createdAt: date, expiresAt: date.addingTimeInterval(120),
            source: file, quarantineRoot: .init(device: 1, inode: 3, owner: geteuid()), sourceRoot: .init(device: 1, inode: 4, owner: geteuid()), program: file)
        let metadataEncoder = JSONEncoder(); metadataEncoder.outputFormatting = [.sortedKeys]
        let metadataDigest = SHA256.hash(data: try metadataEncoder.encode(file)).map { String(format: "%02x", $0) }.joined()
        let rootID = UUID()
        let backup = OwnedFixtureBackupEvidence(backupID: UUID(), planID: plan.id,
            root: .init(rootID: rootID, directoryName: "ResidueGuard-VM-VerifiedBackup-" + rootID.uuidString, parentDevice: 1, parentInode: 5, device: 1, inode: 6, owner: geteuid()),
            contentSHA256: file.sha256, metadataSHA256: metadataDigest, manifestSHA256: String(repeating: "c", count: 64), observedAt: date)
        try await journal.create(plan: plan)
        if stage == "owned-prepare-beforecommit" {
            try await JournalCrashCheckpoint.$beforeCommit.withValue({ _ in ready(directory, hot: true) }) {
                try await journal.prepare(planID: plan.id, phase: .isolation, backup: backup, at: date)
            }
        }
        if stage != "owned-created" { try await journal.prepare(planID: plan.id, phase: .isolation, backup: backup, at: date) }
        let effects = OwnedFixtureExperimentEffects(file: .quarantinedVerified, runtime: .observedRegisteredNotRunning, quarantineObject: file)
        if stage == "owned-result-beforecommit" {
            try await JournalCrashCheckpoint.$beforeCommit.withValue({ _ in ready(directory, hot: true) }) {
                try await journal.recordResult(planID: plan.id, phase: .isolation, effects: effects, at: date)
            }
        }
        if stage == "owned-result" { try await journal.recordResult(planID: plan.id, phase: .isolation, effects: effects, at: date) }
        ready(directory)
    }
    static func ready(_ directory: URL, hot: Bool = false) {
        do {
            if hot {
                let rollback = try Data(contentsOf: directory.appendingPathComponent("owned-fixture-experiment.sqlite-journal"))
                guard rollback.count > 512, rollback.prefix(8) == Data([0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7]) else { exit(68) }
            }
            try Data("ready".utf8).write(to: directory.appendingPathComponent("ready"))
        } catch { exit(67) }
        while true { pause() }
    }
}
#endif

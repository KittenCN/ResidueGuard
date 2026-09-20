#if DEBUG
import Darwin
import Foundation
import ResidueCore
import ResidueRecovery
@testable import ResiduePersistence

/// Exercises the actual migration and audited write methods in child processes.
enum AuditedCrashProbe {
    static let nonce = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let date = Date(timeIntervalSince1970: 5000)
    static func plan() throws -> VerifiedTransactionPlan {
        try .validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID,
            createdAt: date, expiresAt: date.addingTimeInterval(120),
            steps: [.init(id: "stop", targetID: "fixture", action: .bootoutExactService, fingerprint: "fp")],
            targets: [.init(id: "fixture", displayName: "Synthetic", presence: .highConfidenceOrphan, fingerprint: "fp")], impactApproved: true)
    }
    static func ready(_ directory: URL, hot: Bool = false) {
        do {
            if hot {
                let rollback = try Data(contentsOf: directory.appendingPathComponent("journal.sqlite-journal"))
                guard rollback.count > 512, rollback.prefix(8) == Data([0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7]) else { exit(68) }
            }
            try Data("ready".utf8).write(to: directory.appendingPathComponent("ready"))
        } catch { exit(69) }
        while true { pause() }
    }
    static func run(_ args: [String]) async throws {
        let stage = args[2], writer = args[1] == "writer"
        guard ["writer", "verify"].contains(args[1]),
              ["audit-claim", "audit-prepared", "audit-result", "audit-finished", "audit-prepare-beforecommit", "audit-result-beforecommit", "migration-beforecommit", "migration-aftercommit"].contains(stage) else { exit(64) }
        let directory = URL(fileURLWithPath: args[3], isDirectory: true)
        guard directory.deletingLastPathComponent().path == "/private/tmp", directory.lastPathComponent.hasPrefix("ResidueJournalCrashTests-") else { exit(64) }
        if stage.hasPrefix("migration-") {
            if writer {
                let journal = try TransactionJournal(directory: directory, createNew: true)
                try await journal.claim(planID: "legacy", digest: "legacy-digest", nonce: nonce.uuidString)
                try await journal.prepare(planID: "legacy", operationID: "pending")
                if stage == "migration-beforecommit" {
                    try JournalCrashCheckpoint.$beforeCommit.withValue({ _ in ready(directory, hot: true) }) {
                        try TransactionJournal.migrateLegacyToAuditV2(directory: directory)
                    }
                } else {
                    try TransactionJournal.migrateLegacyToAuditV2(directory: directory)
                    ready(directory)
                }
            } else {
                if stage == "migration-beforecommit" {
                    let legacy = try TransactionJournal(directory: directory)
                    guard try await legacy.unfinishedEntries().first?.steps.first?.operationID == "pending" else { exit(65) }
                    try TransactionJournal.migrateLegacyToAuditV2(directory: directory)
                }
                let reopened = try TransactionJournal(directory: directory, schema: .auditV2)
                guard case .legacyEvidenceUnavailable(let entry) = try await reopened.recoveryEntries().first,
                      entry.planID == "legacy", entry.digest == "legacy-digest", entry.steps.count == 1, entry.steps[0].result == nil else { exit(65) }
                do { try await reopened.claimAudited(nonce: nonce, plan: plan()); exit(66) }
                catch JournalError.replay { }
            }
            return
        }
        let journal = try TransactionJournal(directory: directory, createNew: writer, schema: .auditV2)
        if !writer {
            let entries = try await journal.recoveryEntries(includeFinished: true)
            guard entries.count == 1, case .audit(let snapshot) = entries[0], snapshot.plan.targets.first?.displayName == "Synthetic" else { exit(65) }
            let expectedSteps = ["audit-claim", "audit-prepare-beforecommit"].contains(stage) ? 0 : 1
            guard snapshot.observations.count == expectedSteps else { exit(65) }
            if expectedSteps == 1 {
                let expectedSuccess = ["audit-result", "audit-finished"].contains(stage)
                guard (snapshot.observations[0].effects?.runtime == .succeeded) == expectedSuccess,
                      snapshot.backups.count == 1 else { exit(65) }
            } else { guard snapshot.backups.isEmpty else { exit(65) } }
            guard snapshot.auditClosed == (stage == "audit-finished") else { exit(65) }
            do { try await journal.claimAudited(nonce: nonce, plan: plan()); exit(66) }
            catch JournalError.replay { }
            return
        }
        let p = try plan()
        try await journal.claimAudited(nonce: nonce, plan: p)
        let backups = [BackupAuditReceipt(targetID: "fixture", contentSHA256: String(repeating: "a", count: 64), metadataSHA256: String(repeating: "b", count: 64), observedAt: date)]
        if stage == "audit-prepare-beforecommit" {
            try await JournalCrashCheckpoint.$beforeCommit.withValue({ _ in ready(directory, hot: true) }) {
                try await journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: backups, at: date)
            }
        }
        if stage != "audit-claim" {
            try await journal.prepareAudited(plan: p, step: p.steps[0], backupReceipts: backups, at: date)
        }
        if stage == "audit-result-beforecommit" {
            try await JournalCrashCheckpoint.$beforeCommit.withValue({ _ in ready(directory, hot: true) }) {
                try await journal.recordAuditedResult(plan: p, step: p.steps[0], effects: .init(runtime: .succeeded), at: date)
            }
        }
        if ["audit-result", "audit-finished"].contains(stage) {
            try await journal.recordAuditedResult(plan: p, step: p.steps[0], effects: .init(runtime: .succeeded), at: date)
        }
        if stage == "audit-finished" { try await journal.finishAudited(plan: p) }
        ready(directory)
    }
}
#endif

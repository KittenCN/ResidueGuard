import CSQLite
import Darwin
import Foundation
import ResiduePersistence

// Test helper only. No system mutation, commands, services or production integration.
@main struct JournalCrashProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        #if DEBUG
        if args.count == 4, args[2].hasPrefix("audit-") || args.count == 4 && args[2].hasPrefix("migration-") {
            try await AuditedCrashProbe.run(args); return
        }
        #endif
        guard args.count == 4, ["writer", "verify"].contains(args[1]),
              ["claim", "prepared", "result", "finished", "uncommitted"].contains(args[2]) else { exit(64) }
        let directory = URL(fileURLWithPath: args[3], isDirectory: true)
        guard directory.deletingLastPathComponent().path == "/private/tmp",
              directory.lastPathComponent.hasPrefix("ResidueJournalCrashTests-") else { exit(64) }
        let stage = args[2]
        let journal = try TransactionJournal(directory: directory, createNew: args[1] == "writer")
        if args[1] == "verify" {
            let before = try await journal.unfinishedEntries()
            guard before.count == (stage == "finished" ? 0 : 1) else { exit(65) }
            if let entry = before.first {
                guard entry.planID == "plan", entry.digest == "digest" else { exit(65) }
                if ["claim", "uncommitted"].contains(stage) {
                    guard entry.steps.isEmpty else { exit(65) }
                } else {
                    guard entry.steps.count == 1, entry.steps[0].operationID == "fixture",
                          entry.steps[0].result == (stage == "result" ? .succeeded : nil) else { exit(65) }
                }
            }
            for (plan, nonce) in [("plan", "unused"), ("other", "nonce")] {
                do { try await journal.claim(planID: plan, digest: "digest", nonce: nonce); exit(66) }
                catch JournalError.replay { }
            }
            guard try await journal.unfinishedEntries() == before else { exit(65) }
            // Rejected replays must not consume fresh identifiers.
            try await journal.claim(planID: "other", digest: "digest", nonce: "unused")
            return
        }
        try await journal.claim(planID: "plan", digest: "digest", nonce: "nonce")
        if ["prepared", "result", "finished"].contains(stage) {
            try await journal.prepare(planID: "plan", operationID: "fixture")
        }
        if ["result", "finished"].contains(stage) {
            try await journal.recordResult(planID: "plan", operationID: "fixture", result: .succeeded)
        }
        if stage == "finished" { try await journal.finish(planID: "plan") }
        if stage == "uncommitted" {
            // Force SQLite to spill an uncommitted transaction to disk. SIGKILL leaves
            // a real hot rollback journal, rather than merely an idle committed DB.
            var db: OpaquePointer?
            guard sqlite3_open(directory.appendingPathComponent("journal.sqlite").path, &db) == SQLITE_OK else { exit(67) }
            let sql = "PRAGMA cache_size=10; PRAGMA synchronous=FULL; WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<10000) INSERT INTO plans SELECT 'seed-'||x,hex(randomblob(512)),'seed-nonce-'||x,1 FROM n; BEGIN IMMEDIATE; UPDATE plans SET digest=hex(randomblob(512)),finished=0 WHERE plan_id LIKE 'seed-%';"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { exit(67) }
            guard sqlite3_db_cacheflush(db) == SQLITE_OK else { exit(67) }
            let rollback = try Data(contentsOf: directory.appendingPathComponent("journal.sqlite-journal"))
            guard rollback.count > 512, rollback.prefix(8) == Data([0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7]) else { exit(68) }
            // Intentionally retain the open connection until killed; never commit/close.
        }
        try Data("ready".utf8).write(to: directory.appendingPathComponent("ready"))
        while true { pause() }
    }
}

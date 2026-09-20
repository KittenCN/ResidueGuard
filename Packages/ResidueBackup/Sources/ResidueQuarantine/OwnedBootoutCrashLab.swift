#if DEBUG
import Foundation
import ResidueBackup

package enum OwnedBootoutCrashPhase: String {
    case bootoutAfterIntent, bootoutBeforeOutcome, bootoutAfterOutcome
}
/// Synthetic process-death tests only. Deliberately never references the transport or VM probe.
package enum OwnedBootoutCrashLab {
    private struct Intent: Encodable {
        let version = 1
        let profile = "owned-iso01-bootout-v1"
        let attempt: UUID
        let authorizesReplay = false
        let syntheticRuntimeAndBuild = true
        let actualServiceCalls = 0
    }
    package static func run(phase: OwnedBootoutCrashPhase, token: UUID) async throws {
        let context = try OwnedFixtureCrashContext.open(token: token, create: true)
        let log = try OwnedBootoutLog(directoryFD: context.backupFD, attempt: token)
        _ = try await OwnedBootoutSequence.execute(prepare: {
            try log.append(.intent, Intent(attempt: token))
            if phase == .bootoutAfterIntent { try context.checkpoint(phase.rawValue) }
        }, fresh: {}, issue: {
            // Value injection only: "launched" models an ambiguous dispatched action, not a child process.
            .init(stdout: "synthetic command result", stderr: "", exitCode: 0, failure: nil,
                  outputTruncated: false, launched: true)
        }, record: { capture in
            guard let capture else { throw OwnedBootoutError.changed }
            if phase == .bootoutBeforeOutcome { try context.checkpoint(phase.rawValue) }
            try log.append(.outcome, OwnedBootoutOutcome(attempt: token, observedAt: Date(),
                disposition: "issuedOutcomeRecorded", capture: capture))
            if phase == .bootoutAfterOutcome { try context.checkpoint(phase.rawValue) }
        })
        throw OwnedBootoutError.stopped
    }
    package static func verify(token: UUID) throws -> String {
        let context = try OwnedFixtureCrashContext.open(token: token, create: false)
        guard let report = try OwnedBootoutAuditReader.read(directoryFD: context.backupFD), report.attempt == token else {
            throw OwnedBootoutError.storage
        }
        struct Result: Encodable {
            let syntheticRuntimeAndBuild = true
            let actualServiceCalls = 0
            let authorizesMutation = false
            let automaticRecovery = false
            let report: OwnedBootoutAuditSummary
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(Result(report: report)), as: UTF8.self)
    }
}
#endif

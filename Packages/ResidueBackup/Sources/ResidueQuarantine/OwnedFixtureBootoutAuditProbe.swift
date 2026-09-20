import Foundation
import Darwin
import ResidueBackup

public struct OwnedBootoutAuditCaptureSummary: Encodable {
    public let exitCode: Int32?
    public let failure: String?
    public let outputTruncated: Bool
    public let launched: Bool
    public let stdoutSHA256: String
    public let stderrSHA256: String
    public let textClassification: String
    init(_ capture: OwnedBootoutCapture) throws {
        func digest(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        guard digest(capture.stdoutSHA256), digest(capture.stderrSHA256),
              capture.elapsed.isFinite, capture.elapsed >= 0 else { throw OwnedBootoutError.storage }
        exitCode = capture.exitCode; failure = capture.failure?.rawValue
        outputTruncated = capture.outputTruncated; launched = capture.launched
        stdoutSHA256 = capture.stdoutSHA256; stderrSHA256 = capture.stderrSHA256
        textClassification = capture.stdout.isEmpty && capture.stderr.isEmpty ? "emptyCapture" : "unparsedDiagnostic"
    }
}
public struct OwnedBootoutAuditSummary: Encodable {
    public let attempt: UUID
    public let slots: [String]
    public let outcome: String
    public let mayHaveExecuted: String
    public let command: OwnedBootoutAuditCaptureSummary?
    public let post: OwnedBootoutAuditCaptureSummary?
    public let postFileMatchesHistory: Bool?
    public let postRuntime = "unknown"
    public let absenceProven = false
    public let authorizesMutation = false
    public let freshFilesInspected = false
}
public struct OwnedBootoutAuditReport: Encodable {
    public let coverage: String
    public let refusedRoots: Int
    public let logsAbsent: Int
    public let failedLogs: Int
    public let experiments: [OwnedBootoutAuditSummary]
    public let inspectionOnly = true
    public let mutationAvailable = false
}

extension QuarantineStore {
    public static func inspectISO01VirtualMachineBootoutExperiments() throws -> OwnedBootoutAuditReport {
        try OwnedBootoutGate.verify()
        let enumeration = try OwnedFixtureAuditLabReader.read()
        var reports: [OwnedBootoutAuditSummary] = [], absent = 0, failed = 0
        for root in enumeration.labs {
            do {
                if let report = try root.withDirectoryFD({ try OwnedBootoutAuditReader.read(directoryFD: $0) }) {
                    reports.append(report)
                } else { absent += 1 }
            } catch { failed += 1 }
        }
        return .init(coverage: failed > 0 || enumeration.refusedRootCount > 0 ? "partial" : enumeration.coverage.rawValue,
                     refusedRoots: enumeration.refusedRootCount, logsAbsent: absent, failedLogs: failed, experiments: reports)
    }
}

enum OwnedBootoutAuditReader {
    private struct Discovery: Decodable { let attempt: UUID }
    private struct Intent: Decodable {
        let version: Int; let profile: String; let attempt: UUID; let authorizesReplay: Bool
    }
    private struct Outcome: Decodable {
        let attempt: UUID; let disposition: String; let capture: OwnedBootoutCapture?
    }
    private struct Post: Decodable {
        let attempt: UUID; let state: String; let absenceProven: Bool; let filesStillMatch: Bool
        let capture: OwnedBootoutCapture?
    }
    /// Internal temporary-fixture seam. No directory input is exposed to the CLI.
    static func read(directoryFD: Int32) throws -> OwnedBootoutAuditSummary? {
        let file = openat(directoryFD, "owned-bootout-intent.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if file < 0 {
            guard errno == ENOENT else { throw OwnedBootoutError.storage }
            // Missing intent with later evidence is corruption, not an absent experiment.
            for slot in ["preflight", "outcome", "observation"] {
                var info = stat()
                if fstatat(directoryFD, "owned-bootout-" + slot + ".json", &info, AT_SYMLINK_NOFOLLOW) == 0 { throw OwnedBootoutError.storage }
                guard errno == ENOENT else { throw OwnedBootoutError.storage }
            }
            return nil
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= 3_145_728 else { throw OwnedBootoutError.storage }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(file, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0, data.count + max(0, count) <= 3_145_728 else { throw OwnedBootoutError.storage }
            if count == 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        let decoder = JSONDecoder()
        let attempt = try decoder.decode(Discovery.self, from: data).attempt
        // The discovery value is untrusted. Full canonical/digest/metadata checks follow.
        let log = try OwnedBootoutLog(directoryFD: directoryFD, attempt: attempt, readOnly: true)
        let slots = try log.readAll()
        guard let intentData = slots[.intent] else { throw OwnedBootoutError.storage }
        let intent = try decoder.decode(Intent.self, from: intentData)
        guard intent.version == 1, intent.profile == "owned-iso01-bootout-v1", intent.attempt == attempt,
              !intent.authorizesReplay else { throw OwnedBootoutError.storage }
        var outcome = "pendingOutcomeUnknown", mayHaveExecuted = "unknown"
        var command: OwnedBootoutAuditCaptureSummary?, postCapture: OwnedBootoutAuditCaptureSummary?
        if let outcomeData = slots[.outcome] {
            let value = try decoder.decode(Outcome.self, from: outcomeData)
            guard value.attempt == attempt else { throw OwnedBootoutError.storage }
            switch value.disposition {
            case "notIssuedPreflightFailed":
                guard value.capture == nil else { throw OwnedBootoutError.storage }
                mayHaveExecuted = "false"
            case "notIssued":
                guard let capture = value.capture, !capture.launched else { throw OwnedBootoutError.storage }
                mayHaveExecuted = "false"
            case "issuedOutcomeRecorded":
                guard let capture = value.capture, capture.launched else { throw OwnedBootoutError.storage }
                mayHaveExecuted = "true"
            default: throw OwnedBootoutError.storage
            }
            outcome = value.disposition
            command = try value.capture.map(OwnedBootoutAuditCaptureSummary.init)
        }
        var matched: Bool?
        if let postData = slots[.observation] {
            let post = try decoder.decode(Post.self, from: postData)
            guard post.attempt == attempt, post.state == "unknown", !post.absenceProven,
                  outcome == "issuedOutcomeRecorded" else { throw OwnedBootoutError.storage }
            matched = post.filesStillMatch
            postCapture = try post.capture.map(OwnedBootoutAuditCaptureSummary.init)
        }
        return .init(attempt: attempt, slots: OwnedBootoutLog.Slot.allCases.filter { slots[$0] != nil }.map(\.rawValue),
                     outcome: outcome, mayHaveExecuted: mayHaveExecuted,
                     command: command, post: postCapture,
                     postFileMatchesHistory: matched)
    }
}

import Foundation
import CryptoKit
import ResidueCore

public enum LaunchRuntimeState: String, Sendable { case running, registeredNotRunning, unknown }

/// Exact association requested by the caller; this is not proof of code-signing identity.
public struct LaunchRuntimeIdentity: Sendable {
    public let userID: UInt32
    public let label: String
    public let sourcePath: String
    public let program: String
    public init(userID: UInt32, label: String, sourcePath: String, program: String) {
        self.userID = userID; self.label = label; self.sourcePath = sourcePath; self.program = program
    }
    public var target: String { "gui/\(userID)/\(label)" }
}

public struct LaunchRuntimeObservation: Sendable {
    public let state: LaunchRuntimeState
    public let coverage: ScanCoverage
    public let provenance: SourceRecord
}

/// Diagnostic text is an unstable format. Only the captured VM build/profile is accepted.
/// Errors, including 'Could not find service', never establish absence or non-running state.
public struct LaunchRuntimeParser: Sendable {
    public static let profile = "launchctl-print-gui-26A428-v1"
    public init() {}
    public func parse(_ result: DiagnosticResult, expected: LaunchRuntimeIdentity,
                      osMajor: Int, osBuild: String, profile: String,
                      generation: String, observedAt: Date) -> LaunchRuntimeObservation {
        var state = LaunchRuntimeState.unknown
        var reason = "Unsupported OS build or parser profile"
        let supported = osMajor == 27 && osBuild == "26A428" && profile == Self.profile
        if supported {
            reason = "Incomplete or unsuccessful diagnostic capture"
            if let failure = result.failure { reason += ": " + failure.rawValue }
            if result.failure == nil && !result.outputTruncated && result.exitCode == 0 && result.stderr.isEmpty {
                reason = "Unrecognized format or conflicting service identity"
                if let fields = Self.fields(result.stdout, target: expected.target),
                   fields["path"] == expected.sourcePath, fields["program"] == expected.program,
                   expected.sourcePath.hasPrefix("/"), expected.program.hasPrefix("/"),
                   !expected.label.isEmpty, !expected.label.contains("/"),
                   fields["type"] == "LaunchAgent",
                   let domain = fields["domain"],
                   domain.range(of: "^gui/\(expected.userID) \\[\\d+\\]$", options: .regularExpression) != nil {
                    if fields["state"] == "running", fields["active count"] == "1",
                       let pid = fields["pid"].flatMap(Int.init), pid > 0 {
                        state = .running
                    } else if fields["state"] == "not running", fields["active count"] == "0", fields["pid"] == nil {
                        state = .registeredNotRunning
                    }
                    if state != .unknown { reason = "Exact service diagnostic association; point-in-time observation only" }
                }
            }
        }
        // An exact observed error spelling is diagnostic provenance, never a
        // runtime presence fact. No official stable error-format contract exists.
        let observedDiagnostic = supported && Self.matchesObservedScopedDiagnostic(result, expected: expected)
        if observedDiagnostic {
            reason = "Observed scoped service lookup diagnostic; runtime and domain reachability remain unknown"
        }
        let known = state != .unknown
        let coverage = ScanCoverage(providerID: "launchd.runtime", state: supported ? (result.failure == .cancelled ? .cancelled : (known ? .completeWithinDeclaredScope : .partial)) : .unsupported,
                                    declaredRoots: [expected.target], diagnostics: [reason], userScopes: ["gui/\(expected.userID)"],
                                    osBuild: osBuild, generation: generation, startedAt: observedAt, completedAt: observedAt,
                                    parsedCount: known ? 1 : 0, unparsedCount: known ? 0 : 1,
                                    skippedAreas: ["Other services and domains; signing identity; mutation capability"])
        let digest = SHA256.hash(data: Data(result.stdout.utf8)).map { String(format: "%02x", $0) }.joined()
        let provenance = SourceRecord(id: .init(providerID: "launchd.runtime", scope: "gui/\(expected.userID)", nativeIdentity: expected.label),
                                      category: "launchd.runtime", observedAt: observedAt, generation: generation,
                                      sourceArtifact: "/bin/launchctl print \(expected.target)", displayName: expected.label,
                                      declaredAppIDs: [], targetReferences: known ? [expected.sourcePath, expected.program] : [],
                                      rawMetadata: ["stdoutSHA256": digest, "parserProfile": profile, "osBuild": osBuild,
                                                    "outputTruncated": String(result.outputTruncated),
                                                    "observedDiagnostic": observedDiagnostic ? "scopedServiceLookupText26A428" : "unclassified",
                                                    "runtimeState": state.rawValue, "captureFailure": result.failure?.rawValue ?? "none", "exitCode": result.exitCode.map(String.init) ?? "unavailable"],
                                      parseWarnings: known ? [] : [reason])
        return .init(state: state, coverage: coverage, provenance: provenance)
    }

    private static func matchesObservedScopedDiagnostic(_ result: DiagnosticResult, expected: LaunchRuntimeIdentity) -> Bool {
        guard result.failure == nil, !result.outputTruncated, result.exitCode == 113,
              result.stdout.isEmpty, expected.userID > 0,
              !expected.label.isEmpty, !expected.label.hasPrefix("-"), !expected.label.contains(".."),
              expected.label.utf8.count <= 255,
              expected.label.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                      || byte == 46 || byte == 45 || byte == 95
              }) else { return false }
        return result.stderr == "Bad request.\nCould not find service \"\(expected.label)\" in domain for user gui: \(expected.userID)\n"
    }

    private static func fields(_ text: String, target: String) -> [String: String]? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.first == "\(target) = {", lines.last == "}" else { return nil }
        let allowed: Set<String> = ["active count", "path", "type", "state", "program", "domain", "asid", "minimum runtime", "exit timeout", "runs", "pid", "immediate reason", "forks", "execs", "initialized", "trampolined", "started suspended", "proxy started suspended", "checked allocations", "checked allocations reason", "checked allocations flags", "last exit code", "spawn type", "jetsam priority", "jetsam memory limit (active)", "jetsam memory limit (inactive)", "jetsamproperties category", "jetsam thread limit", "cpumon", "sanitizer flags", "properties", "job state"]
        let blocks: Set<String> = ["arguments", "inherited environment", "default environment", "environment", "resource coalition", "jetsam coalition"]
        var fields: [String: String] = [:]
        var seenBlocks = Set<String>()
        var inBlock = false
        for line in lines.dropFirst().dropLast() {
            if inBlock {
                if line == "\t}" { inBlock = false; continue }
                guard line.hasPrefix("\t\t"), !line.contains("{"), !line.contains("}") else { return nil }
                continue
            }
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { return nil }
            let body = String(line.dropFirst())
            guard let separator = body.range(of: " = ") else { return nil }
            let pair = [String(body[..<separator.lowerBound]), String(body[separator.upperBound...])]
            if pair[1] == "{" {
                guard blocks.contains(pair[0]), seenBlocks.insert(pair[0]).inserted else { return nil }
                inBlock = true
            } else {
                guard allowed.contains(pair[0]), fields[pair[0]] == nil, !pair[1].contains("{"), !pair[1].contains("}") else { return nil }
                fields[pair[0]] = pair[1]
            }
        }
        guard !inBlock, fields["properties"] != nil, fields["runs"].flatMap(Int.init) != nil else { return nil }
        // The reboot capture contains this opaque field. Accept only its observed
        // literal/context, without using it to derive runtime state or cleanup eligibility.
        if let jobState = fields["job state"] {
            guard jobState == "uninitialized", fields["state"] == "not running",
                  fields["active count"] == "0", fields["runs"] == "0", fields["pid"] == nil else { return nil }
        }
        return fields
    }
}

import Foundation
import ResidueCore
import CryptoKit
import CoreFoundation

public enum LaunchConfigurationParser {
    public enum Failure: Error { case invalidShape, missingLabel, limitExceeded }
    public static func parse(_ data: Data, source: URL, scope: String, generation: String, observedAt: Date = Date()) throws -> SourceRecord {
        guard data.count <= 4_194_304 else { throw Failure.limitExceeded }
        let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        try validate(raw, depth: 0)
        guard let dictionary = raw as? [String: Any] else { throw Failure.invalidShape }
        guard let label = dictionary["Label"] as? String, !label.isEmpty else { throw Failure.missingLabel }
        var warnings = try validateLaunchSchema(dictionary)
        let args = dictionary["ProgramArguments"] as? [String]
        // Schema validation distinguishes an absent Program from an invalid one.
        // Only absence permits launchd's ProgramArguments fallback.
        let program = dictionary["Program"] as? String ?? args?.first
        var targets: [String] = []
        if let program, !program.isEmpty { targets.append(program) } else { warnings.append("missingProgram") }
        if let program, !program.hasPrefix("/") { warnings.append("relativeProgram") }
        if let program, ["sh", "bash", "zsh", "env", "osascript", "python", "python3", "perl", "ruby", "node"].contains(URL(fileURLWithPath: program).lastPathComponent) {
            warnings.append("ambiguousPayload")
            // Retain arguments as evidence only; never assume an interpreter proves its payload present.
        }
        if dictionary["BundleProgram"] != nil { warnings.append("bundleProgramRequiresOwningBundle") }
        let known: Set<String> = ["Label", "Program", "ProgramArguments", "RunAtLoad", "KeepAlive", "WorkingDirectory", "UserName", "AssociatedBundleIdentifiers", "BundleProgram"]
        let unknown = dictionary.keys.filter { !known.contains($0) }.sorted()
        if !unknown.isEmpty { warnings.append("additionalLaunchSemanticsUnverified") }
        let appIDs: [String]
        if let ids = dictionary["AssociatedBundleIdentifiers"] as? [String] { appIDs = ids }
        else if let id = dictionary["AssociatedBundleIdentifiers"] as? String { appIDs = [id] }
        else { appIDs = [] }
        // Retain bounded original plist for provenance, including unknown fields; never interpreted as instructions.
        if data.count > 4096 { warnings.append("rawProvenanceTruncated") }
        let metadata = ["contentSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "rawPropertyListBase64": data.prefix(4096).base64EncodedString(), "label": label, "parserVersion": "launch-plist-v2"]
        return SourceRecord(id: RecordIdentity(providerID: "launchd.configuration", scope: scope, nativeIdentity: "v1:\(source.path):\(label)"), category: "background", observedAt: observedAt, generation: generation, sourceArtifact: source.path, displayName: label, declaredAppIDs: appIDs, targetReferences: targets, rawMetadata: metadata, parseWarnings: warnings)
    }
    private static func validateLaunchSchema(_ values: [String: Any]) throws -> [String] {
        var warnings: [String] = []
        for key in ["Label", "Program", "BundleProgram", "WorkingDirectory", "UserName"] {
            if let value = values[key] {
                guard let text = value as? String, !text.isEmpty, !text.contains("\0") else { throw Failure.invalidShape }
            }
        }
        if let value = values["ProgramArguments"] {
            guard let args = value as? [String], !args.isEmpty,
                  args.allSatisfy({ !$0.contains("\0") }),
                  values["Program"] != nil || args.first?.isEmpty == false else { throw Failure.invalidShape }
        }
        if let value = values["RunAtLoad"], !isPropertyListBoolean(value) { throw Failure.invalidShape }
        if let value = values["KeepAlive"], !isPropertyListBoolean(value) {
            guard let conditions = value as? [String: Any] else { throw Failure.invalidShape }
            for (key, condition) in conditions {
                switch key {
                case "SuccessfulExit", "NetworkState", "Crashed":
                    guard isPropertyListBoolean(condition) else { throw Failure.invalidShape }
                case "PathState", "OtherJobEnabled":
                    guard let entries = condition as? [String: Any],
                          entries.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("\0") && isPropertyListBoolean($0.value) }) else { throw Failure.invalidShape }
                default:
                    warnings.append("additionalKeepAliveSemanticsUnverified")
                }
            }
        }
        if let value = values["AssociatedBundleIdentifiers"] {
            let identifiers: [String]
            if let identifier = value as? String { identifiers = [identifier] }
            else if let list = value as? [String] { identifiers = list }
            else { throw Failure.invalidShape }
            guard identifiers.allSatisfy({ !$0.isEmpty && !$0.contains("\0") }) else { throw Failure.invalidShape }
        }
        return Array(Set(warnings)).sorted()
    }
    private static func isPropertyListBoolean(_ value: Any) -> Bool {
        // `as? Bool` accepts numeric NSNumber values (including 0 and 1).
        // Plist integer values must not silently satisfy a boolean schema.
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
    private static func validate(_ value: Any, depth: Int) throws {
        guard depth <= 24 else { throw Failure.limitExceeded }
        if let text = value as? String, text.utf8.count > 16_384 { throw Failure.limitExceeded }
        if let values = value as? [Any] {
            guard values.count <= 4096 else { throw Failure.limitExceeded }
            for child in values { try validate(child, depth: depth + 1) }
        }
        if let values = value as? [String: Any] {
            guard values.count <= 4096 else { throw Failure.limitExceeded }
            for (key, child) in values { try validate(key, depth: depth + 1); try validate(child, depth: depth + 1) }
        }
    }
}

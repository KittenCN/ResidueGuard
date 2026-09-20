import Foundation
import CryptoKit

public struct ReportEntry: Sendable {
    public let source: SourceRecord
    public let presence: PresenceState
    public init(source: SourceRecord, presence: PresenceState) { self.source = source; self.presence = presence }
}
public enum ReportDataOrigin: String, Codable, Sendable { case observedReadOnly, synthetic, unknown }
public struct AuditReport: Encodable, Sendable {
    public struct Row: Encodable, Sendable {
        public let recordKey: String
        public let provider: String
        public let scope: String
        public let presence: PresenceState
        public let name: String?
        public let sourcePath: String?
        public let declaredAppIDs: [String]?
        public let warningCount: Int
    }
    public struct Coverage: Encodable, Sendable {
        public let provider: String
        public let state: CoverageState
        public let rootCount: Int
        public let parsedCount: Int
        public let unparsedCount: Int
        public let errorCount: Int
        public let skippedCount: Int
    }
    public let schemaVersion = 1
    public let isExecutionInput = false
    public let dataOrigin: ReportDataOrigin
    public let reportID: UUID
    public let createdAt: Date
    public let includesIdentitiesAndPaths: Bool
    public let records: [Row]
    public let coverage: [Coverage]
    /// Raw metadata, target references and error text are never exported, even in explicit detailed mode.
    public static func make(entries: [ReportEntry], coverage: [ScanCoverage], includeIdentitiesAndPaths: Bool = false,
                            salt: String = UUID().uuidString, now: Date = Date(), dataOrigin: ReportDataOrigin = .unknown) -> Self {
        let rows = entries.map { entry in
            let source = entry.source
            // Length-prefix components avoid ambiguous identity concatenation.
            let identity = [source.id.providerID, source.id.scope, source.id.nativeIdentity].map { "\($0.utf8.count):\($0)" }.joined()
            return Row(recordKey: pseudonym(identity, salt: salt), provider: publicProvider(source.id.providerID),
                scope: ["currentUser", "sharedAgents", "systemDaemons"].contains(source.id.scope) ? source.id.scope : "unknownScope",
                presence: entry.presence, name: includeIdentitiesAndPaths ? source.displayName : nil,
                sourcePath: includeIdentitiesAndPaths ? source.sourceArtifact : nil,
                declaredAppIDs: includeIdentitiesAndPaths ? source.declaredAppIDs : nil, warningCount: source.parseWarnings.count)
        }
        return Self(dataOrigin: dataOrigin, reportID: UUID(), createdAt: now, includesIdentitiesAndPaths: includeIdentitiesAndPaths, records: rows,
            coverage: coverage.map { Coverage(provider: publicProvider($0.providerID), state: $0.state,
                rootCount: $0.declaredRoots.count, parsedCount: $0.parsedCount, unparsedCount: $0.unparsedCount,
                errorCount: $0.errors.count, skippedCount: $0.skippedAreas.count) })
    }
    private static func publicProvider(_ input: String) -> String {
        let known = ["launchd.configuration", "launchd.runtime", "applications.index", "backgroundTaskManagement", "loginItems", "permissions.TCC", "scan.limits"]
        return known.contains(input) ? input : "unknownProvider"
    }
    public static func pseudonym(_ input: String, salt: String) -> String {
        SHA256.hash(data: Data(("\(salt.utf8.count):\(salt)" + input).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public func json() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public func csv() -> String {
        let header = ["schemaVersion", "dataOrigin", "isExecutionInput", "recordKey", "provider", "scope", "presence", "name", "sourcePath", "declaredAppIDs", "warningCount"]
        let rows = records.map { [String(schemaVersion), dataOrigin.rawValue, "false", $0.recordKey, $0.provider, $0.scope, $0.presence.rawValue, $0.name ?? "", $0.sourcePath ?? "", $0.declaredAppIDs?.joined(separator: ";") ?? "", String($0.warningCount)] }
        return ([header] + rows).map { $0.map(Self.csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
    public static func csvCell(_ input: String) -> String {
        let candidate = input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
        let risk = candidate.first.map { "=+-@".contains($0) } ?? false
        let safe = (risk ? "'" : "") + input
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

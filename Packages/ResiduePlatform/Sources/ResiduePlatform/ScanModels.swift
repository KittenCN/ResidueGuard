import Foundation
import ResidueCore

public struct ScanRoot: Sendable {
    public let url: URL
    public let scope: String
    public init(url: URL, scope: String) { self.url = url; self.scope = scope }
}
public struct ScanConfiguration: Sendable {
    public let launchRoots: [ScanRoot]
    public let applicationRoots: [URL]
    public let maximumEntries: Int
    public let maximumFileBytes: Int
    public let rootsTruncated: Bool
    public init(launchRoots: [ScanRoot], applicationRoots: [URL], maximumEntries: Int = 4096, maximumFileBytes: Int = 1_048_576) {
        self.rootsTruncated = launchRoots.count > 16 || applicationRoots.count > 16
        self.launchRoots = Array(launchRoots.prefix(16)); self.applicationRoots = Array(applicationRoots.prefix(16))
        self.maximumEntries = max(1, min(maximumEntries, 20_000))
        self.maximumFileBytes = max(1, min(maximumFileBytes, 4_194_304))
    }
    public static var currentUser: Self {
        let home = URL(fileURLWithPath: SafeFiles.realUserHome.isEmpty ? "/unavailable-current-user-home" : SafeFiles.realUserHome)
        return Self(launchRoots: [ScanRoot(url: home.appendingPathComponent("Library/LaunchAgents"), scope: "currentUser"), ScanRoot(url: URL(fileURLWithPath: "/Library/LaunchAgents"), scope: "sharedAgents"), ScanRoot(url: URL(fileURLWithPath: "/Library/LaunchDaemons"), scope: "systemDaemons")], applicationRoots: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")])
    }
}
public struct ScanRow: Sendable, Identifiable {
    public var id: RecordIdentity { record.id }
    public let record: SourceRecord
    public let presence: PresenceState
    public let capability: CapabilityDescriptor
    public let evidence: [String]
    public init(record: SourceRecord, presence: PresenceState, capability: CapabilityDescriptor, evidence: [String]) { self.record = record; self.presence = presence; self.capability = capability; self.evidence = evidence }
}
public struct ApplicationInstance: Sendable {
    public let bundleID: String
    public let path: String
    public let fileIdentity: String
    public let volumeIdentity: String
    public let signingStatus: String
    public let observedAt: Date
}
public struct ScanSnapshot: Sendable {
    public let generation: String
    public let observedAt: Date
    public let rows: [ScanRow]
    public let applications: [ApplicationInstance]
    public let coverage: [ScanCoverage]
    public init(generation: String, observedAt: Date, rows: [ScanRow], coverage: [ScanCoverage], applications: [ApplicationInstance] = []) { self.applications = applications; self.generation = generation; self.observedAt = observedAt; self.rows = rows; self.coverage = coverage }
    public var isCancelled: Bool { coverage.contains { $0.state == .cancelled } }
}

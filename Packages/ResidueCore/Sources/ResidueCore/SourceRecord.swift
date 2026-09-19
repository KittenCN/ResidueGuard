import Foundation

/// Stable source identity is scope-qualified; it never uses display names or row positions.
public struct RecordIdentity: Codable, Hashable, Sendable {
    public let providerID: String
    public let scope: String
    public let nativeIdentity: String
    public init(providerID: String, scope: String, nativeIdentity: String) {
        self.providerID = providerID; self.scope = scope; self.nativeIdentity = nativeIdentity
    }
}
public struct SourceRecord: Codable, Sendable, Identifiable {
    public let id: RecordIdentity
    public let category: String
    public let observedAt: Date
    public let generation: String
    public let sourceArtifact: String
    public let displayName: String
    public let declaredAppIDs: [String]
    public let targetReferences: [String]
    public let rawMetadata: [String: String]
    public let parseWarnings: [String]
    public init(id: RecordIdentity, category: String, observedAt: Date, generation: String,
                sourceArtifact: String, displayName: String, declaredAppIDs: [String],
                targetReferences: [String], rawMetadata: [String: String], parseWarnings: [String]) {
        self.id = id; self.category = category; self.observedAt = observedAt; self.generation = generation
        self.sourceArtifact = sourceArtifact; self.displayName = displayName; self.declaredAppIDs = declaredAppIDs
        self.targetReferences = targetReferences; self.rawMetadata = rawMetadata; self.parseWarnings = parseWarnings
    }
}
public struct ProviderResult: Sendable {
    public let records: [SourceRecord]
    public let coverage: ScanCoverage
    public init(records: [SourceRecord], coverage: ScanCoverage) { self.records = records; self.coverage = coverage }
}
public protocol RecordProvider: Sendable {
    func collect() async -> ProviderResult
}

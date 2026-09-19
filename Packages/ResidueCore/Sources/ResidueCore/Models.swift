import Foundation

public enum PresenceState: String, Codable, CaseIterable, Sendable {
    case present, highConfidenceOrphan, suspectedOrphan, unknown, volumeUnavailable
    case inTrash, sharedComponentActive, permissionDenied
}
public enum CoverageState: String, Codable, Sendable {
    case completeWithinDeclaredScope, partial, permissionDenied, unsupported, failed, cancelled
}
public struct ScanCoverage: Codable, Equatable, Sendable {
    public let providerID: String
    public let state: CoverageState
    public let declaredRoots: [String]
    public let userScopes: [String]
    public let osBuild: String
    public let generation: String
    public let startedAt: Date?
    public let completedAt: Date?
    public let parsedCount: Int
    public let unparsedCount: Int
    public let skippedAreas: [String]
    public let errors: [String]
    public let diagnostics: [String]
    public init(providerID: String, state: CoverageState, declaredRoots: [String], diagnostics: [String] = [], userScopes: [String] = [], osBuild: String = "unverified", generation: String = "unknown", startedAt: Date? = nil, completedAt: Date? = nil, parsedCount: Int = 0, unparsedCount: Int = 0, skippedAreas: [String] = [], errors: [String] = []) {
        self.providerID = providerID; self.state = state; self.declaredRoots = declaredRoots; self.diagnostics = diagnostics
        self.userScopes = userScopes; self.osBuild = osBuild; self.generation = generation
        self.startedAt = startedAt; self.completedAt = completedAt; self.parsedCount = parsedCount
        self.unparsedCount = unparsedCount; self.skippedAreas = skippedAreas; self.errors = errors
    }
}
public enum CapabilityState: String, Codable, Sendable {
    case supportedVerified, readOnly, guidedOnly, unverified, unsupported, blockedByPolicy
}
public enum CapabilityOperation: String, Codable, Sendable, CaseIterable {
    case enumerate, readStatus, removeRegistration, resetPermission, verifyOutcome, restoreConfiguration
}
public struct CapabilityDescriptor: Codable, Equatable, Sendable {
    public let profileID: String
    public let state: CapabilityState
    public let testedOSBuilds: [String]
    public let reason: String
    public let operations: [CapabilityOperation: CapabilityState]
    public init(profileID: String, state: CapabilityState, testedOSBuilds: [String], reason: String, operations: [CapabilityOperation: CapabilityState] = [:]) {
        self.profileID = profileID; self.state = state; self.testedOSBuilds = testedOSBuilds; self.reason = reason; self.operations = operations
    }
    public func support(for operation: CapabilityOperation) -> CapabilityState { operations[operation] ?? .unverified }
    public func permitsPlanning(for operation: CapabilityOperation, on osBuild: String) -> Bool {
        !profileID.isEmpty && !osBuild.isEmpty && state == .supportedVerified && support(for: operation) == .supportedVerified && testedOSBuilds.contains(osBuild)
    }
}
/// Evidence comes from injected observations; this type never reads or launches software.
public struct PresenceEvidence: Sendable {
    public var matchingInstallationExists = false
    public var validStandaloneExecutableExists = false
    public var sharedOwnerExists = false
    public var volumeOnline = true
    public var accessDenied = false
    public var inTrash = false
    public var stableRecheckVerified = false
    public var identityVerified = false
    public var allDeclaredTargetsMissing = false
    public var coverageComplete = false
    public var runtimeActive = false
    public var installationInProgress = false
    public var ambiguousPayload = false
    public var evidenceIDs: [String] = []
    public init() {}
}
public enum OrphanClassifier {
    public static func classify(_ e: PresenceEvidence) -> PresenceState {
        if e.sharedOwnerExists { return .sharedComponentActive }
        if e.matchingInstallationExists || e.validStandaloneExecutableExists { return .present }
        if e.inTrash { return .inTrash }
        if !e.volumeOnline { return .volumeUnavailable }
        if e.accessDenied { return .permissionDenied }
        if e.runtimeActive || e.installationInProgress || e.ambiguousPayload { return .unknown }
        guard e.identityVerified, e.coverageComplete else { return .unknown }
        if e.stableRecheckVerified && e.allDeclaredTargetsMissing && !e.evidenceIDs.isEmpty { return .highConfidenceOrphan }
        return .suspectedOrphan
    }
}

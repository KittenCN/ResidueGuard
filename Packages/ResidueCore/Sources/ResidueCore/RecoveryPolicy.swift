import Foundation

public struct RecoveryEvidence: Sendable {
    public let backupVerified: Bool
    public let destinationAbsent: Bool
    public let softwareReinstalled: Bool
    public let identityUnchanged: Bool
    public let metadataCompatible: Bool
    public let scopeVerified: Bool
    public let permissionGrant: Bool
    public init(backupVerified: Bool, destinationAbsent: Bool, softwareReinstalled: Bool,
                identityUnchanged: Bool, metadataCompatible: Bool, scopeVerified: Bool, permissionGrant: Bool = false) {
        self.backupVerified = backupVerified; self.destinationAbsent = destinationAbsent
        self.softwareReinstalled = softwareReinstalled; self.identityUnchanged = identityUnchanged
        self.metadataCompatible = metadataCompatible; self.scopeVerified = scopeVerified; self.permissionGrant = permissionGrant
    }
}
public enum RecoveryDecision: String, Sendable {
    case blockedConflict, blockedUnverified, permissionGrantNotRestorable, configurationOnlyRequiresNewPlan
}
public enum RecoveryPolicy {
    public static func evaluate(_ evidence: RecoveryEvidence) -> RecoveryDecision {
        if evidence.permissionGrant { return .permissionGrantNotRestorable }
        if !evidence.destinationAbsent || evidence.softwareReinstalled { return .blockedConflict }
        guard evidence.backupVerified, evidence.identityUnchanged, evidence.metadataCompatible,
              evidence.scopeVerified else { return .blockedUnverified }
        return .configurationOnlyRequiresNewPlan
    }
    /// A restoration decision never authorizes reloading or launching a service.
    public static let automaticServiceRestartAllowed = false
}

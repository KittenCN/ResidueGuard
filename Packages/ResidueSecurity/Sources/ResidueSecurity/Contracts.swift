import Foundation

/// Versioned IPC vocabulary only: identifiers refer to server-owned registrations, never GUI paths.
public enum HelperScope: String, Codable, Sendable { case currentUser, sharedMachine }
public enum KnownSourceKind: String, Codable, Sendable { case launchAgentConfiguration }
public struct KnownSourceID: Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: KnownSourceKind
    public init(id: UUID, kind: KnownSourceKind) { self.id = id; self.kind = kind }
}
public enum HelperRequest: Codable, Sendable {
    case status(protocolVersion: Int)
    case prepare(protocolVersion: Int, source: KnownSourceID, scope: HelperScope)
    case executeOnce(PlanToken)
    case executionStatus(protocolVersion: Int, executionID: UUID)
    case prepareRecovery(protocolVersion: Int, backupID: UUID)
}
public struct PlanToken: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let policyVersion: Int
    public let planID: UUID
    public let source: KnownSourceID
    public let scope: HelperScope
    public let planDigest: String
    public let nonce: UUID
    public let expiresAt: Date
    // Only server-side policy can mint a token; Codable decoding alone never makes it trusted.
    init(planID: UUID, source: KnownSourceID, scope: HelperScope, digest: String, nonce: UUID, expiresAt: Date) {
        protocolVersion = 1; policyVersion = 1; self.planID = planID; self.source = source
        self.scope = scope; planDigest = digest; self.nonce = nonce; self.expiresAt = expiresAt
    }
}
public enum SecurityFailure: Error, Equatable, Sendable {
    case transportUnavailable, callerRejected, unsupportedVersion, unknownSource, scopeBlocked
    case impactBlocked, invalidDigest, expired, unknownToken, replayed, tokenMismatch
    case authorizationUnavailable, capacityExceeded
}
/// Only a future verified transport adapter may construct this; no GUI-supplied booleans/PID proof.
public struct VerifiedCaller: Equatable, Sendable {
    public let bundleID: String
    public let teamID: String
    public let designatedRequirement: String
    public let uid: UInt32
    public let sessionID: UInt32
    public let connectionID: UUID
    init(bundleID: String, teamID: String, designatedRequirement: String, uid: UInt32, sessionID: UInt32, connectionID: UUID) {
        self.bundleID = bundleID; self.teamID = teamID; self.designatedRequirement = designatedRequirement
        self.uid = uid; self.sessionID = sessionID; self.connectionID = connectionID
    }
}
/// Implementations must authenticate the current connection themselves. No request identity argument.
public protocol CallerAuthenticating: Sendable {
    func verifiedCaller() async throws -> VerifiedCaller
}
public struct UnavailableTransportAuthenticator: CallerAuthenticating {
    public init() {}
    public func verifiedCaller() async throws -> VerifiedCaller { throw SecurityFailure.transportUnavailable }
}
public struct ClientProfile: Sendable {
    public let bundleID: String
    public let teamID: String
    public let designatedRequirement: String
    public let uid: UInt32
    public let sessionID: UInt32
    public init(bundleID: String, teamID: String, designatedRequirement: String, uid: UInt32, sessionID: UInt32) {
        self.bundleID = bundleID; self.teamID = teamID; self.designatedRequirement = designatedRequirement
        self.uid = uid; self.sessionID = sessionID
    }
    func accepts(_ caller: VerifiedCaller) -> Bool {
        !bundleID.isEmpty && !teamID.isEmpty && !designatedRequirement.isEmpty && uid != 0 &&
        caller.bundleID == bundleID && caller.teamID == teamID &&
        caller.designatedRequirement == designatedRequirement && caller.uid == uid && caller.sessionID == sessionID
    }
}

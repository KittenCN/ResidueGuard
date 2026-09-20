import Foundation

/// Historical experiment observations only. No value in this file authorizes an operation.
public struct OwnedFixtureObjectIdentity: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let owner: UInt32
    public init(device: Int32, inode: UInt64, owner: UInt32) { self.device = device; self.inode = inode; self.owner = owner }
}
public struct OwnedFixtureFileIdentity: Codable, Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let owner: UInt32
    public let group: UInt32
    public let mode: UInt16
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanos: Int64
    public let changedSeconds: Int64
    public let changedNanos: Int64
    public let sha256: String
    public let extendedAttributes: [String: Data]
    public init(device: Int32, inode: UInt64, owner: UInt32, group: UInt32, mode: UInt16, size: Int64,
                modifiedSeconds: Int64, modifiedNanos: Int64, changedSeconds: Int64, changedNanos: Int64,
                sha256: String, extendedAttributes: [String: Data]) {
        self.device = device; self.inode = inode; self.owner = owner; self.group = group; self.mode = mode; self.size = size
        self.modifiedSeconds = modifiedSeconds; self.modifiedNanos = modifiedNanos; self.changedSeconds = changedSeconds
        self.changedNanos = changedNanos; self.sha256 = sha256; self.extendedAttributes = extendedAttributes
    }
}
public struct OwnedFixtureExperimentPlan: Codable, Equatable, Sendable {
    public let id: UUID
    public let userID: UInt32
    public let osBuild: String
    public let createdAt: Date
    public let expiresAt: Date
    public let source: OwnedFixtureFileIdentity
    public let quarantineRoot: OwnedFixtureObjectIdentity
    public let sourceRoot: OwnedFixtureObjectIdentity
    public let program: OwnedFixtureFileIdentity
    public var profile: String { "owned-iso01-observation-isolate-restore-v1" }
    public var label: String { "example.residueguard.fixture.iso01" }
    public var sourceName: String { "example.residueguard.fixture.iso01.plist" }
    public var programRelativePath: String { "Library/ResidueGuard-VM-ISO01/fixture" }
    public init(id: UUID, userID: UInt32, osBuild: String, createdAt: Date, expiresAt: Date,
                source: OwnedFixtureFileIdentity, quarantineRoot: OwnedFixtureObjectIdentity, sourceRoot: OwnedFixtureObjectIdentity, program: OwnedFixtureFileIdentity) {
        self.id = id; self.userID = userID; self.osBuild = osBuild; self.createdAt = createdAt; self.expiresAt = expiresAt
        self.source = source; self.quarantineRoot = quarantineRoot; self.sourceRoot = sourceRoot; self.program = program
    }
}
public struct OwnedFixtureBackupRoot: Codable, Equatable, Sendable {
    public let rootID: UUID
    public let directoryName: String
    public let parentDevice: Int32
    public let parentInode: UInt64
    public let device: Int32
    public let inode: UInt64
    public let owner: UInt32
    public var namespace: String { "ownedISO01VM" }
    public init(rootID: UUID, directoryName: String, parentDevice: Int32, parentInode: UInt64, device: Int32, inode: UInt64, owner: UInt32) {
        self.rootID = rootID; self.directoryName = directoryName; self.parentDevice = parentDevice; self.parentInode = parentInode
        self.device = device; self.inode = inode; self.owner = owner
    }
}
public struct OwnedFixtureBackupEvidence: Codable, Equatable, Sendable {
    public let backupID: UUID
    public let planID: UUID
    public let root: OwnedFixtureBackupRoot
    public let contentSHA256: String
    public let metadataSHA256: String
    public let manifestSHA256: String
    public let observedAt: Date
    public var metadataFormat: String { "source-fingerprint-json-sorted-keys-v1" }
    public init(backupID: UUID, planID: UUID, root: OwnedFixtureBackupRoot, contentSHA256: String, metadataSHA256: String, manifestSHA256: String, observedAt: Date) {
        self.backupID = backupID; self.planID = planID; self.root = root; self.contentSHA256 = contentSHA256
        self.metadataSHA256 = metadataSHA256; self.manifestSHA256 = manifestSHA256; self.observedAt = observedAt
    }
}
public enum OwnedFixtureExperimentPhase: String, Codable, Sendable { case isolation, restoration }
public enum OwnedFixtureFileEffect: String, Codable, Sendable { case notMoved, quarantinedVerified, restoredVerified, movedUnverified }
public enum OwnedFixtureRuntimeEffect: String, Codable, Sendable { case observedRegisteredNotRunning, unknown }
public struct OwnedFixtureExperimentEffects: Codable, Equatable, Sendable {
    public let file: OwnedFixtureFileEffect
    public let runtime: OwnedFixtureRuntimeEffect
    public let quarantineObject: OwnedFixtureFileIdentity?
    public let sourceObject: OwnedFixtureFileIdentity?
    public var registration: String { "noMutation" }
    public var permission: String { "noMutation" }
    public init(file: OwnedFixtureFileEffect, runtime: OwnedFixtureRuntimeEffect, quarantineObject: OwnedFixtureFileIdentity? = nil, sourceObject: OwnedFixtureFileIdentity? = nil) {
        self.file = file; self.runtime = runtime; self.quarantineObject = quarantineObject; self.sourceObject = sourceObject
    }
}
public struct OwnedFixtureExperimentStep: Codable, Equatable, Sendable {
    public let phase: OwnedFixtureExperimentPhase
    public let backup: OwnedFixtureBackupEvidence
    public let preparedAt: Date
    public internal(set) var effects: OwnedFixtureExperimentEffects?
    public internal(set) var recordedAt: Date?
    public var actionOutcomeUnknown: Bool { effects == nil }
}
public struct OwnedFixtureExperimentEntry: Codable, Equatable, Sendable {
    public let plan: OwnedFixtureExperimentPlan
    public internal(set) var steps: [OwnedFixtureExperimentStep]
    public var authorizesMutation: Bool { false }
}

import Foundation
import ResidueSecurity

public enum StatusLabCase: String, CaseIterable, Sendable {
    case accepted, deniedPrepare, deniedExecute, deniedExecutionStatus, deniedRecovery
    case oversize, duplicateField, badVersion, truncated, messageLimit, connectionLimit, invalidatedConnection
    case wrongClient, wrongServer, uidMismatch, sessionMismatch
}
public struct StatusLabReply: Codable, Equatable, Sendable {
    public let version: Int
    public let outcome: String
    public let transportExperimentOnly: Bool
    public let manifestTrustedForProduction: Bool
    public let authorizesMutation: Bool
    public init(_ outcome: String) {
        version = 1; self.outcome = outcome; transportExperimentOnly = true
        manifestTrustedForProduction = false; authorizesMutation = false
    }
    public func encoded() -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
    public static func decode(_ data: Data) throws -> StatusLabReply {
        guard data.count <= 2048 else { throw HelperWireFailure.resourceLimit }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, value.transportExperimentOnly, !value.manifestTrustedForProduction,
              !value.authorizesMutation, ["statusOnly", "deniedOperation", "invalidFrame", "messageLimit", "peerRejected"].contains(value.outcome),
              value.encoded() == data else { throw HelperWireFailure.nonCanonical }
        return value
    }
}
public enum StatusLabPolicy {
    public static func evaluate(_ data: Data, messageNumber: Int) -> StatusLabReply {
        guard (1...8).contains(messageNumber) else { return .init("messageLimit") }
        guard let request = try? HelperRequestWireCodec.decode(data) else { return .init("invalidFrame") }
        switch request {
        case .status: return .init("statusOnly")
        case .prepare, .executeOnce, .executionStatus, .prepareRecovery: return .init("deniedOperation")
        }
    }
    public static func acceptsPeer(actualUID: UInt32, actualSession: Int32, currentUID: UInt32, currentSession: Int32) -> Bool {
        currentUID > 0 && currentSession > 0 && actualUID == currentUID && actualSession == currentSession
    }
    public static func frame(for value: StatusLabCase) throws -> Data {
        let source = KnownSourceID(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, kind: .launchAgentConfiguration)
        switch value {
        case .deniedPrepare: return try HelperRequestWireCodec.encode(.prepare(protocolVersion: 1, source: source, scope: .currentUser))
        case .deniedExecutionStatus: return try HelperRequestWireCodec.encode(.executionStatus(protocolVersion: 1, executionID: source.id))
        case .deniedRecovery: return try HelperRequestWireCodec.encode(.prepareRecovery(protocolVersion: 1, backupID: source.id))
        case .deniedExecute:
            // Synthetic untrusted token bytes only. No internal PlanToken initializer or policy issuance.
            let data = Data("{\"request\":{\"executeOnce\":{\"_0\":{\"expiresAt\":1000,\"nonce\":\"11111111-1111-1111-1111-111111111111\",\"planDigest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"planID\":\"11111111-1111-1111-1111-111111111111\",\"policyVersion\":1,\"protocolVersion\":1,\"scope\":\"currentUser\",\"source\":{\"id\":\"11111111-1111-1111-1111-111111111111\",\"kind\":\"launchAgentConfiguration\"}}}},\"wireVersion\":1}".utf8)
            _ = try HelperRequestWireCodec.decode(data); return data
        case .oversize: return Data(repeating: 0x20, count: 16385)
        case .duplicateField: return Data("{\"request\":{\"status\":{\"protocolVersion\":1,\"protocolVersion\":1}},\"wireVersion\":1}".utf8)
        case .badVersion: return Data("{\"request\":{\"status\":{\"protocolVersion\":1}},\"wireVersion\":2}".utf8)
        case .truncated: return Data("{\"request\":".utf8)
        default: return try HelperRequestWireCodec.encode(.status(protocolVersion: 1))
        }
    }
}

public struct StatusLabMessageBudget: Sendable {
    public enum Decision: Equatable, Sendable { case allow(Int), rejectAndClose, closed }
    private var count = 0
    private var terminal = false
    public init() {}
    public mutating func next() -> Decision {
        guard !terminal else { return .closed }
        if count == 8 { terminal = true; return .rejectAndClose }
        count += 1; return .allow(count)
    }
    public mutating func invalidate() { terminal = true }
}

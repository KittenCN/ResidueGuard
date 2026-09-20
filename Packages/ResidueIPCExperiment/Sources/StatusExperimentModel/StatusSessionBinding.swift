import Foundation

/// Harness expectation, never a production authentication credential.
public struct StatusCallerSessionExpectation: Sendable {
    public let session: Int32
    public init(manifest: [String: String], labUUID: String) throws {
        guard Set(manifest.keys) == ["labUUID", "expectedCallerSession"],
              let uuid = UUID(uuidString: labUUID), uuid.uuidString == labUUID,
              manifest["labUUID"] == labUUID,
              let raw = manifest["expectedCallerSession"],
              raw.utf8.count <= 10, raw.first != "0",
              raw.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int32(raw), value > 0 else { throw CocoaError(.coderInvalidValue) }
        session = value
    }
}

/// Per-connection observation only. Establish after a valid pin-protected reply.
/// Invalidation, timeout, or transport rejection is terminal, with no re-learning.
public struct StatusObservedServerSession: Sendable {
    public private(set) var observed: Int32?
    public private(set) var terminal = false
    public init() {}
    public mutating func accept(actualUID: UInt32, expectedUID: UInt32, session: Int32) -> Bool {
        guard !terminal, expectedUID > 0, actualUID == expectedUID, session > 0,
              observed == nil || observed == session else { invalidate(); return false }
        observed = session
        return true
    }
    public mutating func invalidate() { terminal = true }
}

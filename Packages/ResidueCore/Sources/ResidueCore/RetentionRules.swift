import Foundation

public enum RetentionRuleError: Error, Equatable, Sendable {
    case invalidIdentity, invalidFingerprint, invalidLifetime, invalidTime
    case unsupportedSchema, unexpectedFields, duplicateRule, limitExceeded
}

/// Additive protection only. Construction must follow an explicit user choice of an observed record.
/// No path glob, presence override, coverage change, or execution authorization is represented here.
public struct RetentionRule: Codable, Equatable, Identifiable, Sendable {
    public static let defaultLifetime: TimeInterval = 30 * 86_400
    public static let maximumLifetime: TimeInterval = 365 * 86_400
    public let id: UUID
    public let recordIdentity: RecordIdentity
    public let fingerprint: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: UUID = UUID(), recordIdentity: RecordIdentity, fingerprint: String,
                createdAt: Date, lifetime: TimeInterval = Self.defaultLifetime) throws {
        guard lifetime.isFinite, lifetime > 0, lifetime <= Self.maximumLifetime else { throw RetentionRuleError.invalidLifetime }
        try self.init(id: id, recordIdentity: recordIdentity, fingerprint: fingerprint,
                      createdAt: createdAt, expiresAt: createdAt.addingTimeInterval(lifetime))
    }
    private init(id: UUID, recordIdentity: RecordIdentity, fingerprint: String, createdAt: Date, expiresAt: Date) throws {
        guard Self.validIdentity(recordIdentity) else { throw RetentionRuleError.invalidIdentity }
        guard Self.validFingerprint(fingerprint) else { throw RetentionRuleError.invalidFingerprint }
        guard createdAt.timeIntervalSince1970.isFinite, expiresAt.timeIntervalSince1970.isFinite,
              createdAt.timeIntervalSince1970 >= 0 else { throw RetentionRuleError.invalidTime }
        let lifetime = expiresAt.timeIntervalSince(createdAt)
        guard lifetime > 0, lifetime <= Self.maximumLifetime else { throw RetentionRuleError.invalidLifetime }
        self.id = id; self.recordIdentity = recordIdentity; self.fingerprint = fingerprint
        self.createdAt = createdAt; self.expiresAt = expiresAt
    }
    static func validFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func validIdentity(_ identity: RecordIdentity) -> Bool {
        for (value, limit) in [(identity.providerID, 128), (identity.scope, 256), (identity.nativeIdentity, 2048)] {
            guard !value.isEmpty, value.utf8.count <= limit,
                  value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !value.contains("*"), !value.contains("?"), !value.contains("["), !value.contains("]") else { return false }
        }
        return true
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case id, recordIdentity, fingerprint, createdAt, expiresAt }
    public init(from decoder: any Decoder) throws {
        try requireKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let identityDecoder = try c.superDecoder(forKey: .recordIdentity)
        try requireKeys(identityDecoder, ["providerID", "scope", "nativeIdentity"])
        try self.init(id: c.decode(UUID.self, forKey: .id),
                      recordIdentity: RecordIdentity(from: identityDecoder),
                      fingerprint: c.decode(String.self, forKey: .fingerprint),
                      createdAt: Date(timeIntervalSince1970: c.decode(Double.self, forKey: .createdAt)),
                      expiresAt: Date(timeIntervalSince1970: c.decode(Double.self, forKey: .expiresAt)))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(recordIdentity, forKey: .recordIdentity)
        try c.encode(fingerprint, forKey: .fingerprint)
        try c.encode(createdAt.timeIntervalSince1970, forKey: .createdAt)
        try c.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
    }
}

public struct RetentionObservation: Sendable {
    public let identity: RecordIdentity?
    public let fingerprint: String?
    public init(identity: RecordIdentity?, fingerprint: String?) { self.identity = identity; self.fingerprint = fingerprint }
}
public enum RetentionMatchState: String, Codable, Sendable {
    case protected, expired, notYetValid, unmatched, identityChanged, fingerprintChanged, unknownObservation
}
public enum RetentionRuleMatcher {
    /// nil observation means not observed, not deleted. Invalid/unknown observations cannot match.
    public static func evaluate(rule: RetentionRule, observation: RetentionObservation?, now: Date) -> RetentionMatchState {
        guard now.timeIntervalSince1970.isFinite else { return .unknownObservation }
        guard now >= rule.createdAt else { return .notYetValid }
        guard now < rule.expiresAt else { return .expired }
        guard let observation else { return .unmatched }
        guard let identity = observation.identity, let fingerprint = observation.fingerprint,
              RetentionRule.validIdentity(identity), RetentionRule.validFingerprint(fingerprint) else { return .unknownObservation }
        guard identity == rule.recordIdentity else { return .identityChanged }
        guard fingerprint == rule.fingerprint else { return .fingerprintChanged }
        return .protected
    }
}

public struct RetentionRuleConfiguration: Codable, Equatable, Sendable {
    public static let maximumRules = 128
    public static let maximumEncodedBytes = 65_536
    public let schemaVersion: Int
    public let rules: [RetentionRule]
    public init(rules: [RetentionRule] = []) throws {
        guard rules.count <= Self.maximumRules else { throw RetentionRuleError.limitExceeded }
        guard Set(rules.map(\.id)).count == rules.count,
              Set(rules.map(\.recordIdentity)).count == rules.count else { throw RetentionRuleError.duplicateRule }
        self.schemaVersion = 1; self.rules = rules
    }
    public static func decode(data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else { throw RetentionRuleError.limitExceeded }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else { throw RetentionRuleError.limitExceeded }
        return data
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, rules }
    public init(from decoder: any Decoder) throws {
        try requireKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == 1 else { throw RetentionRuleError.unsupportedSchema }
        var items = try c.nestedUnkeyedContainer(forKey: .rules)
        var rules: [RetentionRule] = []
        while !items.isAtEnd {
            guard rules.count < Self.maximumRules else { throw RetentionRuleError.limitExceeded }
            rules.append(try items.decode(RetentionRule.self))
        }
        try self.init(rules: rules)
    }
}
private struct RetentionCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private func requireKeys(_ decoder: any Decoder, _ keys: Set<String>) throws {
    let container = try decoder.container(keyedBy: RetentionCodingKey.self)
    guard Set(container.allKeys.map(\.stringValue)) == keys else { throw RetentionRuleError.unexpectedFields }
}

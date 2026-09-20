import Foundation

public enum HelperWireFailure: Error, Equatable, Sendable {
    case resourceLimit, malformed, nonCanonical, unsupportedVersion, invalidField
}

/// Untrusted wire data only. Decoding does not authenticate a peer, validate a token, or authorize work.
public enum HelperRequestWireCodec {
    public static let maximumBytes = 16_384
    public static let maximumDepth = 8
    public static let maximumStringCount = 64
    public static let maximumStringBytes = 256
    private struct Envelope: Codable {
        let wireVersion: Int
        let request: HelperRequest
    }
    public static func encode(_ request: HelperRequest) throws -> Data {
        try validate(request)
        let data: Data
        do { data = try encoder().encode(Envelope(wireVersion: 1, request: request)) }
        catch { throw HelperWireFailure.malformed }
        try preflight(data)
        return data
    }
    public static func decode(_ data: Data) throws -> HelperRequest {
        // Bound memory, nesting and string work before invoking Foundation's JSON parser.
        try preflight(data)
        let envelope: Envelope
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch { throw HelperWireFailure.malformed }
        guard envelope.wireVersion == 1 else { throw HelperWireFailure.unsupportedVersion }
        try validate(envelope.request)
        // Unknown/duplicate fields, whitespace, alternative escaping/numbers, and trailing bytes are not v1 wire syntax.
        guard try encode(envelope.request) == data else { throw HelperWireFailure.nonCanonical }
        return envelope.request
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }
    private static func validate(_ request: HelperRequest) throws {
        func version(_ value: Int) throws {
            guard value == 1 else { throw HelperWireFailure.unsupportedVersion }
        }
        switch request {
        case .status(let protocolVersion), .prepare(let protocolVersion, _, _),
             .executionStatus(let protocolVersion, _), .prepareRecovery(let protocolVersion, _):
            try version(protocolVersion)
        case .executeOnce(let token):
            try version(token.protocolVersion); try version(token.policyVersion)
            guard token.planDigest.utf8.count == 64,
                  token.planDigest.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  token.expiresAt.timeIntervalSinceReferenceDate.isFinite,
                  token.expiresAt.timeIntervalSince1970.isFinite else { throw HelperWireFailure.invalidField }
        }
    }
    // This scanner only enforces resource bounds; JSONDecoder still decides syntax and DTO shape.
    private static func preflight(_ data: Data) throws {
        guard !data.isEmpty else { throw HelperWireFailure.malformed }
        guard data.count <= maximumBytes else { throw HelperWireFailure.resourceLimit }
        var depth = 0, strings = 0, stringBytes = 0
        var inString = false, escaped = false
        for byte in data {
            if inString {
                if !escaped && byte == 34 { inString = false; continue }
                stringBytes += 1
                guard stringBytes <= maximumStringBytes else { throw HelperWireFailure.resourceLimit }
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
            } else {
                if byte == 34 {
                    strings += 1; stringBytes = 0; inString = true
                    guard strings <= maximumStringCount else { throw HelperWireFailure.resourceLimit }
                } else if byte == 123 || byte == 91 {
                    depth += 1
                    guard depth <= maximumDepth else { throw HelperWireFailure.resourceLimit }
                } else if byte == 125 || byte == 93 {
                    depth -= 1
                    guard depth >= 0 else { throw HelperWireFailure.malformed }
                }
            }
        }
        guard !inString, depth == 0 else { throw HelperWireFailure.malformed }
    }
}

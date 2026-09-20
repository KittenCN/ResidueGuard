import Foundation
import Testing
@testable import ResidueSecurity

private func wireToken(expiry: Date = Date(timeIntervalSinceReferenceDate: 1_000_000.125), digest: String = String(repeating: "a", count: 64)) -> PlanToken {
    .init(planID: UUID(), source: .init(id: UUID(), kind: .launchAgentConfiguration), scope: .currentUser,
          digest: digest, nonce: UUID(), expiresAt: expiry)
}
private func bytes(_ string: String) -> Data { Data(string.utf8) }
private func altered(_ request: HelperRequest, _ mutate: (inout [String: Any]) -> Void) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: HelperRequestWireCodec.encode(request)) as? [String: Any])
    mutate(&object)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
@Test func wireEveryRequestRoundTripsWithAmpleBoundedHeadroom() throws {
    let requests: [HelperRequest] = [.status(protocolVersion: 1),
        .prepare(protocolVersion: 1, source: .init(id: UUID(), kind: .launchAgentConfiguration), scope: .currentUser),
        .prepare(protocolVersion: 1, source: .init(id: UUID(), kind: .launchAgentConfiguration), scope: .sharedMachine),
        .executeOnce(wireToken()), .executionStatus(protocolVersion: 1, executionID: UUID()),
        .prepareRecovery(protocolVersion: 1, backupID: UUID())]
    for request in requests {
        let data = try HelperRequestWireCodec.encode(request)
        #expect(data.count < 1024) // 16 KiB is a ceiling, not a reason to accept arbitrary DTO fields.
        #expect(try HelperRequestWireCodec.encode(HelperRequestWireCodec.decode(data)) == data)
    }
}
@Test func wireHasExplicitGoldenStatusFrame() throws {
    #expect(try HelperRequestWireCodec.encode(.status(protocolVersion: 1)) == bytes("{\"request\":{\"status\":{\"protocolVersion\":1}},\"wireVersion\":1}"))
}
@Test func wireRejectsOversizeBeforeParsing() {
    #expect(throws: HelperWireFailure.resourceLimit) { try HelperRequestWireCodec.decode(Data(repeating: 0x20, count: 16_385)) }
}
@Test func wireRejectsDepthStringCountAndStringLengthLimits() {
    for data in [bytes(String(repeating: "[", count: 9) + String(repeating: "]", count: 9)),
                 bytes("[" + Array(repeating: "\"x\"", count: 65).joined(separator: ",") + "]"),
                 bytes("\"" + String(repeating: "x", count: 257) + "\"")] {
        #expect(throws: HelperWireFailure.resourceLimit) { try HelperRequestWireCodec.decode(data) }
    }
}
@Test func wireRejectsUnknownAndDuplicateFields() throws {
    let unknown = try altered(.status(protocolVersion: 1)) { $0["path"] = "/unexpected" }
    #expect(throws: HelperWireFailure.nonCanonical) { try HelperRequestWireCodec.decode(unknown) }
    let nested = bytes("{\"request\":{\"status\":{\"protocolVersion\":1,\"shell\":\"ignored?\"}},\"wireVersion\":1}")
    #expect(throws: HelperWireFailure.nonCanonical) { try HelperRequestWireCodec.decode(nested) }
    let duplicate = bytes("{\"request\":{\"status\":{\"protocolVersion\":1,\"protocolVersion\":1}},\"wireVersion\":1}")
    #expect(throws: HelperWireFailure.nonCanonical) { try HelperRequestWireCodec.decode(duplicate) }
}
@Test func wireRejectsNonCanonicalWhitespaceEscapesNumbersAndTrailingGarbage() throws {
    let canonical = String(decoding: try HelperRequestWireCodec.encode(.status(protocolVersion: 1)), as: UTF8.self)
    for string in [" " + canonical, canonical + "\n", canonical.replacingOccurrences(of: "status", with: "\\u0073tatus"),
                   canonical.replacingOccurrences(of: ":1", with: ":1.0"), canonical + "{}", canonical + "x"] {
        #expect(throws: (any Error).self) { try HelperRequestWireCodec.decode(bytes(string)) }
    }
}
@Test func wireRejectsUnknownVersionsOnEncodeAndDecode() throws {
    #expect(throws: HelperWireFailure.unsupportedVersion) { try HelperRequestWireCodec.encode(.status(protocolVersion: 2)) }
    let data = try altered(.status(protocolVersion: 1)) { $0["wireVersion"] = 2 }
    #expect(throws: HelperWireFailure.unsupportedVersion) { try HelperRequestWireCodec.decode(data) }
    let protocolData = bytes("{\"request\":{\"status\":{\"protocolVersion\":2}},\"wireVersion\":1}")
    #expect(throws: HelperWireFailure.unsupportedVersion) { try HelperRequestWireCodec.decode(protocolData) }
}
@Test func wireRejectsInvalidDigestAndNonfiniteExpiry() {
    for digest in ["", String(repeating: "g", count: 64), String(repeating: "a", count: 65), String(repeating: "é", count: 64)] {
        #expect(throws: HelperWireFailure.invalidField) { try HelperRequestWireCodec.encode(.executeOnce(wireToken(digest: digest))) }
    }
    for value in [Double.nan, Double.infinity, -Double.infinity] {
        #expect(throws: HelperWireFailure.invalidField) { try HelperRequestWireCodec.encode(.executeOnce(wireToken(expiry: Date(timeIntervalSinceReferenceDate: value)))) }
    }
}
@Test func wireRejectsMalformedUUIDScopeAndNonfiniteNumericInput() throws {
    let original = String(decoding: try HelperRequestWireCodec.encode(.executeOnce(wireToken())), as: UTF8.self)
    for changed in [original.replacingOccurrences(of: "currentUser", with: "system"),
                    original.replacingOccurrences(of: "1000000.125", with: "1e9999"),
                    original.replacingOccurrences(of: "1000000.125", with: "\"NaN\"")] {
        #expect(throws: (any Error).self) { try HelperRequestWireCodec.decode(bytes(changed)) }
    }
    let invalid = bytes("{\"request\":{\"executionStatus\":{\"executionID\":\"not-a-uuid\",\"protocolVersion\":1}},\"wireVersion\":1}")
    #expect(throws: HelperWireFailure.malformed) { try HelperRequestWireCodec.decode(invalid) }
}
@Test func wireScannerTreatsQuotedBracketsAndEscapedQuotesAsStrings() {
    let data = bytes("{\"request\":{\"status\":{\"protocolVersion\":1,\"extra\":\"[[[[[[[[[\\\"\\\\\"}},\"wireVersion\":1}")
    #expect(throws: HelperWireFailure.nonCanonical) { try HelperRequestWireCodec.decode(data) }
}
@Test func wireRejectsEmptyTruncatedInvalidUTF8AndUnexpectedShapes() {
    for data in [Data(), bytes("{"), bytes("\"unterminated"), Data([0xff, 0xfe]), bytes("[]"), bytes("null"), bytes("{\"request\":{\"shell\":{}},\"wireVersion\":1}")] {
        #expect(throws: (any Error).self) { try HelperRequestWireCodec.decode(data) }
    }
}
@Test func wireDecodedTokenStillCannotAuthenticateOrAuthorize() async throws {
    let request = try HelperRequestWireCodec.decode(HelperRequestWireCodec.encode(.executeOnce(wireToken())))
    guard case .executeOnce(let token) = request else { Issue.record("wrong case"); return }
    let profile = ClientProfile(bundleID: "test", teamID: "test", designatedRequirement: "test", uid: 501, sessionID: 1)
    let policy = HelperPolicy(profile: profile)
    await #expect(throws: SecurityFailure.transportUnavailable) { try await policy.consumeForPolicyReview(token) }
    #expect(await policy.executionAvailability() == .authorizationUnavailable)
}

import Foundation
import Testing
@testable import ResidueCore

private let retentionID = RecordIdentity(providerID: "launchd.configuration", scope: "gui/501", nativeIdentity: "/Users/fixture/Library/LaunchAgents/example.plist|example")
private let retentionHash = String(repeating: "a", count: 64)
private let retentionTime = Date(timeIntervalSince1970: 1_000_000)
private func retentionRule(lifetime: TimeInterval = RetentionRule.defaultLifetime) throws -> RetentionRule {
    try .init(recordIdentity: retentionID, fingerprint: retentionHash, createdAt: retentionTime, lifetime: lifetime)
}
private func retentionJSON(_ transform: (inout [String: Any]) -> Void) throws -> Data {
    let data = try RetentionRuleConfiguration(rules: [retentionRule()]).encoded()
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    transform(&json)
    return try JSONSerialization.data(withJSONObject: json)
}
@Test func retentionRequiresExactIdentityAndFingerprint() throws {
    let rule = try retentionRule()
    func state(_ id: RecordIdentity?, _ hash: String?) -> RetentionMatchState {
        RetentionRuleMatcher.evaluate(rule: rule, observation: .init(identity: id, fingerprint: hash), now: retentionTime)
    }
    #expect(state(retentionID, retentionHash) == .protected)
    #expect(state(retentionID, String(repeating: "b", count: 64)) == .fingerprintChanged)
    for id in [RecordIdentity(providerID: "other", scope: retentionID.scope, nativeIdentity: retentionID.nativeIdentity),
               .init(providerID: retentionID.providerID, scope: "gui/502", nativeIdentity: retentionID.nativeIdentity),
               .init(providerID: retentionID.providerID, scope: retentionID.scope, nativeIdentity: retentionID.nativeIdentity + "other")] {
        #expect(state(id, retentionHash) == .identityChanged)
    }
    #expect(state(nil, retentionHash) == .unknownObservation)
    #expect(state(retentionID, nil) == .unknownObservation)
    #expect(state(retentionID, "unknown") == .unknownObservation)
    #expect(RetentionRuleMatcher.evaluate(rule: rule, observation: nil, now: retentionTime) == .unmatched)
}
@Test func retentionExpirationIsExclusiveAndPreCreationClockIsRejected() throws {
    let rule = try retentionRule(lifetime: 60)
    let observation = RetentionObservation(identity: retentionID, fingerprint: retentionHash)
    #expect(RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: retentionTime.addingTimeInterval(-1)) == .notYetValid)
    #expect(RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: retentionTime.addingTimeInterval(59.999)) == .protected)
    #expect(RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: rule.expiresAt) == .expired)
    #expect(RetentionRuleMatcher.evaluate(rule: rule, observation: nil, now: rule.expiresAt) == .expired)
    #expect(RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: Date(timeIntervalSince1970: .infinity)) == .unknownObservation)
    #expect(try retentionRule().expiresAt.timeIntervalSince(retentionTime) == 30 * 86_400)
    #expect(try retentionRule(lifetime: RetentionRule.maximumLifetime).expiresAt.timeIntervalSince(retentionTime) == 365 * 86_400)
}
@Test func retentionConstructionRejectsUnboundedOrUnknownInputs() throws {
    for lifetime in [0, -1, .infinity, .nan, RetentionRule.maximumLifetime + 1] {
        #expect(throws: RetentionRuleError.invalidLifetime) { try retentionRule(lifetime: lifetime) }
    }
    for hash in ["", "unknown", String(repeating: "a", count: 63), String(repeating: "g", count: 64), String(repeating: "A", count: 64)] {
        #expect(throws: RetentionRuleError.invalidFingerprint) { try RetentionRule(recordIdentity: retentionID, fingerprint: hash, createdAt: retentionTime) }
    }
    for native in ["", "*", "foo?", "[a-z]", "a\nb", " abc", String(repeating: "x", count: 2049)] {
        let id = RecordIdentity(providerID: "fixture", scope: "user", nativeIdentity: native)
        #expect(throws: RetentionRuleError.invalidIdentity) { try RetentionRule(recordIdentity: id, fingerprint: retentionHash, createdAt: retentionTime) }
    }
    #expect(throws: RetentionRuleError.invalidTime) { try RetentionRule(recordIdentity: retentionID, fingerprint: retentionHash, createdAt: Date(timeIntervalSince1970: -.infinity)) }
}
@Test func retentionConfigurationRoundTripsAndUsesUnixTime() throws {
    let config = try RetentionRuleConfiguration(rules: [retentionRule()])
    let data = try config.encoded()
    #expect(try RetentionRuleConfiguration.decode(data: data) == config)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let rules = try #require(json["rules"] as? [[String: Any]])
    #expect(rules[0]["createdAt"] as? Double == retentionTime.timeIntervalSince1970)
}
@Test func retentionDecodingDoesNotBypassValidation() throws {
    for key in ["fingerprint", "expiresAt", "recordIdentity"] {
        let data = try retentionJSON { json in
            var rules = json["rules"] as! [[String: Any]]
            switch key {
            case "fingerprint": rules[0][key] = "unknown"
            case "expiresAt": rules[0][key] = retentionTime.timeIntervalSince1970 - 1
            default: rules[0][key] = ["providerID": "fixture", "scope": "*", "nativeIdentity": "foo"]
            }
            json["rules"] = rules
        }
        #expect(throws: (any Error).self) { try RetentionRuleConfiguration.decode(data: data) }
    }
}
@Test func retentionUnknownFieldsAndVersionsAreRejectedAtEveryLevel() throws {
    #expect(throws: RetentionRuleError.unsupportedSchema) { try RetentionRuleConfiguration.decode(data: retentionJSON { $0["schemaVersion"] = 2 }) }
    for level in 0...2 {
        let data = try retentionJSON { json in
            if level == 0 { json["allowCleanup"] = true; return }
            var rules = json["rules"] as! [[String: Any]]
            if level == 1 { rules[0]["allowCleanup"] = true }
            else { var identity = rules[0]["recordIdentity"] as! [String: Any]; identity["wildcard"] = true; rules[0]["recordIdentity"] = identity }
            json["rules"] = rules
        }
        #expect(throws: RetentionRuleError.unexpectedFields) { try RetentionRuleConfiguration.decode(data: data) }
    }
}
@Test func retentionConfigurationRejectsDuplicatesAndLimitsBeforeUnboundedAllocation() throws {
    let rule = try retentionRule()
    #expect(throws: RetentionRuleError.duplicateRule) { try RetentionRuleConfiguration(rules: [rule, rule]) }
    #expect(throws: RetentionRuleError.duplicateRule) { try RetentionRuleConfiguration(rules: [rule, retentionRule()]) }
    #expect(throws: RetentionRuleError.limitExceeded) { try RetentionRuleConfiguration(rules: Array(repeating: rule, count: 129)) }
    #expect(throws: RetentionRuleError.limitExceeded) { try RetentionRuleConfiguration.decode(data: Data(repeating: 32, count: 65_537)) }
    let oversized = try retentionJSON { json in json["rules"] = Array(repeating: (json["rules"] as! [[String: Any]])[0], count: 129) }
    #expect(throws: RetentionRuleError.limitExceeded) { try JSONDecoder().decode(RetentionRuleConfiguration.self, from: oversized) }
    #expect(throws: RetentionRuleError.duplicateRule) { try RetentionRuleConfiguration.decode(data: retentionJSON { $0["rules"] = Array(repeating: ($0["rules"] as! [[String: Any]])[0], count: 2) }) }
}
@Test func retentionMatchCanOnlyAddPlannerProtectionWithoutRemovingExpandedTargets() throws {
    let rule = try retentionRule()
    let observation = RetentionObservation(identity: retentionID, fingerprint: retentionHash)
    let protected = RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: retentionTime) == .protected
    let capability = CapabilityDescriptor(profileID: "synthetic", state: .supportedVerified, testedOSBuilds: ["synthetic"], reason: "fixture", operations: [.removeRegistration: .supportedVerified])
    let records = [PlanningRecord(id: "selected", operationKey: "shared-action", affectedTargetIDs: ["a"], capability: capability, fingerprint: retentionHash),
                   PlanningRecord(id: "hidden", operationKey: "shared-action", affectedTargetIDs: ["b"], capability: capability, fingerprint: retentionHash)]
    func plan(retained: Bool) -> DryRunPlan {
        let targets = [ImpactTarget(id: "a", displayName: "A", presence: .highConfidenceOrphan, isProtectedOrManaged: retained, fingerprint: retentionHash),
                       ImpactTarget(id: "b", displayName: "B", presence: .present, fingerprint: retentionHash)]
        return DryRunPlanner.makePlan(selectedRecordIDs: ["selected"], snapshot: .init(generation: "fixture", osBuild: "synthetic", records: records, targets: targets, observedAt: retentionTime), expandedImpactApproved: true, now: retentionTime)
    }
    let previous = plan(retained: false), retained = plan(retained: protected)
    #expect(previous.requirement == .two)
    #expect(retained.requirement == .blocked)
    #expect(retained.targets.map(\.id) == previous.targets.map(\.id))
    #expect(retained.targets.map(\.presence) == previous.targets.map(\.presence))
    #expect(retained.digest != previous.digest)
}
@Test func retentionEncodingHasAByteBudgetIndependentOfRuleCount() throws {
    let rules = try (0..<128).map { index in
        try RetentionRule(recordIdentity: .init(providerID: "fixture", scope: "user", nativeIdentity: String(repeating: "x", count: 2000) + String(index)), fingerprint: retentionHash, createdAt: retentionTime)
    }
    let config = try RetentionRuleConfiguration(rules: rules)
    #expect(throws: RetentionRuleError.limitExceeded) { try config.encoded() }
}

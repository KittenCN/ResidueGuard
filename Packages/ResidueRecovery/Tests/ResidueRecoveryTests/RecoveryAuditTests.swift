import CryptoKit
import Foundation
import Testing
import ResidueCore
import ResidueRecovery

private let now = Date(timeIntervalSince1970: 5000)
private let digest = String(repeating: "a", count: 64)
private func snapshot(_ observations: [StepAuditObservation]? = nil, auditClosed: Bool = false) throws -> RecoveryAuditSnapshot {
    let plan = try VerifiedTransactionPlan.validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID,
        createdAt: now, expiresAt: now.addingTimeInterval(120),
        steps: [.init(id: "private-step-stop", targetID: "private-target", action: .bootoutExactService, fingerprint: "private-fingerprint"),
                .init(id: "private-step-isolate", targetID: "private-target", action: .quarantineLaunchConfiguration, fingerprint: "private-fingerprint", dependencies: ["private-step-stop"])],
        targets: [.init(id: "private-target", displayName: "/Users/private/software.app", presence: .highConfidenceOrphan, fingerprint: "private-fingerprint")], impactApproved: true)
    return .init(plan: .init(recording: plan),
        backups: [.init(targetID: "private-target", contentSHA256: digest, metadataSHA256: digest, observedAt: now)],
        observations: observations ?? [.init(stepID: "private-step-stop", preparedAt: now, resultAt: now.addingTimeInterval(1), effects: .init(runtime: .succeeded, registration: .pendingSystemRefresh)),
                                        .init(stepID: "private-step-isolate", preparedAt: now.addingTimeInterval(2))], auditClosed: auditClosed)
}
private func editPayload(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
    var envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let old = try #require(Data(base64Encoded: envelope["payload"] as! String))
    var value = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
    edit(&value)
    let payload = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    // JSONEncoder escapes forward slashes; preserve canonical encoding for structural tests.
    let canonical = Data(String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "/", with: "\\/").utf8)
    envelope["payload"] = canonical.base64EncodedString()
    envelope["contentSHA256"] = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

@Test func roundTripPreservesFullHistoricalPlanAndSeparateEffects() throws {
    let original = try snapshot()
    let decoded = try RecoveryAudit.decode(RecoveryAudit.encode(original))
    #expect(decoded.plan.digest == original.plan.digest)
    #expect(decoded.plan.targets.first?.displayName == "/Users/private/software.app")
    #expect(decoded.backups.first?.metadataSHA256 == digest)
    #expect(decoded.observations.first?.effects?.runtime == .succeeded)
    #expect(decoded.observations.first?.effects?.registration == .pendingSystemRefresh)
    #expect(decoded.observations.last?.effects == nil)
}
@Test func partialRecoveryReportIsRedactedAndNeverAuthorizesExecution() throws {
    let summary = try RecoveryAudit.summary(snapshot())
    #expect(summary.targetCount == 1 && summary.plannedStepCount == 2)
    #expect(summary.steps.count == 2 && summary.steps.last?.effects == nil)
    #expect(summary.requiresReadOnlyReview && summary.backupReverificationRequired)
    #expect(!summary.automaticExecutionAllowed && !summary.contentAuthenticityEstablished)
    let display = String(reflecting: summary)
    for secret in ["private-target", "private-step", "private-fingerprint", "/Users/"] { #expect(!display.contains(secret)) }
}
@Test func corruptedHashAndUnknownVersionAreRejected() throws {
    let encoded = try RecoveryAudit.encode(snapshot())
    var envelope = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    envelope["contentSHA256"] = String(repeating: "0", count: 64)
    #expect(throws: RecoveryAuditError.corrupt) { try RecoveryAudit.decode(JSONSerialization.data(withJSONObject: envelope)) }
    envelope["schemaVersion"] = 99
    #expect(throws: RecoveryAuditError.unsupportedVersion) { try RecoveryAudit.decode(JSONSerialization.data(withJSONObject: envelope)) }
}
@Test func oversizedInputIsRejectedBeforeDecode() throws {
    #expect(throws: RecoveryAuditError.oversized) { try RecoveryAudit.decode(Data(repeating: 32, count: RecoveryAudit.maximumEnvelopeBytes + 1)) }
}
@Test(arguments: ["target", "step", "backup", "time", "count"])
func inconsistentReferencesAndBoundsAreRejected(change: String) throws {
    let encoded = try RecoveryAudit.encode(snapshot())
    let changed = try editPayload(encoded) { payload in
        if change == "target" || change == "count" {
            var plan = payload["plan"] as! [String: Any]
            if change == "target" { plan["targets"] = [] }
            else { plan["steps"] = Array(repeating: (plan["steps"] as! [[String: Any]])[0], count: 257) }
            payload["plan"] = plan
        } else if change == "backup" {
            var backups = payload["backups"] as! [[String: Any]]; backups[0]["targetID"] = "unknown"; payload["backups"] = backups
        } else {
            var observations = payload["observations"] as! [[String: Any]]
            if change == "step" { observations[0]["stepID"] = "unknown" }
            else { observations[0]["resultAt"] = -999_999_999 }
            payload["observations"] = observations
        }
    }
    #expect(throws: RecoveryAuditError.invalidSnapshot) { try RecoveryAudit.decode(changed) }
}
@Test func unknownFieldsAreRejectedEvenWithRecomputedHash() throws {
    let changed = try editPayload(RecoveryAudit.encode(snapshot())) { $0["executeOnLoad"] = true }
    #expect(throws: RecoveryAuditError.corrupt) { try RecoveryAudit.decode(changed) }
}
@Test func attackerRecomputedValidHashStillDoesNotEstablishTrust() throws {
    let changed = try editPayload(RecoveryAudit.encode(snapshot())) { payload in
        var plan = payload["plan"] as! [String: Any]
        var targets = plan["targets"] as! [[String: Any]]
        targets[0]["displayName"] = "attacker edited display"
        plan["targets"] = targets; payload["plan"] = plan
    }
    let decoded = try RecoveryAudit.decode(changed)
    #expect(decoded.plan.targets.first?.displayName == "attacker edited display")
    #expect(try !RecoveryAudit.summary(decoded).contentAuthenticityEstablished)
}
@Test func closedAuditWithUnresolvedPreparationIsRejected() throws {
    #expect(throws: RecoveryAuditError.invalidSnapshot) { try RecoveryAudit.encode(snapshot(auditClosed: true)) }
}
@Test func completedAndFailedStepsRemainSeparateHistoricalEffects() throws {
    let s = try snapshot([
        .init(stepID: "private-step-stop", preparedAt: now, resultAt: now.addingTimeInterval(1), effects: .init(runtime: .succeeded, registration: .pendingSystemRefresh)),
        .init(stepID: "private-step-isolate", preparedAt: now.addingTimeInterval(2), resultAt: now.addingTimeInterval(3), effects: .init(file: .failed, registration: .unverified))], auditClosed: true)
    let summary = try RecoveryAudit.summary(RecoveryAudit.decode(RecoveryAudit.encode(s)))
    #expect(summary.auditClosed)
    #expect(summary.steps[0].effects?.runtime == .succeeded)
    #expect(summary.steps[1].effects?.file == .failed)
    #expect(summary.requiresReadOnlyReview && !summary.automaticExecutionAllowed)
}

@Test func oversizedDecodedPayloadIsRejectedIndependentlyOfEnvelopeBound() throws {
    let payload = Data(repeating: 32, count: RecoveryAudit.maximumPayloadBytes + 1)
    let envelope: [String: Any] = ["schemaVersion": 1, "contentSHA256": digest, "payload": payload.base64EncodedString()]
    let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    #expect(data.count < RecoveryAudit.maximumEnvelopeBytes)
    #expect(throws: RecoveryAuditError.oversized) { try RecoveryAudit.decode(data) }
}

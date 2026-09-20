import Foundation
import Testing
@testable import StatusExperimentModel

@Test func onlyStatusIsAcceptedAcrossClosedOperationSet() throws {
    #expect(StatusLabPolicy.evaluate(try StatusLabPolicy.frame(for: .accepted), messageNumber: 1).outcome == "statusOnly")
    for scenario in [StatusLabCase.deniedPrepare, .deniedExecute, .deniedExecutionStatus, .deniedRecovery] {
        let reply = StatusLabPolicy.evaluate(try StatusLabPolicy.frame(for: scenario), messageNumber: 1)
        #expect(reply.outcome == "deniedOperation"); #expect(!reply.authorizesMutation)
    }
}
@Test func malformedAndOversizedFramesAreRefused() throws {
    for scenario in [StatusLabCase.oversize, .duplicateField, .badVersion, .truncated] {
        #expect(StatusLabPolicy.evaluate(try StatusLabPolicy.frame(for: scenario), messageNumber: 1).outcome == "invalidFrame")
    }
}
@Test func ninthAndInvalidMessageNumbersAreRefused() throws {
    let frame = try StatusLabPolicy.frame(for: .accepted)
    for number in [Int.min, -1, 0, 9, Int.max] { #expect(StatusLabPolicy.evaluate(frame, messageNumber: number).outcome == "messageLimit") }
    for number in 1...8 { #expect(StatusLabPolicy.evaluate(frame, messageNumber: number).outcome == "statusOnly") }
}
@Test func uidAndAuditSessionMustBothMatchAndBeAvailable() {
    #expect(StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: 3, expectedUID: 501, expectedSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 502, actualSession: 3, expectedUID: 501, expectedSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: 4, expectedUID: 501, expectedSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 0, actualSession: 3, expectedUID: 0, expectedSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: 0, expectedUID: 501, expectedSession: 0))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: -1, expectedUID: 501, expectedSession: -1))
}
@Test func repliesAreSmallCanonicalAndNeverAuthority() throws {
    for outcome in ["statusOnly", "deniedOperation", "invalidFrame", "messageLimit", "peerRejected"] {
        let reply = StatusLabReply(outcome), data = reply.encoded()
        #expect(data.count < 2048); #expect(try StatusLabReply.decode(data) == reply)
        #expect(reply.transportExperimentOnly && !reply.manifestTrustedForProduction && !reply.authorizesMutation)
        #expect(throws: (any Error).self) { try StatusLabReply.decode(data + Data([32])) }
    }
    #expect(throws: (any Error).self) { try StatusLabReply.decode(Data(repeating: 32, count: 2049)) }
    #expect(throws: (any Error).self) { try StatusLabReply.decode(StatusLabReply("executeApproved").encoded()) }
}
@Test func replyCannotClaimProductionTrustOrMutation() throws {
    let canonical = String(decoding: StatusLabReply("statusOnly").encoded(), as: UTF8.self)
    for field in ["authorizesMutation", "manifestTrustedForProduction"] {
        let altered = canonical.replacingOccurrences(of: "\"\(field)\":false", with: "\"\(field)\":true")
        #expect(throws: (any Error).self) { try StatusLabReply.decode(Data(altered.utf8)) }
    }
}

@Test func connectionMessageBudgetIsTerminalAfterLimitOrInvalidation() {
    var budget = StatusLabMessageBudget()
    for number in 1...8 { #expect(budget.next() == .allow(number)) }
    #expect(budget.next() == .rejectAndClose)
    for _ in 0..<10 { #expect(budget.next() == .closed) }
    var invalidated = StatusLabMessageBudget()
    #expect(invalidated.next() == .allow(1)); invalidated.invalidate()
    #expect(invalidated.next() == .closed)
}

@Test func callerExpectationBindsExactLabAndPositiveCanonicalSession() throws {
    let id = "164BDB58-15B7-4ED7-89AF-4CE39EC6C3B3"
    let good = ["labUUID": id, "expectedCallerSession": "2147483647"]
    #expect(try StatusCallerSessionExpectation(manifest: good, labUUID: id).session == Int32.max)
    for invalid in ["", "0", "-1", "+1", "01", " 1", "1.0", "2147483648", "999999999999999"] {
        #expect(throws: (any Error).self) {
            try StatusCallerSessionExpectation(manifest: ["labUUID": id, "expectedCallerSession": invalid], labUUID: id)
        }
    }
    #expect(throws: (any Error).self) { try StatusCallerSessionExpectation(manifest: good, labUUID: UUID().uuidString) }
    #expect(throws: (any Error).self) { try StatusCallerSessionExpectation(manifest: good, labUUID: id.lowercased()) }
    #expect(throws: (any Error).self) { try StatusCallerSessionExpectation(manifest: ["labUUID": id], labUUID: id) }
    #expect(throws: (any Error).self) { try StatusCallerSessionExpectation(manifest: good.merging(["unknown": "x"], uniquingKeysWith: { a, _ in a }), labUUID: id) }
}

@Test func observedServerSessionIsConnectionLocalAndTerminal() {
    var first = StatusObservedServerSession(), second = StatusObservedServerSession()
    #expect({ first.accept(actualUID: 501, expectedUID: 501, session: 10) }())
    #expect({ second.accept(actualUID: 501, expectedUID: 501, session: 11) }())
    #expect({ first.accept(actualUID: 501, expectedUID: 501, session: 10) }())
    #expect({ !first.accept(actualUID: 501, expectedUID: 501, session: 11) }())
    #expect(first.terminal)
    #expect({ !first.accept(actualUID: 501, expectedUID: 501, session: 10) }())
    second.invalidate()
    #expect({ !second.accept(actualUID: 501, expectedUID: 501, session: 11) }())
    #expect(second.observed == 11)
}

@Test func unknownPeerCannotEstablishOrRelearnSession() {
    for pair: (UInt32, Int32) in [(501, 0), (501, -1), (502, 4)] {
        var binding = StatusObservedServerSession()
        #expect({ !binding.accept(actualUID: pair.0, expectedUID: 501, session: pair.1) }())
        #expect(binding.observed == nil)
        #expect({ !binding.accept(actualUID: 501, expectedUID: 501, session: 4) }())
    }
}

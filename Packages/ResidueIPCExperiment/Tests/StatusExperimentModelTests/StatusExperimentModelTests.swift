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
    #expect(StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: 3, currentUID: 501, currentSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 502, actualSession: 3, currentUID: 501, currentSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: 4, currentUID: 501, currentSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 0, actualSession: 3, currentUID: 0, currentSession: 3))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: 0, currentUID: 501, currentSession: 0))
    #expect(!StatusLabPolicy.acceptsPeer(actualUID: 501, actualSession: -1, currentUID: 501, currentSession: -1))
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

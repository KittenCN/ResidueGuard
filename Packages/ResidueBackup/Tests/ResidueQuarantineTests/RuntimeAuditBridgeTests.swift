import XCTest
@testable import ResiduePlatform
@testable import ResidueQuarantine

final class RuntimeAuditBridgeTests: XCTestCase {
    func testKnownObservationPreservesExactProvenance() throws {
        let identity = LaunchRuntimeIdentity(userID: 501, label: "example.residueguard.fixture.iso01",
            sourcePath: "/fixture/source.plist", program: "/fixture/program")
        let text = "gui/501/example.residueguard.fixture.iso01 = {\n\tactive count = 0\n\tpath = /fixture/source.plist\n\ttype = LaunchAgent\n\tstate = not running\n\tprogram = /fixture/program\n\tdomain = gui/501 [100]\n\truns = 0\n\tproperties = inferred program\n}"
        let generation = UUID().uuidString, date = Date()
        let observation = LaunchRuntimeParser().parse(.init(stdout: text, stderr: "", exitCode: 0, failure: nil, outputTruncated: false), expected: identity,
            osMajor: 27, osBuild: "26A428", profile: LaunchRuntimeParser.profile, generation: generation, observedAt: date)
        let evidence = try QuarantineStore.auditRuntime(observation)
        XCTAssertEqual(evidence.generation, generation); XCTAssertEqual(evidence.observedAt, date)
        XCTAssertEqual(evidence.scope, "gui/501"); XCTAssertEqual(evidence.nativeLabel, identity.label)
        XCTAssertEqual(evidence.state, "registeredNotRunning"); XCTAssertEqual(evidence.coverage, "completeWithinDeclaredScope")
        XCTAssertEqual(evidence.exitCode, 0); XCTAssertEqual(evidence.captureFailure, "none")
        XCTAssertFalse(evidence.outputTruncated); XCTAssertEqual(evidence.stdoutSHA256.count, 64)
    }
    func testFailedCapturePreservesUnknownAndTruncation() throws {
        let identity = LaunchRuntimeIdentity(userID: 501, label: "example.residueguard.fixture.iso01",
            sourcePath: "/fixture/source.plist", program: "/fixture/program")
        let observation = LaunchRuntimeParser().parse(.init(stdout: "partial", stderr: "", exitCode: 15,
            failure: .timedOut, outputTruncated: true), expected: identity, osMajor: 27, osBuild: "26A428",
            profile: LaunchRuntimeParser.profile, generation: UUID().uuidString, observedAt: Date())
        let evidence = try QuarantineStore.auditRuntime(observation)
        XCTAssertEqual(evidence.state, "unknown"); XCTAssertEqual(evidence.coverage, "partial")
        XCTAssertEqual(evidence.exitCode, 15); XCTAssertEqual(evidence.captureFailure, "timedOut")
        XCTAssertTrue(evidence.outputTruncated)
    }
}

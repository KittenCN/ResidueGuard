import Foundation
import Testing
@testable import ResiduePlatform

private let identity = LaunchRuntimeIdentity(userID: 501, label: "example.residueguard.fixture.iso01", sourcePath: "/Users/fixture-user/Library/LaunchAgents/example.residueguard.fixture.iso01.plist", program: "/Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture")
private func observe(_ text: String, build: String = "26A428", major: Int = 27, profile: String = LaunchRuntimeParser.profile, stderr: String = "", exit: Int32? = 0, failure: DiagnosticFailure? = nil, truncated: Bool = false) -> LaunchRuntimeObservation {
    LaunchRuntimeParser().parse(.init(stdout: text, stderr: stderr, exitCode: exit, failure: failure, outputTruncated: truncated), expected: identity, osMajor: major, osBuild: build, profile: profile, generation: "fixture-generation", observedAt: Date(timeIntervalSince1970: 0))
}
@Test func capturedRuntimeStatesAreExactScopedObservations() {
    let running = observe(runtimeFixtureRunning)
    #expect(running.state == .running)
    #expect(running.coverage.parsedCount == 1)
    #expect(running.coverage.declaredRoots == [identity.target])
    #expect(running.provenance.rawMetadata["stdoutSHA256"]?.count == 64)
    #expect(running.provenance.targetReferences == [identity.sourcePath, identity.program])
    #expect(observe(runtimeFixtureRegistered).state == .registeredNotRunning)
}
@Test func runtimeProfileRequiresExactOSAndBuild() {
    #expect(observe(runtimeFixtureRunning, build: "26A429").state == .unknown)
    #expect(observe(runtimeFixtureRunning, major: 26).coverage.state == .unsupported)
    #expect(observe(runtimeFixtureRunning, profile: "future").state == .unknown)
}
@Test func runtimeFailuresNeverEstablishAbsence() {
    for text in [runtimeFixtureBaseline, runtimeFixtureAfterBootout, runtimeFixtureAfterRestore, ""] {
        #expect(observe(text).state == .unknown)
    }
    #expect(observe(runtimeFixtureRunning, stderr: "warning").state == .unknown)
    #expect(observe(runtimeFixtureRunning, exit: 113).state == .unknown)
    #expect(observe(runtimeFixtureRunning, exit: nil).state == .unknown)
    #expect(observe(runtimeFixtureRunning, failure: .timedOut).state == .unknown)
    #expect(observe(runtimeFixtureRunning, truncated: true).state == .unknown)
}

@Test func runtimeCaptureProvenanceSurvivesUnknownState() {
    let complete = observe(runtimeFixtureRunning)
    #expect(complete.provenance.rawMetadata["outputTruncated"] == "false")
    #expect(complete.provenance.rawMetadata["captureFailure"] == "none")
    #expect(complete.provenance.rawMetadata["exitCode"] == "0")
    for (failure, code, truncated) in [
        (DiagnosticFailure.outputLimit, Int32(15), true),
        (.timedOut, 15, false),
        (.cancelled, 9, true)
    ] {
        let result = observe(runtimeFixtureRunning, exit: code, failure: failure, truncated: truncated)
        let metadata = result.provenance.rawMetadata
        #expect(result.state == .unknown && result.provenance.targetReferences.isEmpty)
        #expect(metadata["runtimeState"] == "unknown")
        #expect(metadata["captureFailure"] == failure.rawValue)
        #expect(metadata["exitCode"] == String(code))
        #expect(metadata["outputTruncated"] == String(truncated))
        #expect(metadata["stdoutSHA256"] == complete.provenance.rawMetadata["stdoutSHA256"])
        #expect(metadata["parserProfile"] == LaunchRuntimeParser.profile)
    }
    let truncatedOnly = observe(runtimeFixtureRunning, truncated: true)
    #expect(truncatedOnly.state == .unknown)
    #expect(truncatedOnly.provenance.rawMetadata["outputTruncated"] == "true")
    #expect(truncatedOnly.provenance.rawMetadata["captureFailure"] == "none")
    let unsupported = observe("unknown output", build: "future", exit: nil, truncated: true)
    #expect(unsupported.coverage.state == .unsupported)
    #expect(unsupported.provenance.rawMetadata["outputTruncated"] == "true")
    #expect(unsupported.provenance.rawMetadata["exitCode"] == "unavailable")
    #expect(unsupported.provenance.rawMetadata["runtimeState"] == "unknown")
}
@Test func runtimeRejectsConflictingIdentityAndMalformedStructure() {
    let mutations = [
        runtimeFixtureRunning.replacingOccurrences(of: "gui/501", with: "gui/502"),
        runtimeFixtureRunning.replacingOccurrences(of: "iso01", with: "other"),
        runtimeFixtureRunning.replacingOccurrences(of: "path = /Users", with: "path = /Other"),
        runtimeFixtureRunning.replacingOccurrences(of: "program = /Users", with: "program = /Other"),
        runtimeFixtureRunning.replacingOccurrences(of: "state = running", with: "state = waiting"),
        runtimeFixtureRunning.replacingOccurrences(of: "pid = 1038", with: "pid = 0"),
        runtimeFixtureRunning.replacingOccurrences(of: "state = running", with: "state = running\n\tstate = not running"),
        runtimeFixtureRunning + "\ntrailing junk",
        String(runtimeFixtureRunning.dropLast()),
        runtimeFixtureRunning.replacingOccurrences(of: "\tproperties", with: "\tfuture properties"),
        runtimeFixtureRunning.replacingOccurrences(of: "\targuments = {", with: "\targuments = unknown"),
        runtimeFixtureRegistered.replacingOccurrences(of: "\truns = 0", with: "\tpid = 1\n\truns = 0")
    ]
    for text in mutations {
        let result = observe(text)
        #expect(result.state == .unknown)
        #expect(result.coverage.state == .partial)
        #expect(result.provenance.targetReferences.isEmpty)
    }
}

@Test func runtimeRebootRegistrationIsObservedWithoutInferringJobStateSemantics() {
    #expect(observe(runtimeFixtureAfterReboot).state == .registeredNotRunning)
    let changes = [
        runtimeFixtureAfterReboot.replacingOccurrences(of: "job state = uninitialized", with: "job state = future"),
        runtimeFixtureAfterReboot.replacingOccurrences(of: "job state = uninitialized", with: "job state = uninitialized\n\tjob state = uninitialized"),
        runtimeFixtureAfterReboot.replacingOccurrences(of: "state = not running", with: "state = future"),
        runtimeFixtureAfterReboot.replacingOccurrences(of: "active count = 0", with: "active count = 1"),
        runtimeFixtureAfterReboot.replacingOccurrences(of: "runs = 0", with: "runs = 1"),
        runtimeFixtureAfterReboot.replacingOccurrences(of: "job state = uninitialized", with: "pid = 1038\n\tjob state = uninitialized")
    ]
    for text in changes { #expect(observe(text).state == .unknown) }
    #expect(observe(runtimeFixtureAfterReboot, build: "26A429").state == .unknown)
}

@Test func observedScopedErrorTextRemainsUnknownAndPartial() {
    let text = "Bad request.\nCould not find service \"example.residueguard.fixture.iso01\" in domain for user gui: 501\n"
    let result = observe("", stderr: text, exit: 113)
    #expect(result.provenance.rawMetadata["observedDiagnostic"] == "scopedServiceLookupText26A428")
    #expect(result.state == .unknown)
    #expect(result.coverage.state == .partial)
    #expect(result.coverage.parsedCount == 0 && result.coverage.unparsedCount == 1)
    #expect(result.provenance.targetReferences.isEmpty)

    let negatives = [
        observe("", stderr: text, exit: 1), observe("", stderr: text, exit: 0),
        observe("", stderr: text, exit: nil), observe("output", stderr: text, exit: 113),
        observe("", stderr: text, exit: 113, truncated: true),
        observe("", stderr: text, exit: 113, failure: .timedOut),
        observe("", stderr: text, exit: 113, failure: .cancelled),
        observe("", build: "26A429", stderr: text, exit: 113),
        observe("", major: 26, stderr: text, exit: 113),
        observe("", profile: "future", stderr: text, exit: 113)
    ] + [
        text.replacingOccurrences(of: "501", with: "502"),
        text.replacingOccurrences(of: "gui:", with: "user:"),
        text.replacingOccurrences(of: "gui:", with: "system:"),
        text.replacingOccurrences(of: "iso01", with: "iso02"),
        text.replacingOccurrences(of: "Bad request.", with: "无效请求。"),
        text.replacingOccurrences(of: "\n", with: "\r\n"),
        String(text.dropLast()), "prefix\n" + text, text + "\n", text + text,
        text + "\u{FFFD}"
    ].map { observe("", stderr: $0, exit: 113) }
    for rejected in negatives {
        #expect(rejected.provenance.rawMetadata["observedDiagnostic"] == "unclassified")
        #expect(rejected.state == .unknown && rejected.provenance.targetReferences.isEmpty)
        #expect(rejected.coverage.parsedCount == 0)
    }
}

@Test func observedScopedDiagnosticRejectsInvalidCollectorLabels() {
    for label in ["-example.fixture", "example..fixture", "", "example/fixture", "example\nfixture"] {
        let expected = LaunchRuntimeIdentity(userID: 501, label: label, sourcePath: identity.sourcePath, program: identity.program)
        let capture = DiagnosticResult(stdout: "", stderr: "Bad request.\nCould not find service \"\(label)\" in domain for user gui: 501\n", exitCode: 113, failure: nil, outputTruncated: false)
        let result = LaunchRuntimeParser().parse(capture, expected: expected, osMajor: 27, osBuild: "26A428", profile: LaunchRuntimeParser.profile, generation: "fixture-generation", observedAt: Date(timeIntervalSince1970: 0))
        #expect(result.provenance.rawMetadata["observedDiagnostic"] == "unclassified")
        #expect(result.state == .unknown && result.coverage.state == .partial)
    }
}

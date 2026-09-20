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

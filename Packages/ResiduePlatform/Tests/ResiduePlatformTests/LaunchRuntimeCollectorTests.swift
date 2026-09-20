import Foundation
import Darwin
import Testing
@testable import ResiduePlatform

private actor Calls {
    var count = 0
    func record() { count += 1 }
}
private let collectorIdentity = LaunchRuntimeIdentity(userID: getuid(), label: "example.residueguard.fixture.iso01", sourcePath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/example.residueguard.fixture.iso01.plist").path, program: "/usr/local/bin/residueguard-fixture")
private var collectorFixture: String {
    runtimeFixtureRunning.replacingOccurrences(of: "gui/501", with: "gui/\(getuid())")
        .replacingOccurrences(of: "/Users/fixture-user/Library/LaunchAgents/example.residueguard.fixture.iso01.plist", with: collectorIdentity.sourcePath)
        .replacingOccurrences(of: "/Users/fixture-user/Library/ResidueGuard-VM-ISO01/fixture", with: collectorIdentity.program)
}
@Test func runtimeCollectorGatesBeforeLaunching() async {
    let calls = Calls()
    for (configuration, major, build, uid) in [
        (LaunchRuntimeCollector.Configuration.disabled, 27, "26A428", getuid()),
        (.exactCurrentUserService(profile: "future"), 27, "26A428", getuid()),
        (.exactCurrentUserService(profile: LaunchRuntimeParser.profile), 26, "26A428", getuid()),
        (.exactCurrentUserService(profile: LaunchRuntimeParser.profile), 27, "26A429", getuid()),
        (.exactCurrentUserService(profile: LaunchRuntimeParser.profile), 27, "26A428", getuid() + 1),
        (.exactCurrentUserService(profile: LaunchRuntimeParser.profile), 27, "26A428", 0)
    ] {
        let collector = LaunchRuntimeCollector(configuration: configuration, osMajor: major, osBuild: build, userID: uid) { _ in
            await calls.record()
            return .init(stdout: collectorFixture, stderr: "", exitCode: 0, failure: nil, outputTruncated: false)
        }
        #expect(await collector.collect(expected: collectorIdentity, generation: "test").state == .unknown)
    }
    #expect(await calls.count == 0)
}
@Test func runtimeCollectorValidatesExactRequestAndPropagatesFailures() async {
    for failure in [DiagnosticFailure.cancelled, .timedOut, .outputLimit, .ioFailure, .launchFailed] {
        let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile), osMajor: 27, osBuild: "26A428", userID: getuid()) { request in
            guard case .currentUserService(let label) = request else { Issue.record("Wrong command"); return .init(stdout: "", stderr: "", exitCode: nil, failure: .invalidRequest, outputTruncated: false) }
            #expect(label == collectorIdentity.label)
            return .init(stdout: collectorFixture, stderr: "", exitCode: 0, failure: failure, outputTruncated: false)
        }
        let observation = await collector.collect(expected: collectorIdentity, generation: "test")
        #expect(observation.state == .unknown)
        #expect(observation.provenance.rawMetadata["captureFailure"] == failure.rawValue)
        if failure == .cancelled { #expect(observation.coverage.state == .cancelled) }
    }
}
@Test func runtimeCollectorOnlyAcceptsValidatedSourceIdentity() async {
    let calls = Calls()
    let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile), osMajor: 27, osBuild: "26A428", userID: getuid()) { _ in
        await calls.record()
        return .init(stdout: collectorFixture, stderr: "", exitCode: 0, failure: nil, outputTruncated: false)
    }
    #expect(await collector.collect(expected: collectorIdentity, generation: "test").state == .running)
    for source in ["/Library/LaunchDaemons/example.plist", "/tmp/fixture.plist", collectorIdentity.sourcePath + "/../other.plist", collectorIdentity.sourcePath + "\n"] {
        let bad = LaunchRuntimeIdentity(userID: getuid(), label: collectorIdentity.label, sourcePath: source, program: collectorIdentity.program)
        #expect(await collector.collect(expected: bad, generation: "test").state == .unknown)
    }
    #expect(await calls.count == 1)
}
@Test func runtimeCollectorCancellationBeforeStartDoesNotLaunch() async {
    let calls = Calls()
    let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile), osMajor: 27, osBuild: "26A428", userID: getuid()) { _ in
        await calls.record()
        return .init(stdout: collectorFixture, stderr: "", exitCode: 0, failure: nil, outputTruncated: false)
    }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await collector.collect(expected: collectorIdentity, generation: "test")
    }
    #expect(await task.value.coverage.state == .cancelled)
    #expect(await calls.count == 0)
}
@Test func runtimeCollectorRejectsIncompleteAndConflictingCaptures() async {
    let captures: [DiagnosticResult] = [
        .init(stdout: collectorFixture, stderr: "", exitCode: 0, failure: nil, outputTruncated: true),
        .init(stdout: collectorFixture + "\nunknown output", stderr: "", exitCode: 0, failure: nil, outputTruncated: false),
        .init(stdout: collectorFixture.replacingOccurrences(of: "state = running", with: "state = future"), stderr: "", exitCode: 0, failure: nil, outputTruncated: false),
        .init(stdout: collectorFixture.replacingOccurrences(of: collectorIdentity.program, with: "/different/program"), stderr: "", exitCode: 0, failure: nil, outputTruncated: false)
    ]
    for captured in captures {
        let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile), osMajor: 27, osBuild: "26A428", userID: getuid()) { _ in captured }
        let observation = await collector.collect(expected: collectorIdentity, generation: "test")
        #expect(observation.state == .unknown)
        #expect(observation.provenance.targetReferences.isEmpty)
    }
}
@Test func runtimeCollectorCancellationDuringCaptureOverridesKnownResult() async {
    let task = Task {
        let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile), osMajor: 27, osBuild: "26A428", userID: getuid()) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .init(stdout: collectorFixture, stderr: "", exitCode: 0, failure: nil, outputTruncated: false)
        }
        return await collector.collect(expected: collectorIdentity, generation: "test")
    }
    let observation = await task.value
    #expect(observation.state == .unknown)
    #expect(observation.coverage.state == .cancelled)
}

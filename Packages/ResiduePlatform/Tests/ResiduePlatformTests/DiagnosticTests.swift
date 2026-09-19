import Foundation
import Testing
@testable import ResiduePlatform

@Test func diagnosticRejectsUnboundedServiceIdentity() async {
    let runner = DiagnosticProcessRunner()
    let result = await runner.run(.currentUserService(label: "../../system"))
    #expect(result.failure == .invalidRequest)
    #expect(result.exitCode == nil)
}
@Test func diagnosticCapturesReadOnlyCommand() async {
    let result = await DiagnosticProcessRunner().run(.operatingSystemVersion)
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("ProductVersion"))
    #expect(!result.outputTruncated)
}
@Test func diagnosticBoundsOutputAndTerminatesChild() async {
    let result = await DiagnosticProcessRunner().runTestCommand(path: "/usr/bin/yes", arguments: [], timeout: 2, maximumBytes: 100)
    #expect(result.outputTruncated)
    #expect(result.stdout.utf8.count <= 100)
    #expect(result.failure == .outputLimit)
}
@Test func diagnosticTimeoutAndCancellationAreDistinct() async throws {
    let timed = await DiagnosticProcessRunner().runTestCommand(path: "/bin/sleep", arguments: ["5"], timeout: 0.05, maximumBytes: 100)
    #expect(timed.failure == .timedOut)
    let task = Task { await DiagnosticProcessRunner().runTestCommand(path: "/bin/sleep", arguments: ["5"], timeout: 10, maximumBytes: 100) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    let cancelled = await task.value
    #expect(cancelled.failure == .cancelled)
}
@Test func diagnosticKeepsStderrExitFailureAndStdoutSeparate() async {
    let result = await DiagnosticProcessRunner().runTestCommand(path: "/bin/ls", arguments: ["-d", "/", "/nonexistent-residueguard-test-path"], timeout: 2, maximumBytes: 2048)
    #expect(result.exitCode != 0)
    #expect(result.failure == nil)
    #expect(result.stdout.contains("/"))
    #expect(result.stderr.contains("No such file"))
}
@Test func diagnosticLaunchFailureIsNotEmptySuccess() async {
    let result = await DiagnosticProcessRunner().runTestCommand(path: "/nonexistent-residueguard-test-tool", arguments: [], timeout: 1, maximumBytes: 100)
    #expect(result.failure == .launchFailed)
    #expect(result.exitCode == nil)
}

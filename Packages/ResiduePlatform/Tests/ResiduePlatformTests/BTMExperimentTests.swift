import Testing
@testable import ResiduePlatform

@Test func btmGuardsNeverCapture() async {
    for (args, model, uid, major, minor, patch, build) in [
        (["dumpbtm"], "VirtualMac2,1", UInt32(501), 27, 0, 0, "26A428"),
        ([], "Mac17,2", 501, 27, 0, 0, "26A428"),
        ([], "VirtualMac2,1", 0, 27, 0, 0, "26A428"),
        ([], "VirtualMac2,1", 501, 26, 0, 0, "26A428"),
        ([], "VirtualMac2,1", 501, 27, 1, 0, "26A428"),
        ([], "VirtualMac2,1", 501, 27, 0, 1, "26A428"),
        ([], "VirtualMac2,1", 501, 27, 0, 0, "unknown")
    ] {
        let report = await BTMExperiment.collect(arguments: args, model: model, uid: uid, major: major,
                                                 minor: minor, patch: patch, build: build) {
            Issue.record("Rejected gate must not invoke capture")
            return .init(stdout: "unexpected", stderr: "", exitCode: 0, failure: nil, outputTruncated: false)
        }
        #expect(report.refusal != nil)
        #expect(report.elapsedSeconds == 0 && report.timeoutSeconds == 30)
        #expect(report.stdoutByteLimit == 1_048_576 && report.stderrByteLimit == 16_384)
        #expect(report.stdout.isEmpty && report.exitCode == nil && report.scopeUnverified)
    }
}

@Test func btmCapturePreservesFailureWithoutParsing() async {
    for failure in [DiagnosticFailure.cancelled, .timedOut, .outputLimit] {
        let report = await BTMExperiment.collect(arguments: [], model: "VirtualMac2,1", uid: 501,
                                                 major: 27, minor: 0, patch: 0, build: "26A428") {
            .init(stdout: "unparsed", stderr: "diagnostic", exitCode: 9, failure: failure, outputTruncated: true)
        }
        #expect(report.failure == failure.rawValue && report.exitCode == 9)
        #expect(report.elapsedSeconds >= 0 && report.timeoutSeconds == 30)
        #expect(report.stdout == "unparsed" && report.outputTruncated && report.experimentOnly)
    }
}

@Test func independentDiagnosticStreamLimits() async {
    let runner = DiagnosticProcessRunner()
    let success = await runner.runCommand(path: "/bin/sh", arguments: ["-c", "printf 123456789; printf err >&2"],
                                          timeout: 2, maximumBytes: 9, stderrMaximumBytes: 3)
    #expect(success.failure == nil && success.stdout == "123456789" && success.stderr == "err")
    let limited = await runner.runCommand(path: "/bin/sh", arguments: ["-c", "printf 123456789; printf error >&2"],
                                          timeout: 2, maximumBytes: 9, stderrMaximumBytes: 3)
    #expect(limited.failure == .outputLimit && limited.outputTruncated)
    #expect(limited.stdout == "123456789" && limited.stderr == "err")
}

@Test func btmMeasuresCaptureElapsedTime() async {
    let report = await BTMExperiment.collect(arguments: [], model: "VirtualMac2,1", uid: 501,
                                             major: 27, minor: 0, patch: 0, build: "26A428") {
        try? await Task.sleep(for: .milliseconds(20))
        return .init(stdout: "", stderr: "", exitCode: 15, failure: .timedOut, outputTruncated: false)
    }
    #expect(report.elapsedSeconds >= 0.015)
    #expect(report.failure == "timedOut" && report.stdout.isEmpty && report.scopeUnverified)
}

import Foundation
import Darwin

/// Package-only experimental transport. Never a product enumeration capability.
package enum BTMExperiment {
    static let timeoutSeconds: TimeInterval = 30
    static let stdoutByteLimit = 1_048_576
    static let stderrByteLimit = 16_384
    package struct Report: Encodable, Sendable {
        package let timeoutSeconds = BTMExperiment.timeoutSeconds
        package let stdoutByteLimit = BTMExperiment.stdoutByteLimit
        package let stderrByteLimit = BTMExperiment.stderrByteLimit
        package let elapsedSeconds: TimeInterval
        package let experimentOnly = true
        package let scopeUnverified = true
        package let mutationAvailable = false
        package let refusal: String?
        package let stdout: String
        package let stderr: String
        package let exitCode: Int32?
        package let failure: String?
        package let outputTruncated: Bool
    }

    package static func run(arguments: [String]) async -> Report {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return await collect(arguments: arguments, model: hardwareModel(), uid: getuid(),
                             major: version.majorVersion, minor: version.minorVersion,
                             patch: version.patchVersion, build: SafeFiles.osBuild) {
            // System-protected fixed executable; no PATH resolution or caller-supplied arguments.
            var info = stat()
            guard lstat("/usr/bin/sfltool", &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == 0,
                  (info.st_mode & 0o022) == 0, (info.st_mode & 0o111) != 0 else {
                return .init(stdout: "", stderr: "Fixed system tool unavailable", exitCode: nil,
                             failure: .launchFailed, outputTruncated: false)
            }
            return await DiagnosticProcessRunner().runCommand(path: "/usr/bin/sfltool", arguments: ["dumpbtm"],
                                                       timeout: timeoutSeconds, maximumBytes: stdoutByteLimit, stderrMaximumBytes: stderrByteLimit)
        }
    }

    static func collect(arguments: [String], model: String, uid: UInt32, major: Int, minor: Int,
                        patch: Int, build: String,
                        capture: @Sendable () async -> DiagnosticResult) async -> Report {
        let refusal: String?
        if !arguments.isEmpty { refusal = "zeroArgumentsRequired" }
        else if !model.hasPrefix("VirtualMac") || uid == 0 { refusal = "nonrootVMRequired" }
        else if major != 27 || minor != 0 || patch != 0 || build != "26A428" { refusal = "unsupportedOSBuild" }
        else { refusal = nil }
        if let refusal {
            return Report(elapsedSeconds: 0, refusal: refusal, stdout: "", stderr: "", exitCode: nil, failure: nil, outputTruncated: false)
        }
        let started = ProcessInfo.processInfo.systemUptime
        let result = await capture()
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - started)
        return Report(elapsedSeconds: elapsed, refusal: nil, stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode,
                      failure: result.failure?.rawValue, outputTruncated: result.outputTruncated)
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size <= 256 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}

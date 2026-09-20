import Foundation
import Darwin

/// Only fixed, read-only diagnostic commands; no shell or caller-supplied executable.
public enum ReadOnlyDiagnostic: Sendable {
    case operatingSystemVersion
    case currentUserService(label: String)
}
public enum DiagnosticFailure: String, Sendable { case invalidRequest, launchFailed, timedOut, cancelled, outputLimit, ioFailure }
public struct DiagnosticResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32?
    public let failure: DiagnosticFailure?
    public let outputTruncated: Bool
}
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
public struct DiagnosticProcessRunner: Sendable {
    public init() {}
    public func run(_ request: ReadOnlyDiagnostic) async -> DiagnosticResult {
        switch request {
        case .operatingSystemVersion:
            return await runCommand(path: "/usr/bin/sw_vers", arguments: [], timeout: 3, maximumBytes: 16_384)
        case .currentUserService(let label):
            guard !label.isEmpty, label.utf8.count <= 255,
                  label.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-" )).contains($0) }),
                  !label.hasPrefix("-"), !label.contains("..") else {
                return .init(stdout: "", stderr: "", exitCode: nil, failure: .invalidRequest, outputTruncated: false)
            }
            return await runCommand(path: "/bin/launchctl", arguments: ["print", "gui/\(getuid())/\(label)"], timeout: 3, maximumBytes: 256_000)
        }
    }
    // Internal test seam. Not exported in the product API, and never fed inspected records.
    func runTestCommand(path: String, arguments: [String], timeout: TimeInterval, maximumBytes: Int) async -> DiagnosticResult {
        await runCommand(path: path, arguments: arguments, timeout: timeout, maximumBytes: maximumBytes)
    }
    func runCommand(path: String, arguments: [String], timeout: TimeInterval, maximumBytes: Int, stderrMaximumBytes: Int? = nil) async -> DiagnosticResult {
        let flag = CancellationFlag()
        return await withTaskCancellationHandler {
            if Task.isCancelled { flag.cancel() }
            return await Task.detached(priority: .utility) {
                Self.capture(path: path, arguments: arguments, timeout: timeout, maximumBytes: maximumBytes, stderrMaximumBytes: stderrMaximumBytes ?? maximumBytes, flag: flag)
            }.value
        } onCancel: { flag.cancel() }
    }
    private static func capture(path: String, arguments: [String], timeout: TimeInterval, maximumBytes: Int, stderrMaximumBytes: Int, flag: CancellationFlag) -> DiagnosticResult {
        guard !flag.isCancelled else { return .init(stdout: "", stderr: "", exitCode: nil, failure: .cancelled, outputTruncated: false) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: path); child.arguments = arguments
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        child.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        child.standardOutput = out; child.standardError = err
        let outputs = [out.fileHandleForReading, err.fileHandleForReading]
        defer { for handle in outputs { try? handle.close() } }
        do { try child.run() } catch {
            return .init(stdout: "", stderr: "Diagnostic launch unavailable", exitCode: nil, failure: .launchFailed, outputTruncated: false)
        }
        try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
        var data = [Data(), Data()]
        var closed = [false, false]
        var failure: DiagnosticFailure?
        var truncated = false
        for (index, handle) in outputs.enumerated() {
            let fd = handle.fileDescriptor
            let flags = fcntl(fd, F_GETFL)
            if flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 {
                failure = .ioFailure
                closed[index] = true // Never read a pipe that may still be blocking.
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var terminatedAt: TimeInterval?
        var exitObservedAt: TimeInterval?
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if flag.isCancelled && failure == nil { failure = .cancelled }
            if now - started >= timeout && failure == nil { failure = .timedOut }
            if failure != nil && terminatedAt == nil {
                if child.isRunning { child.terminate() }
                terminatedAt = now
            }
            if let terminatedAt, now - terminatedAt > 0.25, child.isRunning { kill(child.processIdentifier, SIGKILL) }
            for index in 0..<2 where !closed[index] {
                // Fair bounded drain of each pipe prevents stderr starvation.
                for _ in 0..<16 {
                    let count = read(outputs[index].fileDescriptor, &buffer, buffer.count)
                    if count > 0 {
                        let room = max(0, (index == 0 ? maximumBytes : stderrMaximumBytes) - data[index].count)
                        data[index].append(contentsOf: buffer.prefix(min(room, count)))
                        if count > room { truncated = true; if failure == nil { failure = .outputLimit } }
                    } else if count == 0 { closed[index] = true; break }
                    else if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    else if errno == EINTR { continue }
                    else { closed[index] = true; if failure == nil { failure = .ioFailure }; break }
                }
            }
            if !child.isRunning {
                if exitObservedAt == nil { exitObservedAt = now }
                if closed.allSatisfy({ $0 }) { break }
                // A descendant holding a pipe cannot keep the collector alive forever.
                if let exitObservedAt, now - exitObservedAt > 0.25 {
                    truncated = true; if failure == nil { failure = .ioFailure }; break
                }
            }
            usleep(5_000)
        }
        return .init(stdout: String(decoding: data[0], as: UTF8.self), stderr: String(decoding: data[1], as: UTF8.self),
                     exitCode: child.terminationStatus, failure: failure, outputTruncated: truncated)
    }
}

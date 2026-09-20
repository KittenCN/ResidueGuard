import Foundation
import Darwin
import CryptoKit

struct OwnedBootoutCapture: Codable {
    enum Failure: String, Codable { case invalidRequest, launchFailed, timedOut, cancelled, outputLimit, ioFailure }
    let stdout: String
    let stderr: String
    let exitCode: Int32?
    let failure: Failure?
    let outputTruncated: Bool
    let launched: Bool
    let elapsed: TimeInterval
    let terminationReason: Int?
    let stdoutSHA256: String
    let stderrSHA256: String
    init(stdout: String, stderr: String, exitCode: Int32?, failure: Failure?, outputTruncated: Bool,
         launched: Bool = false, elapsed: TimeInterval = 0, terminationReason: Int? = nil) {
        self.init(stdoutData: Data(stdout.utf8), stderrData: Data(stderr.utf8), exitCode: exitCode,
                  failure: failure, outputTruncated: outputTruncated, launched: launched,
                  elapsed: elapsed, terminationReason: terminationReason)
    }
    init(stdoutData: Data, stderrData: Data, exitCode: Int32?, failure: Failure?, outputTruncated: Bool,
         launched: Bool = false, elapsed: TimeInterval = 0, terminationReason: Int? = nil) {
        self.stdout = String(decoding: stdoutData, as: UTF8.self)
        self.stderr = String(decoding: stderrData, as: UTF8.self)
        self.exitCode = exitCode; self.failure = failure
        self.outputTruncated = outputTruncated; self.launched = launched; self.elapsed = elapsed
        self.terminationReason = terminationReason
        stdoutSHA256 = SHA256.hash(data: stdoutData).map { String(format: "%02x", $0) }.joined()
        stderrSHA256 = SHA256.hash(data: stderrData).map { String(format: "%02x", $0) }.joined()
    }
}
private final class BootoutCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// Module-internal implementation accepts only two fixed operations. No command/path injection.
enum OwnedBootoutTransport {
    enum Operation: String { case bootout, print }
    static func run(_ operation: Operation, finalCheck: () throws -> Void = {}) async -> OwnedBootoutCapture {
        let flag = BootoutCancellationFlag()
        return await withTaskCancellationHandler {
            if Task.isCancelled { flag.cancel() }
            return Self.capture(operation, flag: flag, finalCheck: finalCheck)
        } onCancel: { flag.cancel() }
    }
    private static func capture(_ operation: Operation, flag: BootoutCancellationFlag, finalCheck: () throws -> Void) -> OwnedBootoutCapture {
        guard !flag.isCancelled else { return .init(stdout: "", stderr: "", exitCode: nil, failure: .cancelled, outputTruncated: false) }
        let startedAt = ProcessInfo.processInfo.systemUptime
        let timeout: TimeInterval = 5
        let maximumBytes = operation == .print ? 256_000 : 16_384
        let stderrMaximumBytes = 16_384
        let path = "/bin/launchctl"
        let arguments = [operation.rawValue, "gui/\(getuid())/example.residueguard.fixture.iso01"]
        do { try OwnedBootoutGate.verify() } catch {
            return .init(stdout: "", stderr: "", exitCode: nil, failure: .invalidRequest, outputTruncated: false)
        }
        var tool = stat()
        guard lstat(path, &tool) == 0, tool.st_mode & S_IFMT == S_IFREG, tool.st_uid == 0, tool.st_mode & 0o022 == 0 else {
            return .init(stdout: "", stderr: "", exitCode: nil, failure: .launchFailed, outputTruncated: false)
        }
        guard !flag.isCancelled else { return .init(stdout: "", stderr: "", exitCode: nil, failure: .cancelled, outputTruncated: false) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: path); child.arguments = arguments
        child.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        child.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        child.standardOutput = out; child.standardError = err
        let outputs = [out.fileHandleForReading, err.fileHandleForReading]
        defer { for handle in outputs { try? handle.close() } }
        do { try finalCheck() } catch {
            return .init(stdout: "", stderr: "Final identity or expiry check refused", exitCode: nil, failure: .invalidRequest, outputTruncated: false)
        }
        guard !flag.isCancelled else { return .init(stdout: "", stderr: "", exitCode: nil, failure: .cancelled, outputTruncated: false) }
        do { try child.run() } catch {
            return .init(stdout: "", stderr: "Diagnostic launch unavailable", exitCode: nil, failure: .launchFailed, outputTruncated: false)
        }
        try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
        var data = [Data(), Data()]
        var closed = [false, false]
        var failure: OwnedBootoutCapture.Failure?
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
        return .init(stdoutData: data[0], stderrData: data[1],
                     exitCode: child.terminationStatus, failure: failure, outputTruncated: truncated, launched: true,
                     elapsed: ProcessInfo.processInfo.systemUptime - startedAt, terminationReason: child.terminationReason.rawValue)
    }
}

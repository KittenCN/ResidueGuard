import Foundation
import Darwin

/// Explicit per-service opt-in. Does not enumerate domains, change sandbox grants,
/// prove ownership, or enable a mutation capability.
public struct LaunchRuntimeCollector: Sendable {
    public enum Configuration: Sendable {
        case disabled
        case exactCurrentUserService(profile: String)
    }
    private let configuration: Configuration
    private let osMajor: Int
    private let osBuild: String
    private let userID: UInt32
    private let run: @Sendable (ReadOnlyDiagnostic) async -> DiagnosticResult

    public init(configuration: Configuration = .disabled) {
        self.init(configuration: configuration,
                  osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                  osBuild: SafeFiles.osBuild, userID: getuid(),
                  run: { await DiagnosticProcessRunner().run($0) })
    }

    // Internal fixture seam: callers cannot supply a fake OS profile or alternate runner.
    init(configuration: Configuration, osMajor: Int, osBuild: String, userID: UInt32,
         run: @escaping @Sendable (ReadOnlyDiagnostic) async -> DiagnosticResult) {
        self.configuration = configuration; self.osMajor = osMajor
        self.osBuild = osBuild; self.userID = userID; self.run = run
    }

    public func collect(expected: LaunchRuntimeIdentity, generation: String) async -> LaunchRuntimeObservation {
        let profile: String
        switch configuration {
        case .disabled: profile = "disabled"
        case .exactCurrentUserService(let requested): profile = requested
        }
        let result: DiagnosticResult
        if Task.isCancelled {
            result = .init(stdout: "", stderr: "", exitCode: nil, failure: .cancelled, outputTruncated: false)
        } else if profile != LaunchRuntimeParser.profile || osMajor != 27 || osBuild != "26A428" {
            result = .init(stdout: "", stderr: "", exitCode: nil, failure: .invalidRequest, outputTruncated: false)
        } else if userID == 0 || expected.userID != userID || !Self.valid(expected) {
            result = .init(stdout: "", stderr: "", exitCode: nil, failure: .invalidRequest, outputTruncated: false)
        } else {
            let captured = await run(.currentUserService(label: expected.label))
            // A runner finishing concurrently with cancellation cannot yield a known state.
            result = Task.isCancelled
                ? .init(stdout: "", stderr: "", exitCode: nil, failure: .cancelled, outputTruncated: false)
                : captured
        }
        return LaunchRuntimeParser().parse(result, expected: expected, osMajor: osMajor,
                                           osBuild: osBuild, profile: profile,
                                           generation: generation, observedAt: Date())
    }

    private static func valid(_ identity: LaunchRuntimeIdentity) -> Bool {
        let label = identity.label
        guard !label.isEmpty, label.utf8.count <= 255, !label.hasPrefix("-"), !label.contains(".."),
              label.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }) else { return false }
        for path in [identity.sourcePath, identity.program] {
            guard path.hasPrefix("/"), path.utf8.count <= 4096,
                  !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  URL(fileURLWithPath: path).standardizedFileURL.path == path,
                  SafeFiles.allowedUserPath(path), !SafeFiles.isExternalVolumePath(path), !SafeFiles.isTrashPath(path) else { return false }
        }
        let source = URL(fileURLWithPath: identity.sourcePath)
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path,
                     "/Library/LaunchAgents"]
        return source.pathExtension == "plist" && roots.contains(source.deletingLastPathComponent().path)
    }
}

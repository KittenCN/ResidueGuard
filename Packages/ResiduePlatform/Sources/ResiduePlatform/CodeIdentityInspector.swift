import Foundation
import Security
import Darwin

public struct CodeIdentityObservation: Sendable {
    public enum Status: String, Sendable { case metadataPresentUnverified, unsigned, unavailable, cancelled }
    public let status: Status
    public let signingIdentifier: String?
    public let teamID: String?
    public let designatedRequirement: String?
    public let diagnostic: String
    public let observedAt: Date
}

/// Static, read-only signature metadata. Does not execute code, validate trust or authorize ownership.
/// Security.framework calls are synchronous and offer no cancellation/timeout guarantee; each scan
/// limits their count. No recursive resource validation or network access flag is requested.
public struct CodeIdentityInspector: Sendable {
    public init() {}
    public func inspect(application: URL) -> CodeIdentityObservation {
        let time = Date()
        func result(_ status: CodeIdentityObservation.Status, _ diagnostic: String) -> CodeIdentityObservation {
            CodeIdentityObservation(status: status, signingIdentifier: nil, teamID: nil, designatedRequirement: nil, diagnostic: diagnostic, observedAt: time)
        }
        if Task.isCancelled { return result(.cancelled, "cancelled") }
        guard SafeFiles.allowedUserPath(application.path), !application.path.hasPrefix("/Volumes/") else { return result(.unavailable, "scopeNotAuthorized") }
        do {
            let root = try SafeFiles.descriptor(application, directory: true); defer { close(root) }
            var before = stat()
            guard fstat(root, &before) == 0 else { return result(.unavailable, "bundleIdentityUnavailable") }
            let info = try SafeFiles.read(application.appendingPathComponent("Contents/Info.plist"), limit: 1_048_576)
            guard let plist = try PropertyListSerialization.propertyList(from: info, options: [], format: nil) as? [String: Any],
                  let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty,
                  executable.utf8.count <= 255, !executable.contains("/"), executable != ".", executable != ".." else { return result(.unavailable, "invalidExecutableIdentity") }
            let executableURL = application.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
            let fd = try SafeFiles.descriptor(executableURL); defer { close(fd) }
            var executableBefore = stat()
            guard fstat(fd, &executableBefore) == 0, (executableBefore.st_mode & S_IFMT) == S_IFREG,
                  executableBefore.st_size <= 268_435_456 else { return result(.unavailable, "executableTypeOrSizeLimit") }
            // Refuse a redirected signature envelope if present; ENOENT permits unsigned bundles.
            do {
                let signature = try SafeFiles.descriptor(application.appendingPathComponent("Contents/_CodeSignature/CodeResources"))
                defer { close(signature) }
                var envelope = stat()
                guard fstat(signature, &envelope) == 0, (envelope.st_mode & S_IFMT) == S_IFREG,
                      envelope.st_size <= 4_194_304 else { return result(.unavailable, "signatureEnvelopeLimit") }
            } catch SafeFiles.Failure.posix(let code) where code == ENOENT { }
            if Task.isCancelled { return result(.cancelled, "cancelled") }
            var code: SecStaticCode?
            let created = SecStaticCodeCreateWithPath(application as CFURL, SecCSFlags(rawValue: 0), &code)
            guard created == errSecSuccess, let code else { return result(created == errSecCSUnsigned ? .unsigned : .unavailable, "SecStaticCodeCreateWithPath:\(created)") }
            var raw: CFDictionary?
            let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSSkipResourceDirectory)
            let copied = SecCodeCopySigningInformation(code, flags, &raw)
            guard copied == errSecSuccess, let raw else { return result(copied == errSecCSUnsigned ? .unsigned : .unavailable, "SecCodeCopySigningInformation:\(copied)") }
            var after = stat(), executableAfter = stat()
            let pathRoot = try SafeFiles.descriptor(application, directory: true); defer { close(pathRoot) }
            let pathExecutable = try SafeFiles.descriptor(executableURL); defer { close(pathExecutable) }
            guard fstat(pathRoot, &after) == 0, fstat(pathExecutable, &executableAfter) == 0,
                  before.st_ino == after.st_ino, before.st_dev == after.st_dev,
                  executableBefore.st_ino == executableAfter.st_ino, executableBefore.st_dev == executableAfter.st_dev,
                  executableBefore.st_size == executableAfter.st_size,
                  executableBefore.st_mtimespec.tv_sec == executableAfter.st_mtimespec.tv_sec,
                  executableBefore.st_mtimespec.tv_nsec == executableAfter.st_mtimespec.tv_nsec else { return result(.unavailable, "identityChangedDuringInspection") }
            if Task.isCancelled { return result(.cancelled, "cancelled") }
            let dictionary = raw as NSDictionary
            guard let identifier = dictionary[kSecCodeInfoIdentifier] as? String else { return result(.unsigned, "noSigningIdentifier") }
            guard identifier.utf8.count <= 4096 else { return result(.unavailable, "signingIdentifierLimit") }
            let team = dictionary[kSecCodeInfoTeamIdentifier] as? String
            var requirementText: String?
            if let value = dictionary[kSecCodeInfoDesignatedRequirement] {
                let requirement = value as! SecRequirement
                var text: CFString?
                let status = SecRequirementCopyString(requirement, SecCSFlags(rawValue: 0), &text)
                if status == errSecSuccess, let text, (text as String).utf8.count <= 16384 { requirementText = text as String }
            }
            return CodeIdentityObservation(status: .metadataPresentUnverified, signingIdentifier: identifier, teamID: team.flatMap { $0.utf8.count <= 255 ? $0 : nil }, designatedRequirement: requirementText, diagnostic: "staticMetadataOnly; signatureValidityAndTrustNotVerified", observedAt: time)
        } catch { return result(.unavailable, SafeFiles.diagnostic(error)) }
    }
}

import Foundation
import Darwin
import ResidueBackup
import ResiduePlatform

package enum OwnedBootoutEnvironmentError: Error { case unsupported }

enum OwnedBootoutError: Error { case refused, changed, storage, stopped }

struct OwnedBootoutRuntimeEvidence: Encodable {
    let generation: String
    let providerID = "launchd.runtime"
    let scope: String
    let nativeLabel = "example.residueguard.fixture.iso01"
    let osBuild = "26A428"
    let profile = LaunchRuntimeParser.profile
    let observedAt: Date
    let state: String
    let coverage: String
    let metadata: [String: String]
    init(_ observation: LaunchRuntimeObservation) {
        generation = observation.provenance.generation
        scope = "gui/\(getuid())"
        observedAt = observation.provenance.observedAt
        state = observation.state.rawValue; coverage = observation.coverage.state.rawValue
        metadata = observation.provenance.rawMetadata
    }
}

struct OwnedBootoutIntent: Encodable {
    let version = 1
    let profile = "owned-iso01-bootout-v1"
    let authorizesReplay = false
    let attempt: UUID
    let createdAt: Date
    let expiresAt: Date
    let userID: UInt32
    let scope: String
    let label = "example.residueguard.fixture.iso01"
    let osBuild = "26A428"
    let receipt: BackupReceipt
    let program: SourceFingerprint
    let backupRootID: UUID
    let backupRootDevice: Int32
    let backupRootInode: UInt64
    let sourceRootDevice: Int32
    let sourceRootInode: UInt64
    let contentSHA256: String
    let metadataSHA256: String
    let manifestSHA256: String
    let runtime: OwnedBootoutRuntimeEvidence
}
struct OwnedBootoutOutcome: Encodable {
    let attempt: UUID
    let observedAt: Date
    let disposition: String
    let capture: OwnedBootoutCapture?
}
struct OwnedBootoutPostObservation: Encodable {
    let attempt: UUID
    let generation = UUID()
    let providerID = "launchd.runtime"
    let scope = "gui/\(getuid())"
    let nativeLabel = "example.residueguard.fixture.iso01"
    let osBuild = "26A428"
    let profile = "unvalidated-postbootout-capture-v1"
    let state = "unknown"
    let coverage = "partial"
    let observedAt: Date
    let runtime: OwnedBootoutRuntimeEvidence?
    let capture: OwnedBootoutCapture?
    let filesStillMatch: Bool
    let absenceProven = false
}

extension QuarantineStore {
    /// Dedicated VM experiment only. Never called by product cleanup or recovery.
    public static func runISO01VirtualMachineBootoutProbe() async throws -> String {
        try OwnedBootoutGate.verify()
        guard !Task.isCancelled else { throw OwnedBootoutError.refused }
        let context = try OwnedFixtureLabContext.createISO01()
        let expected = LaunchRuntimeIdentity(userID: getuid(), label: "example.residueguard.fixture.iso01",
            sourcePath: context.home + "/Library/LaunchAgents/" + context.sourceName,
            program: context.home + "/Library/ResidueGuard-VM-ISO01/fixture")
        let collector = LaunchRuntimeCollector(configuration: .exactCurrentUserService(profile: LaunchRuntimeParser.profile))
        let before = await collector.collect(expected: expected, generation: UUID().uuidString)
        guard before.state == .registeredNotRunning, !Task.isCancelled else { throw OwnedBootoutError.refused }
        let receipt = try context.backup.prepare(name: context.sourceName, expected: context.fingerprint, planID: UUID())
        let audit = try context.backup.inspectAuditEvidence(receipt: receipt)
        var sourceRoot = stat()
        guard fstat(context.sourceFD, &sourceRoot) == 0 else { throw OwnedBootoutError.changed }
        func verifySourceRoot() throws {
            var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard current >= 0 else { throw OwnedBootoutError.changed }
            for component in (context.home + "/Library/LaunchAgents").split(separator: "/") {
                let next = openat(current, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                close(current)
                guard next >= 0 else { throw OwnedBootoutError.changed }
                current = next
            }
            defer { close(current) }
            var info = stat()
            guard fstat(current, &info) == 0, info.st_dev == sourceRoot.st_dev,
                  info.st_ino == sourceRoot.st_ino else { throw OwnedBootoutError.changed }
        }
        let attempt = UUID(), created = Date(), uptime = ProcessInfo.processInfo.systemUptime
        let expires = created.addingTimeInterval(120)
        let log = try OwnedBootoutLog(directoryFD: context.labFD, attempt: attempt)
        let intent = OwnedBootoutIntent(attempt: attempt, createdAt: created, expiresAt: expires,
            userID: getuid(), scope: expected.target, receipt: receipt, program: context.programFingerprint,
            backupRootID: audit.root.rootID, backupRootDevice: audit.root.device, backupRootInode: audit.root.inode,
            sourceRootDevice: sourceRoot.st_dev, sourceRootInode: sourceRoot.st_ino,
            contentSHA256: audit.contentSHA256, metadataSHA256: audit.metadataSHA256,
            manifestSHA256: audit.manifestSHA256, runtime: .init(before))
        _ = try await OwnedBootoutSequence.execute(prepare: { try log.append(.intent, intent) }, fresh: {
            let fresh = await collector.collect(expected: expected, generation: UUID().uuidString)
            try log.append(.preflight, OwnedBootoutRuntimeEvidence(fresh))
            guard fresh.state == .registeredNotRunning else { throw OwnedBootoutError.changed }
        }, issue: {
            await OwnedBootoutTransport.run(.bootout, finalCheck: {
            // Last await is above; all final file/program/backup checks are synchronous.
            try verifySourceRoot()
            try context.verifyProgram()
            guard try context.backup.inspect(name: context.sourceName) == context.fingerprint else { throw OwnedBootoutError.changed }
            let current = try context.backup.inspectAuditEvidence(receipt: receipt)
            guard current.root == audit.root, current.manifestSHA256 == audit.manifestSHA256,
                  current.metadataSHA256 == audit.metadataSHA256, current.contentSHA256 == audit.contentSHA256,
                  Date() >= created, Date() <= expires, ProcessInfo.processInfo.systemUptime - uptime <= 120,
                  !Task.isCancelled else { throw OwnedBootoutError.changed }
            try OwnedBootoutGate.verify()
            })
        }, record: { capture in
            try log.append(.outcome, OwnedBootoutOutcome(attempt: attempt, observedAt: Date(),
                disposition: capture.map { $0.launched ? "issuedOutcomeRecorded" : "notIssued" } ?? "notIssuedPreflightFailed",
                capture: capture))
        })
        let post = await OwnedBootoutTransport.run(.print)
        // Until a separately reviewed absence profile exists, all postflight results are raw/unknown.
        let filesMatch = (try? verifySourceRoot()) != nil && (try? context.backup.inspect(name: context.sourceName)) == context.fingerprint
            && (try? context.verifyProgram()) != nil
        try log.append(.observation, OwnedBootoutPostObservation(attempt: attempt, observedAt: Date(),
            runtime: nil, capture: post, filesStillMatch: filesMatch))
        let reopened = try OwnedBootoutLog(directoryFD: context.labFD, attempt: attempt, readOnly: true)
        guard try reopened.readAll().count == 4 else { throw OwnedBootoutError.storage }
        guard filesMatch else { throw OwnedBootoutError.changed }
        return "experimentOnly=true attempt=\(attempt.uuidString) bootoutExit=0 postRuntime=unknown absenceProven=false filesUnchanged=true productionGate=disabled automaticBootstrap=false"
    }
}

enum OwnedBootoutGate {
    static func accepts(model: String, uid: UInt32, euid: UInt32, major: Int, minor: Int, patch: Int, build: String) -> Bool {
        model.hasPrefix("VirtualMac") && uid > 0 && uid == euid && major == 27 && minor == 0 && patch == 0 && build == "26A428"
    }
    static func verify() throws {
        func read(_ key: String) -> String {
            var size = 0
            guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size <= 256 else { return "" }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "" }
            return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard accepts(model: read("hw.model"), uid: getuid(), euid: geteuid(), major: os.majorVersion,
                      minor: os.minorVersion, patch: os.patchVersion, build: read("kern.osversion")) else { throw OwnedBootoutEnvironmentError.unsupported }
    }
}

/// Internal orchestration seam: tests inject observations, never executable paths.
enum OwnedBootoutSequence {
    static func execute(prepare: () throws -> Void, fresh: () async throws -> Void,
                        issue: () async -> OwnedBootoutCapture,
                        record: (OwnedBootoutCapture?) throws -> Void) async throws -> OwnedBootoutCapture {
        try prepare()
        do {
            guard !Task.isCancelled else { throw OwnedBootoutError.stopped }
            try await fresh()
            guard !Task.isCancelled else { throw OwnedBootoutError.stopped }
        } catch {
            try record(nil)
            throw OwnedBootoutError.stopped
        }
        let result = await issue()
        // Record even if caller cancellation arrived after dispatch; never compensate.
        try record(result)
        guard result.launched, result.failure == nil, result.exitCode == 0, !Task.isCancelled else {
            throw OwnedBootoutError.stopped
        }
        return result
    }
}

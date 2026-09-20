import Foundation
import ResidueCore
import Darwin

/// Each call owns one detached, bounded read worker; cancellation produces explicit partial coverage.
public actor ScanService {
    private let configuration: ScanConfiguration
    private var worker: Task<ScanSnapshot, Never>?
    public init(configuration: ScanConfiguration = .currentUser) { self.configuration = configuration }
    public func cancel() { worker?.cancel() }
    public func scan() async -> ScanSnapshot {
        if let worker { return await worker.value }
        let configuration = self.configuration
        let task = Task.detached(priority: .utility) { Self.collect(configuration) }
        worker = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        worker = nil
        return result
    }
    private nonisolated static func collect(_ config: ScanConfiguration) -> ScanSnapshot {
        let generation = UUID().uuidString, start = Date()
        let os = SafeFiles.osBuild
        var rows: [ScanRow] = [], coverage: [ScanCoverage] = []
        var applications: [ApplicationInstance] = []
        var totalBytes = 0
        var signatureCount = 0
        for root in config.applicationRoots {
            var parsed = 0, failures: [String] = [], skipped: [String] = []
            do {
                guard SafeFiles.allowedUserPath(root.path) else { throw SafeFiles.Failure.invalidPath }
                let entries = try SafeFiles.list(root, limit: config.maximumEntries)
                if entries.truncated { skipped.append("entryLimit") }
                for name in entries.names where name.hasSuffix(".app") {
                    if Task.isCancelled { break }
                    if applications.count >= config.maximumEntries { skipped.append("applicationRecordLimit"); break }
                    do {
                        try Task.checkCancellation()
                        let info = try SafeFiles.read(root.appendingPathComponent(name).appendingPathComponent("Contents/Info.plist"), limit: config.maximumFileBytes)
                        totalBytes += info.count
                        guard totalBytes <= 16_777_216 else { skipped.append("scanByteLimit"); break }
                        guard let plist = try PropertyListSerialization.propertyList(from: info, options: [], format: nil) as? [String: Any], let id = plist["CFBundleIdentifier"] as? String, !id.isEmpty, id.utf8.count <= 255 else { failures.append("invalidBundleInfo"); continue }
                        let appURL = root.appendingPathComponent(name)
                        let fd = try SafeFiles.descriptor(appURL, directory: true); defer { close(fd) }
                        var identity = stat()
                        guard fstat(fd, &identity) == 0 else { throw SafeFiles.Failure.posix(errno) }
                        let signing: CodeIdentityObservation?
                        if signatureCount < 32 { signing = CodeIdentityInspector().inspect(application: appURL); signatureCount += 1 }
                        else { signing = nil; if !skipped.contains("signatureInspectionLimit") { skipped.append("signatureInspectionLimit") } }
                        applications.append(ApplicationInstance(generation: generation, signingIdentifier: signing?.signingIdentifier, bundleID: id, path: appURL.path, fileIdentity: String(identity.st_ino), volumeIdentity: String(identity.st_dev), signingStatus: signing?.status.rawValue ?? "unverified", teamID: signing?.teamID, designatedRequirement: signing?.designatedRequirement, signingDiagnostic: signing?.diagnostic ?? "signatureInspectionLimit", observedAt: start))
                        parsed += 1
                    } catch { failures.append(SafeFiles.diagnostic(error)) }
                }
            } catch { failures.append(SafeFiles.diagnostic(error)) }
            coverage.append(ScanCoverage(providerID: "applications.index", state: Task.isCancelled ? .cancelled : .partial, declaredRoots: [root.path], diagnostics: ["Top-level bundles only; signature validity, alternate installations and runtime not verified. Never deletion evidence."], osBuild: os, generation: generation, startedAt: start, completedAt: Date(), parsedCount: parsed, unparsedCount: failures.count, skippedAreas: skipped + ["nestedBundles", "signatureValidity", "otherVolumes"], errors: failures))
        }
        for root in config.launchRoots {
            var parsed = 0, failures: [String] = [], skipped: [String] = [], denied = false
            var rootRecords: [SourceRecord] = []
            do {
                guard SafeFiles.allowedUserPath(root.url.path) else { throw SafeFiles.Failure.invalidPath }
                let entries = try SafeFiles.list(root.url, limit: config.maximumEntries)
                if entries.truncated { skipped.append("entryLimit") }
                for name in entries.names where name.hasSuffix(".plist") {
                    if Task.isCancelled { break }
                    if rows.count + rootRecords.count >= config.maximumEntries { skipped.append("scanRecordLimit"); break }
                    do {
                        let url = root.url.appendingPathComponent(name)
                        let data = try SafeFiles.read(url, limit: config.maximumFileBytes)
                        totalBytes += data.count
                        guard totalBytes <= 16_777_216 else { skipped.append("scanByteLimit"); break }
                        let record = try LaunchConfigurationParser.parse(data, source: url, scope: root.scope, generation: generation, observedAt: start)
                        rootRecords.append(record); parsed += 1
                    } catch {
                        let diagnostic = SafeFiles.diagnostic(error)
                        failures.append(diagnostic)
                        rootRecords.append(SourceRecord(id: RecordIdentity(providerID: "launchd.configuration", scope: root.scope, nativeIdentity: "unparsed-v1:" + root.url.appendingPathComponent(name).path), category: "background", observedAt: start, generation: generation, sourceArtifact: root.url.appendingPathComponent(name).path, displayName: name, declaredAppIDs: [], targetReferences: [], rawMetadata: [:], parseWarnings: [diagnostic]))
                        if case SafeFiles.Failure.posix(let code) = error, code == EACCES || code == EPERM { denied = true }
                    }
                }
            } catch {
                failures.append(SafeFiles.diagnostic(error))
                if case SafeFiles.Failure.posix(let code) = error, code == EACCES || code == EPERM { denied = true }
            }
            let labels = Dictionary(grouping: rootRecords, by: { $0.displayName })
            for record in rootRecords {
                if Task.isCancelled { break }
                var evidence = ["Source plist read with bounded no-symlink traversal", "No runtime or ownership-complete verification"]
                var state: PresenceState = .unknown
                let duplicate = (labels[record.displayName]?.count ?? 0) > 1
                if duplicate { evidence.append("duplicateLabel") }
                if !record.parseWarnings.isEmpty { evidence.append(contentsOf: record.parseWarnings) }
                if !duplicate && record.parseWarnings.isEmpty, let path = record.targetReferences.first, path.hasPrefix("/") {
                    if SafeFiles.isExternalVolumePath(path) { state = .unknown; evidence.append("externalVolumeNotAuthorized; availabilityUnknown") }
                    else if SafeFiles.isTrashPath(path) { state = .inTrash }
                    else if !SafeFiles.allowedUserPath(path) { evidence.append("otherUserTargetNotInspected") }
                    else {
                        do {
                            let fd = try SafeFiles.descriptor(URL(fileURLWithPath: path)); defer { close(fd) }
                            var info = stat()
                            if fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, (info.st_mode & 0o111) != 0 { state = .present; evidence.append("directExecutablePresent; runtimeNotVerified") }
                        } catch SafeFiles.Failure.posix(let code) {
                            if code == EACCES || code == EPERM { state = .permissionDenied }
                            else if code == ENOENT { state = .suspectedOrphan }
                            evidence.append("targetPOSIX \(code); absenceNotProofOfRemoval")
                        } catch { evidence.append(SafeFiles.diagnostic(error)) }
                    }
                }
                rows.append(ScanRow(record: record, presence: state, capability: CapabilityDescriptor(profileID: "launch-plist-readonly-v1", state: .readOnly, testedOSBuilds: [], reason: "只读文件观察；运行时、签名、影响范围及清理能力尚未验证", operations: [.enumerate: .readOnly, .readStatus: .readOnly, .removeRegistration: .blockedByPolicy, .resetPermission: .blockedByPolicy, .restoreConfiguration: .blockedByPolicy]), evidence: evidence))
            }
            coverage.append(ScanCoverage(providerID: "launchd.configuration", state: Task.isCancelled ? .cancelled : (denied ? .permissionDenied : (failures.isEmpty && skipped.isEmpty ? .completeWithinDeclaredScope : .partial)), declaredRoots: [root.url.path], diagnostics: ["Only immediate plist files; configuration observation does not enumerate runtime registrations."], userScopes: [root.scope], osBuild: os, generation: generation, startedAt: start, completedAt: Date(), parsedCount: parsed, unparsedCount: failures.count, skippedAreas: skipped, errors: failures))
        }
        if config.rootsTruncated {
            coverage.append(ScanCoverage(providerID: "scan.limits", state: .partial, declaredRoots: [], diagnostics: ["At most 16 roots per source are inspected."], generation: generation, skippedAreas: ["rootLimit"]))
        }
        for provider in ["launchd.runtime", "backgroundTaskManagement", "loginItems", "permissions.TCC"] {
            coverage.append(ScanCoverage(providerID: provider, state: Task.isCancelled ? .cancelled : .unsupported, declaredRoots: [], diagnostics: ["未建立已验证来源 profile；不读取 TCC/BTM 数据库、不进行全量重置。"], osBuild: os, generation: generation, startedAt: start, completedAt: Date(), skippedAreas: ["entireProvider"]))
        }
        let graph = CandidateOwnershipGraphBuilder.build(records: rows.map(\.record),
            applications: applications.map(\.ownershipObservation), sourceCoverage: coverage,
            generation: generation, limits: .init(maximumRecords: config.maximumEntries,
                                                   maximumApplications: config.maximumEntries))
        return ScanSnapshot(generation: generation, observedAt: start, rows: rows, coverage: coverage,
                            applications: applications, ownershipGraph: graph)
    }
}

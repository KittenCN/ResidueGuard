import Foundation
import ResidueCore
import ResiduePlatform

extension WorkspaceStore {
    static func production() -> WorkspaceStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-synthetic-scan") {
            if ProcessInfo.processInfo.arguments.contains("--ui-snapshot-fixture") {
                let sequence = SyntheticComparisonSequence()
                let store = WorkspaceStore(scanner: WorkspaceScanner { configuration in await sequence.next(configuration) }, syntheticScan: true)
                store.configureSyntheticComparisonRoots()
                return store
            }
            let ownershipFixture = ProcessInfo.processInfo.arguments.contains("--ui-ownership-fixture")
            let slow = ProcessInfo.processInfo.arguments.contains("--ui-slow-scan")
            return WorkspaceStore(scanner: WorkspaceScanner { _ in
                if slow { try? await Task.sleep(for: .seconds(30)) }
                let cancelled = Task.isCancelled
                let generation = UUID().uuidString
                let now = Date()
                let record = SourceRecord(id: .init(providerID: "synthetic.scan", scope: "currentUser", nativeIdentity: "fixture-readonly"),
                    category: "launchConfiguration", observedAt: now, generation: generation,
                    sourceArtifact: "/Synthetic/LaunchAgents/readonly.plist", displayName: "合成扫描·只读项目",
                    declaredAppIDs: ownershipFixture ? ["org.residueguard.synthetic.duplicate"] : [], targetReferences: ["/Synthetic/tool"], rawMetadata: ["fixture": "synthetic-not-user-data"], parseWarnings: [])
                let row = ScanRow(record: record, presence: .unknown,
                    capability: .init(profileID: "synthetic-scan", state: .readOnly, testedOSBuilds: [], reason: "测试注入，不读取主机"), evidence: ["合成扫描来源"])
                let coverage: [ScanCoverage] = [.init(providerID: "synthetic.scan", state: cancelled ? .cancelled : .partial,
                    declaredRoots: ["/Synthetic"], diagnostics: ["测试注入；未读取真实系统"], generation: generation, parsedCount: cancelled ? 0 : 1)]
                let applications: [OwnershipApplicationObservation] = ownershipFixture && !cancelled ? (1...2).map { index in
                    .init(generation: generation, volumeIdentity: "synthetic-volume", fileIdentity: "synthetic-instance-\(index)",
                          path: "/Synthetic/Instance\(index).app", declaredBundleID: "org.residueguard.synthetic.duplicate", observedAt: now)
                } : []
                let graph = ownershipFixture ? CandidateOwnershipGraphBuilder.build(records: cancelled ? [] : [record],
                    applications: applications, sourceCoverage: coverage, generation: generation) : nil
                return ScanSnapshot(generation: generation, observedAt: now, rows: cancelled ? [] : [row],
                    coverage: coverage, ownershipGraph: graph)
            }, syntheticScan: true)
        }
        #endif
        return WorkspaceStore()
    }
}

#if DEBUG
private actor SyntheticComparisonSequence {
    private var count = 0
    func next(_ configuration: ScanConfiguration) -> ScanSnapshot {
        count += 1
        let partial = count == 2 && configuration.launchRoots.count != 1, generation = UUID().uuidString, now = Date()
        let record = SourceRecord(id: .init(providerID: "launchd.configuration", scope: "currentUser", nativeIdentity: "synthetic-comparison"),
            category: "launchConfiguration", observedAt: now, generation: generation,
            sourceArtifact: "/Synthetic/LaunchAgents/comparison.plist", displayName: "合成比较·固定项目",
            declaredAppIDs: [], targetReferences: [], rawMetadata: ["fixture": "synthetic-not-user-data"], parseWarnings: [])
        let includesSource = configuration.launchRoots.contains { $0.url.path == "/Synthetic/LaunchAgents" }
        let rows: [ScanRow] = partial || !includesSource ? [] : [.init(record: record, presence: .unknown,
            capability: .init(profileID: "synthetic-scan", state: .readOnly, testedOSBuilds: [], reason: "合成比较夹具"), evidence: [])]
        return .init(generation: generation, observedAt: now, rows: rows, coverage: configuration.launchRoots.map { root in
            .init(providerID: "launchd.configuration", state: partial ? .permissionDenied : .completeWithinDeclaredScope,
                declaredRoots: [root.url.path], userScopes: ["currentUser"], osBuild: "synthetic-tests",
                generation: generation, parsedCount: root.url.path == "/Synthetic/LaunchAgents" ? rows.count : 0)
        })
    }
}
#endif

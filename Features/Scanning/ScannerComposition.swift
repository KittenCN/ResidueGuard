import Foundation
import ResidueCore
import ResiduePlatform

extension WorkspaceStore {
    static func production() -> WorkspaceStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-synthetic-scan") {
            let slow = ProcessInfo.processInfo.arguments.contains("--ui-slow-scan")
            return WorkspaceStore(scanner: WorkspaceScanner { _ in
                if slow { try? await Task.sleep(for: .seconds(30)) }
                let cancelled = Task.isCancelled
                let generation = UUID().uuidString
                let now = Date()
                let record = SourceRecord(id: .init(providerID: "synthetic.scan", scope: "currentUser", nativeIdentity: "fixture-readonly"),
                    category: "launchConfiguration", observedAt: now, generation: generation,
                    sourceArtifact: "/Synthetic/LaunchAgents/readonly.plist", displayName: "合成扫描·只读项目",
                    declaredAppIDs: [], targetReferences: ["/Synthetic/tool"], rawMetadata: ["fixture": "synthetic-not-user-data"], parseWarnings: [])
                let row = ScanRow(record: record, presence: .unknown,
                    capability: .init(profileID: "synthetic-scan", state: .readOnly, testedOSBuilds: [], reason: "测试注入，不读取主机"), evidence: ["合成扫描来源"])
                return ScanSnapshot(generation: generation, observedAt: now, rows: cancelled ? [] : [row],
                    coverage: [.init(providerID: "synthetic.scan", state: cancelled ? .cancelled : .partial,
                        declaredRoots: ["/Synthetic"], diagnostics: ["测试注入；未读取真实系统"], generation: generation, parsedCount: cancelled ? 0 : 1)])
            }, syntheticScan: true)
        }
        #endif
        return WorkspaceStore()
    }
}

import SwiftUI
import ResidueCore

/// Candidate hints only: this view has no selection, confirmation or mutation controls.
struct ApplicationAssociationView: View {
    @Bindable var store: WorkspaceStore
    @State private var search = ""
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("应用实例与候选关联").font(.title2)
                Text("声明的应用标识和程序路径只提供关联线索。签名元数据尚未验证；没有候选不代表软件已卸载，也不能用候选图确定完整清理影响。")
                    .foregroundStyle(.secondary)
                if let graph = store.ownershipGraph {
                    let edgesByNode = Dictionary(grouping: graph.edges, by: \.applicationNodeID)
                    let names = Dictionary(store.records.compactMap { record in
                        record.provenance.map { ($0.id, record.name) }
                    }, uniquingKeysWith: { first, _ in first })
                    Text("本次观察 \(graph.applications.count) 个实例节点 · \(graph.edges.count) 条候选关联 · \(graph.issues.count) 项限制或冲突")
                        .accessibilityIdentifier("ownership.counts")
                    Text(graph.isPartial ? "关联覆盖有限，不能证明已列出所有安装实例。" : "仅展示本次输入中的关联，不代表全系统覆盖。")
                        .accessibilityIdentifier("ownership.coverage")
                    TextField("筛选应用标识或观察路径", text: $search).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("ownership.search")
                    if graph.applications.isEmpty {
                        Text("本次没有可展示的应用实例；请检查应用索引授权和采集覆盖，不据此判断卸载。")
                    }
                    if !graph.applications.isEmpty && graph.applications.filter(matches).isEmpty {
                        Text("筛选未命中；只过滤当前展示，不代表实例不存在。")
                            .accessibilityIdentifier("ownership.noMatches")
                    }
                    ForEach(graph.applications.filter(matches)) { node in
                        nodeView(node, edges: edgesByNode[node.id] ?? [], names: names)
                    }
                    if !graph.issues.isEmpty {
                        DisclosureGroup("限制与冲突（不能据候选确认归属）") {
                            ForEach(Array(graph.issues.enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issueLabel(issue.kind))
                                    if let recordID = issue.recordID { Text(names[recordID] ?? recordID.nativeIdentity).font(.caption) }
                                    Text("关联实例提示 \(issue.applicationNodeIDs.count) 项 · 关联记录提示 \(issue.relatedRecordIDs.count) 项").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 3)
                            }
                        }.accessibilityIdentifier("ownership.issues")
                    }
                } else {
                    Text(store.isDemo ? "合成演示未提供应用实例索引；记录示例仍可在各来源分类查看。" : "尚无应用索引快照。请显式选择应用索引目录并开始只读扫描。")
                        .accessibilityIdentifier("ownership.notScanned")
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func matches(_ node: OwnershipApplicationNode) -> Bool {
        search.isEmpty || node.observations.contains {
            $0.path.localizedCaseInsensitiveContains(search) || $0.declaredBundleID.localizedCaseInsensitiveContains(search)
        }
    }
    private func nodeView(_ node: OwnershipApplicationNode, edges: [CandidateOwnershipEdge], names: [RecordIdentity: String]) -> some View {
        return DisclosureGroup {
            ForEach(Array(node.observations.enumerated()), id: \.offset) { _, observation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(observation.path).textSelection(.enabled)
                    Text("声明标识：\(observation.declaredBundleID)")
                    Text("签名标识线索：\(observation.signingIdentifier ?? "未观察到")").font(.caption)
                    Text("签名元数据未验证，不作为归属或执行授权。").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            if !node.issues.isEmpty { Text(node.issues.map(issueLabel).joined(separator: "；")) }
            if edges.isEmpty { Text("当前输入中没有候选关联；不代表不存在登记或已卸载。") }
            ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                VStack(alignment: .leading, spacing: 3) {
                    Text(names[edge.recordID] ?? edge.recordID.nativeIdentity)
                    Text(edge.reasons.map(reason).joined(separator: "；")).font(.caption).foregroundStyle(.secondary)
                }
            }
        } label: {
            VStack(alignment: .leading) {
                Text(node.observations.first?.declaredBundleID ?? "身份未核实的实例")
                    .accessibilityIdentifier("ownership.node.label")
                Text("\(node.observations.count) 次路径观察 · \(edges.count) 条候选关联").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func issueLabel(_ issue: OwnershipIssueKind) -> String {
        switch issue {
        case .duplicateBundleIdentifier: "同一应用标识有多个安装实例"
        case .conflictingInstanceObservations: "同一实例的观察信息冲突"
        case .differingIdentityHints: "声明与签名或路径身份线索不同"
        case .ambiguousRecordIdentity: "来源记录身份重复，不能确定关联"
        case .possibleSharedPayload: "可能共享同一程序，归属尚未核实"
        case .insufficientCoverage: "来源覆盖不足或扫描代次不一致"
        case .unknownGeneration: "扫描代次未知，不能建立关联"
        case .unknownIdentity: "实例身份不足，不能建立关联"
        case .unparsedRecord: "来源解析未完成，不能建立关联"
        case .malformedTargetPath: "目标路径含歧义，未用于关联"
        case .inputLimit: "达到处理上限，结果有明确截断"
        }
    }
    private func reason(_ value: CandidateOwnershipReason) -> String {
        switch value {
        case .declaredBundleIdentifier: "来源声明标识相同（未验证）"
        case .lexicalTargetWithinBundle: "程序路径文字位于应用目录内（未验证）"
        }
    }
}

import SwiftUI
import ResidueCore

struct OverviewView: View {
    let store: WorkspaceStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("先核实来源，再判断残留").font(.largeTitle.bold())
                Text("真实扫描只读；清理确认仅限合成 dry-run。不会修改启动项、后台服务、权限或应用文件。")
                GroupBox("权限总表不可读取") {
                    Text("当前版本未接入真实权限提供器。macOS 27+ 不使用 TCC 数据库直读。权限页面提供手动核对路径，不把不可读取显示为 0 个应用。")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                if store.isDemo {
                    HStack(spacing: 28) {
                        metric("合成记录", store.records.count)
                        metric("合成高可信残留", store.records.filter { $0.presence == .highConfidenceOrphan }.count)
                        metric("真实可执行动作", 0)
                    }
                    Text("演示加载时间：\(store.loadedAt?.formatted() ?? "未知")；范围：Resources/demo-records.json，非本机数据。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    if store.hasSnapshot {
                        Text("已读取 \(store.records.count) 条记录；真实可执行动作：0。")
                        Text("扫描时间：\(store.loadedAt?.formatted() ?? "未知")")
                            .font(.caption)
                    } else { Text(store.isScanning ? "扫描进行中；数量尚未确定。" : "扫描状态：未运行。记录数量未知。请主动选择目录后扫描。") }
                }
                if store.isDemo {
                    Text("合成覆盖状态演示").font(.title2)
                    ForEach(Array(demoCoverage.enumerated()), id: \.offset) { _, coverage in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(coverage.providerID) · \(coverage.state.demoTitle)").font(.headline)
                                Text("范围：\(coverage.declaredRoots.joined(separator: "、"))")
                                Text(coverage.diagnostics.joined(separator: "；")).foregroundStyle(.secondary)
                            }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text(store.isSyntheticScan && !store.isDemo ? "合成测试来源覆盖（未读取主机）" : "真实来源覆盖").font(.title2)
                ForEach(Array(store.coverage.enumerated()), id: \.offset) { _, coverage in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(coverage.providerID) · \(coverage.state.demoTitle)").font(.headline)
                            Text("声明范围：\(coverage.declaredRoots.joined(separator: "、"))")
                            Text("已解析 \(coverage.parsedCount)；未解析 \(coverage.unparsedCount)")
                            Text((coverage.diagnostics + coverage.errors + coverage.skippedAreas).joined(separator: "；"))
                                .foregroundStyle(.secondary)
                            Text("代次：\(coverage.generation)").foregroundStyle(.secondary)
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.accessibilityIdentifier("coverage.\(coverage.providerID)")
                }
                if store.coverage.isEmpty {
                ForEach(["用户启动配置", "共享启动配置", "登录项 / BTM 后台登记", "权限分类 / 独立权限机制"], id: \.self) { source in
                    GroupBox {
                        HStack(alignment: .top) {
                            Label(source, systemImage: "doc.text.magnifyingglass")
                            Spacer()
                            Text("未验证 · 尚未采集").foregroundStyle(.secondary)
                        }
                        Text("声明范围：无真实扫描范围；未启动提供器。下一步：在 P2 验证只读来源与覆盖缺口。")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                }
                Text("覆盖状态模型支持：声明范围内完成、部分、权限不足、不支持、失败、取消。未运行项不计为通过，部分结果不等于完整清单。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private var demoCoverage: [ScanCoverage] {
        [
            .init(providerID: "合成·启动配置", state: .completeWithinDeclaredScope, declaredRoots: ["/Synthetic/Agents"], diagnostics: ["仅在合成声明范围内完成；非全系统清单"]),
            .init(providerID: "合成·后台登记", state: .partial, declaredRoots: ["合成当前用户"], diagnostics: ["存在未解析记录；保留未知项，不能当作空列表"]),
            .init(providerID: "合成·受限来源", state: .permissionDenied, declaredRoots: ["合成受限目录"], diagnostics: ["未能读取，不代表不存在"]),
            .init(providerID: "合成·权限总表", state: .unsupported, declaredRoots: ["不提供 TCC 直读"], diagnostics: ["通过系统设置手动核对"]),
            .init(providerID: "合成·失败来源", state: .failed, declaredRoots: ["合成解析输入"], diagnostics: ["解析失败，真实来源未运行"]),
            .init(providerID: "合成·取消来源", state: .cancelled, declaredRoots: ["合成剩余范围"], diagnostics: ["未访问区域不计为空"])
        ]
    }
    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading) { Text(value.formatted()).font(.title.bold()); Text(title).font(.caption) }
    }
}

private extension CoverageState {
    var demoTitle: String {
        switch self {
        case .completeWithinDeclaredScope: "声明范围内完成"
        case .partial: "部分"
        case .permissionDenied: "权限不足"
        case .unsupported: "不支持"
        case .failed: "失败"
        case .cancelled: "取消"
        }
    }
}

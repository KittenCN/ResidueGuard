import SwiftUI
import ResidueCore
import ResidueRecovery

struct HistoryReportView: View {
    @State private var store = HistoryReportStore()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("导入历史审计报告").font(.title2)
                Text("此页仅核查你选择的报告，不代表完整清理历史。导入不会执行、重试或恢复任何操作。")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("导入历史审计报告…") { store.chooseReport() }
                        .disabled(store.isLoading).accessibilityIdentifier("history.import")
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                        Button("取消导入") { store.cancel() }.accessibilityIdentifier("history.cancel")
                    }
                    if store.summary != nil {
                        Button("移除本次报告") { store.clear() }.accessibilityIdentifier("history.clear")
                    }
                }
                if store.isSynthetic {
                    Label("测试注入 · 合成历史报告，非真实操作记录", systemImage: "testtube.2")
                        .accessibilityIdentifier("history.synthetic")
                }
                Text(store.message).accessibilityIdentifier("history.status")
                if let summary = store.summary {
                    Label("来源未经验证 · 只读摘要", systemImage: "exclamationmark.shield")
                        .font(.headline).accessibilityIdentifier("history.untrusted")
                    Text("内容校验不证明真实性或授权。备份摘要不保证文件仍有效，备份与系统状态需要另行核验。")
                        .accessibilityIdentifier("history.backupWarning")
                    Text("目标 \(summary.targetCount) 项 · 计划 \(summary.plannedStepCount) 步 · 已记录 \(summary.steps.count) 步 · 备份记录 \(summary.recordedBackupCount) 项")
                        .accessibilityIdentifier("history.counts")
                    Text(summary.auditClosed ? "审计已结束（不代表全部操作成功）" : "审计未结束，需要只读核查")
                    ForEach(summary.steps, id: \.index) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("步骤 \(step.index + 1) · \(step.action == .bootoutExactService ? "精确服务卸载" : "配置隔离")").font(.headline)
                            if let effects = step.effects {
                                Text("文件：\(label(effects.file))；运行状态：\(label(effects.runtime))")
                                Text("后台登记：\(label(effects.registration))；权限：\(label(effects.permission))")
                            } else {
                                Text("已准备，结果未知；不能自动重试。").accessibilityIdentifier("history.unresolved")
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            #if DEBUG
            store.loadUITestFixtureIfRequested()
            #endif
        }
        .onDisappear { store.cancel() }
    }
    private func label(_ effect: TransactionEffect) -> String {
        switch effect {
        case .notAttempted: "未执行"
        case .succeeded: "记录为成功"
        case .failed: "记录为失败"
        case .unverified: "未验证"
        case .pendingSystemRefresh: "等待系统刷新"
        }
    }
}

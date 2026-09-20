import SwiftUI
import ResidueCore

struct RetentionRulesView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("保留规则（不隐藏记录）").font(.title2)
                    Text("在记录详情中显式保留30天。匹配仅增加保护；来源标识、内容指纹变化或到期时不再匹配。未再次观察到不代表已删除。")
                        .foregroundStyle(.secondary)
                    Text(store.retention.message).accessibilityIdentifier("retention.status")
                    HStack {
                        Button("重新读取本地规则") {
                            Task { await store.retention.reload(); store.refreshRetentionProtection() }
                        }.disabled(store.retention.isBusy)
                        if store.retention.isBusy { ProgressView().controlSize(.small) }
                    }
                    Text("本地规则").font(.headline)
                    if !store.retention.isReady {
                        Text("本地规则状态未知；不能将读取或校验失败当成没有规则。")
                    } else if store.retention.localRules.isEmpty {
                        Text("尚无本地规则。只有明确添加后才写入本应用配置目录。")
                    }
                    ForEach(store.retention.localRules) { rule in row(rule, sessionOnly: false, now: timeline.date) }
                    Text("本次演示规则 · 不持久保存").font(.headline)
                    if store.retention.sessionRules.isEmpty { Text("尚无本次演示规则。").accessibilityIdentifier("retention.session.empty") }
                    ForEach(store.retention.sessionRules) { rule in row(rule, sessionOnly: true, now: timeline.date) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func row(_ rule: RetentionRule, sessionOnly: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rule.recordIdentity.nativeIdentity).font(.callout).textSelection(.enabled)
            Text("\(rule.recordIdentity.providerID) · \(rule.recordIdentity.scope)").font(.caption).foregroundStyle(.secondary)
            Text(stateLabel(store.retentionState(rule, sessionOnly: sessionOnly, now: now)))
                .accessibilityIdentifier(sessionOnly ? "retention.rule.state.session.\(rule.recordIdentity.nativeIdentity)" : "retention.rule.state.local.\(rule.id.uuidString)")
            Text("到期：\(rule.expiresAt.formatted())").font(.caption)
            Button("移除保留规则") { Task { await store.removeRetentionRule(rule, sessionOnly: sessionOnly) } }
                .disabled(store.isScanning || store.isLoading || store.retention.isBusy || (!sessionOnly && !store.retention.isReady))
                .accessibilityIdentifier(sessionOnly ? "retention.remove.session.\(rule.recordIdentity.nativeIdentity)" : "retention.remove.local.\(rule.id.uuidString)")
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func stateLabel(_ value: RetentionMatchState) -> String {
        switch value {
        case .protected: "当前匹配 · 已增加保护"
        case .expired: "已到期 · 不再匹配"
        case .notYetValid: "时间尚未生效 · 不匹配"
        case .unmatched: "本次未观察到 · 不代表已删除"
        case .identityChanged: "来源身份不同 · 不匹配"
        case .fingerprintChanged: "来源内容已变化 · 不匹配"
        case .unknownObservation: "观察证据不足 · 无法匹配"
        }
    }
}

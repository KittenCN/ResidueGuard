import SwiftUI
import ResidueCore

struct CleanupReviewView: View {
    @Bindable var store: WorkspaceStore
    @State private var session: ConsentSession?
    @State private var presentationID: UUID?
    @State private var riskPhrase = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Dry-run · 合成计划预演", systemImage: "testtube.2").font(.title2.bold())
            Text("不会执行任何系统操作；完成模拟确认也不会生成真实执行授权。")
                .foregroundStyle(.secondary)
            if let plan = store.review {
                if session?.stage == .complete {
                    ContentUnavailableView("预演确认流程完成", systemImage: "checkmark.seal", description: Text("真实修改：0。未停用服务、未删除配置、未重置权限。"))
                        .accessibilityIdentifier("review.complete")
                } else if session?.stage == .secondPresented {
                    secondConfirmation(plan)
                } else {
                    preview(plan)
                }
                if !message.isEmpty { Text(message).foregroundStyle(.orange).accessibilityIdentifier("review.message") }
            } else {
                Text("计划已失效，请重新检查所选操作。")
            }
            Divider()
            HStack {
                Text("系统认证不能替代应用内确认。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(session?.stage == .complete ? "关闭" : "取消") {
                    session?.invalidate(); store.showsReview = false
                }.keyboardShortcut(.cancelAction).accessibilityIdentifier("review.cancel")
            }
        }.padding(24).frame(width: 700, height: 590)
    }
    private func preview(_ plan: DryRunPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("所选 \(plan.selectedRecordIDs.count) 项 → 实际影响 \(plan.targets.count) 个对象 / \(plan.operationKeys.count) 个合成动作")
                .font(.headline)
            Text("操作：合成配置隔离预演；范围：演示用户。未创建备份，未验证恢复。没有管理员认证或真实执行步骤。")
                .font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.targets) { target in
                        VStack(alignment: .leading) {
                            Text("\(target.displayName) · \(target.presence.title)").font(.headline)
                            Text("身份：\(target.id)").font(.caption)
                            Text(store.records.first { $0.id == target.id }?.path ?? "路径未知").font(.caption).textSelection(.enabled)
                        }
                    }
                    ForEach(plan.diagnostics, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("计划摘要：\(plan.digest.prefix(16)) · 到期：\(plan.expiresAt.formatted(date: .omitted, time: .standard))")
                .font(.caption).foregroundStyle(.secondary)
            if session == nil {
                if plan.requirement == .blocked {
                    Button("已核对全部实际影响，批准预演范围") {
                        store.makePlan(expandedImpactApproved: true)
                        if let refreshed = store.review, refreshed.requirement == .one || refreshed.requirement == .two {
                            prepareFirst(refreshed)
                        } else { message = "仍存在阻断条件；请退出并重新载入演示数据或调整选择。" }
                    }.accessibilityIdentifier("review.approveImpact")
                    Text("范围批准不是清理确认；未知、受保护或无操作能力不能靠确认越过。").font(.caption)
                } else {
                    Button("开始模拟确认") { prepareFirst(plan) }
                }
            } else if session?.stage == .firstPresented {
                Text(plan.requirement == .one ? "全部实际影响为可操作的合成高可信残留：需要一次模拟确认。" : "实际影响包含仍安装软件：需要两次独立模拟确认。")
                Button(plan.requirement == .one ? "模拟确认这 \(plan.targets.count) 项" : "继续检查风险（模拟第一次确认）") {
                    guard let presentationID, session?.confirmFirst(presentation: presentationID, now: Date(), currentDigest: plan.digest) == true else {
                        message = "确认失效，请取消并重新生成计划。"; return
                    }
                    self.presentationID = nil
                    if plan.requirement == .two {
                        riskPhrase = ""
                        self.presentationID = session?.presentSecond(now: Date(), currentDigest: plan.digest)
                    }
                }.accessibilityIdentifier("review.confirmFirst")
            } else {
                Text("计划已失效，请取消后重新检查。")
            }
        }
    }
    private func secondConfirmation(_ plan: DryRunPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("第二次独立确认 · 仍安装软件", systemImage: "exclamationmark.triangle").font(.title2)
            Text(plan.targets.filter { $0.presence == .present }.map(\.displayName).joined(separator: "、")).font(.headline)
            Text("真实清理若在未来开放，会影响这些软件的设置或启动行为。当前仅演示风险确认，不改变系统。")
            Text("请输入：\(ConsentSession.riskPhrase)")
            TextField("风险确认文字", text: $riskPhrase).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("review.riskPhrase")
            Button("再次模拟确认") {
                guard let presentationID, session?.confirmSecond(presentation: presentationID, phrase: riskPhrase, now: Date(), currentDigest: plan.digest) == true else {
                    message = "计划已失效或确认文字不匹配。"; return
                }
                self.presentationID = nil
            }.disabled(riskPhrase != ConsentSession.riskPhrase).accessibilityIdentifier("review.confirmSecond")
            Text("此页没有默认回车确认。连续点击或回车不能代替重新输入风险文字。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
    private func prepareFirst(_ plan: DryRunPlan) {
        session = ConsentSession(plan: plan)
        presentationID = session?.presentFirst(now: Date(), currentDigest: plan.digest)
        if presentationID == nil { message = "计划过期或无法确认，请重新生成。" }
    }
}

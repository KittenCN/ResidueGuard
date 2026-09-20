import AppKit
import Foundation
import Observation
import ResidueCore
import ResidueRecovery
import ResidueAuditImport
import UniformTypeIdentifiers

@MainActor @Observable
final class HistoryReportStore {
    private(set) var summary: RecoveryReviewSummary?
    private(set) var message = "尚未导入报告。这不是完整的清理历史；应用不会自动读取历史文件。"
    private(set) var isLoading = false
    private(set) var isSynthetic = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activePanel: NSOpenPanel?

    func chooseReport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.json]
        panel.title = "导入历史审计报告（只读）"
        panel.message = "仅读取这次选择的当前用户文件。授权不保存；报告来源未经验证，不作为执行或恢复依据。"
        panel.prompt = "只读导入"
        guard let window = NSApp.keyWindow else {
            message = "无法打开文件选择器：请先激活本窗口。"; return
        }
        activePanel = panel
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.activePanel = nil
            guard response == .OK, let url = panel.url else {
                self.message = "已取消选择；没有读取新的报告。"; return
            }
            self.start(synthetic: false) { try Self.readReport(url) }
        }
    }
    func cancel() {
        guard isLoading else { return }
        generation = UUID(); task?.cancel(); task = nil
        isLoading = false; message = "导入已取消；未载入报告。"; summary = nil
    }
    func clear() {
        cancel(); summary = nil; isSynthetic = false
        message = "报告已从本次界面移除；未保存文件授权或导入内容。"
    }
    private func start(synthetic: Bool, work: @escaping @Sendable () async throws -> RecoveryReviewSummary) {
        cancel(); summary = nil; isSynthetic = synthetic; isLoading = true
        message = "正在只读解析报告…"
        let current = UUID(); generation = current
        task = Task {
            let worker = Task.detached(priority: .userInitiated) { try await work() }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard generation == current, !Task.isCancelled else { return }
                summary = result; message = "已导入脱敏摘要。来源未经验证，必须重新只读核查。"
            } catch {
                guard generation == current else { return }
                switch error {
                case is CancellationError: message = "导入已取消；未载入报告。"
                case RecoveryAuditError.unsupportedVersion: message = "无法导入：报告版本不受支持。不是空历史。"
                case RecoveryAuditError.oversized, AuditImportError.oversized: message = "无法导入：报告超过大小限制。不是空历史。"
                case AuditImportError.inaccessible: message = "无法导入：文件不可访问或系统拒绝读取。不是空历史。"
                case AuditImportError.unsupportedFile: message = "无法导入：只接受当前用户拥有的普通文件，不接受链接。"
                case AuditImportError.changedDuringRead: message = "无法导入：读取期间文件发生变化，请重新选择。"
                default: message = "无法导入：报告损坏、结构不受支持或校验失败。不是空历史。"
                }
            }
            isLoading = false; task = nil
        }
    }
    nonisolated private static func readReport(_ url: URL) throws -> RecoveryReviewSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try SelectedAuditReportReader.readSummary(from: url)
    }

    #if DEBUG
    func loadUITestFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-history-fixture") else { return }
        let invalid = arguments.contains("--ui-history-invalid")
        let slow = arguments.contains("--ui-history-slow")
        start(synthetic: true) {
            if slow { try await Task.sleep(for: .seconds(10)) }
            if invalid { _ = try RecoveryAudit.decode(Data("invalid synthetic report".utf8)) }
            let date = Date(timeIntervalSince1970: 5000)
            let plan = try VerifiedTransactionPlan.validate(scope: "currentUser", profileID: VerifiedTransactionPlan.syntheticProfileID,
                createdAt: date, expiresAt: date.addingTimeInterval(120),
                steps: [.init(id: "private-test-stop", targetID: "private-test-target", action: .bootoutExactService, fingerprint: "private-test-fingerprint"),
                        .init(id: "private-test-isolate", targetID: "private-test-target", action: .quarantineLaunchConfiguration, fingerprint: "private-test-fingerprint", dependencies: ["private-test-stop"])],
                targets: [.init(id: "private-test-target", displayName: "/Synthetic/Private.app", presence: .highConfidenceOrphan, fingerprint: "private-test-fingerprint")], impactApproved: true)
            let snapshot = RecoveryAuditSnapshot(plan: .init(recording: plan), backups: [], observations: [
                .init(stepID: "private-test-stop", preparedAt: date, resultAt: date.addingTimeInterval(1), effects: .init(runtime: .succeeded, registration: .pendingSystemRefresh)),
                .init(stepID: "private-test-isolate", preparedAt: date.addingTimeInterval(2))])
            return try RecoveryAudit.summary(RecoveryAudit.decode(RecoveryAudit.encode(snapshot)))
        }
    }
    #endif
}

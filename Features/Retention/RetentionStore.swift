import Foundation
import Observation
import ResidueCore
import ResiduePreferences

@MainActor @Observable
final class RetentionStore {
    private(set) var localRules: [RetentionRule] = []
    private(set) var sessionRules: [RetentionRule] = []
    private(set) var isReady = false
    private(set) var isBusy = false
    private(set) var message = "尚未读取本地保留规则。"
    private var revision: String?
    private var didLoad = false
    private var supportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await reload()
    }
    func reload() async {
        guard !isBusy, let directory = supportDirectory else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let worker = Task.detached(priority: .utility) {
                try RetentionPreferenceStore.read(sandboxLibraryDirectory: directory.deletingLastPathComponent())
            }
            let snapshot = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            let configuration = try snapshot.map { try RetentionRuleConfiguration.decode(data: $0.data) }
            localRules = configuration?.rules ?? []
            revision = snapshot?.revision
            isReady = true
            message = "本地规则已读取。规则只增加保护，不隐藏记录，也不赋予清理能力。"
        } catch {
            isReady = false
            message = "本地规则无法读取或校验；未将错误视为空规则。请检查配置后重新读取。"
        }
    }
    func add(identity: RecordIdentity, fingerprint: String, sessionOnly: Bool) async {
        guard !isBusy, sessionOnly || isReady else { return }
        do {
            let rule = try RetentionRule(recordIdentity: identity, fingerprint: fingerprint, createdAt: Date())
            if sessionOnly {
                let proposed = sessionRules.filter { $0.recordIdentity != identity } + [rule]
                sessionRules = try RetentionRuleConfiguration(rules: proposed).rules
                message = "已添加30天保留规则；当前为合成演示，规则仅在本次会话有效，不写入本地配置。"
            } else {
                await save(localRules.filter { $0.recordIdentity != identity } + [rule])
            }
        } catch {
            message = "无法添加规则：来源标识、内容指纹或规则数量不符合约束。"
        }
    }
    func remove(_ rule: RetentionRule, sessionOnly: Bool) async {
        guard !isBusy else { return }
        if sessionOnly {
            sessionRules.removeAll { $0.id == rule.id }
            message = "已移除本次会话规则；没有改动来源文件。"
        } else if isReady {
            await save(localRules.filter { $0.id != rule.id })
        }
    }
    private func save(_ rules: [RetentionRule]) async {
        guard let directory = supportDirectory else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try RetentionRuleConfiguration(rules: rules).encoded()
            let expected = revision
            let worker = Task.detached(priority: .utility) {
                try RetentionPreferenceStore.save(data: data, expectedRevision: expected, sandboxLibraryDirectory: directory.deletingLastPathComponent())
            }
            let snapshot = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            localRules = rules; revision = snapshot.revision
            message = "规则已保存到本应用配置。没有修改扫描来源或系统服务。"
        } catch {
            isReady = false
            message = "保存未确认：配置可能已变化或写入未完成。已停止更新；请重新读取后核对，不能直接重试覆盖。"
        }
    }
}

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("当前阶段") {
                LabeledContent("模式", value: "P1 · 只读与合成预演")
                LabeledContent("真实扫描根目录", value: "未启用")
                LabeledContent("持久化日志 / 备份", value: "未启用")
            }
            Section("自身后台组件") {
                LabeledContent("登录启动", value: "未注册")
                LabeledContent("特权 helper", value: "未提供安装能力")
                LabeledContent("持续监控", value: "未启用")
                LabeledContent("网络遥测", value: "未启用")
            }
            Text("SMAppService 仅可用于本应用自身服务。当前版本没有服务注册、系统清理或权限重置执行器。")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).padding().frame(width: 520)
    }
}

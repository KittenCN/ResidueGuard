import SwiftUI

struct PermissionGuidanceView: View {
    let page: WorkspacePage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(page.rawValue, systemImage: "hand.raised.slash").font(.largeTitle)
                Text("当前系统未提供可用的完整列表读取方式").font(.title2).accessibilityIdentifier("permission.unavailable")
                Text("此页没有读取任何应用权限记录，无法报告应用数量。macOS 27+ 不直读 TCC 数据库，不使用绕过方案。")
                GroupBox("手动核对") {
                    Text(page == .notifications ? "打开 系统设置 → 通知，手动检查对应应用。" : "打开 系统设置 → 隐私与安全性 → \(page.rawValue)，手动核对。具体名称可能随系统版本变化。")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                if [.network, .location, .notifications].contains(page) {
                    Text("这是独立权限机制，不使用猜测的 TCC service 名称，也不提供重置操作。")
                }
                if page == .automation {
                    Text("自动化关系为调用者 → 被控制者。单条关系不代表动作只影响单条关系；任何扩大范围必须重新预览和授权。")
                }
                Text("P1 仅提供文字引导，不会代替你点击系统设置、申请无关权限或执行任何重置。")
                    .foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}

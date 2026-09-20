import SwiftUI
import ResidueCore

struct PermissionGuidanceView: View {
    let page: WorkspacePage
    private var descriptor: PermissionCategoryDescriptor {
        PermissionCatalog.descriptor(PermissionCategory.allCases.first { $0.title == page.rawValue } ?? .unknown)
    }
    private var profile: PermissionCapabilityProfile {
        // No tested live permission provider is shipped, even on the development build.
        PermissionCapabilityRegistry.profile(category: descriptor.category,
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            recognizedEnvironment: false)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(descriptor.category.title, systemImage: "hand.raised.slash").font(.largeTitle)
                Text("当前系统未提供可用的完整列表读取方式").font(.title2).accessibilityIdentifier("permission.unavailable")
                Text("此页没有读取任何应用权限记录，无法报告应用数量。macOS 27+ 不直读 TCC 数据库，不使用绕过方案。")
                GroupBox("手动核对") {
                    Text(descriptor.guidance)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        .accessibilityIdentifier("permission.guidance")
                }
                Text(descriptor.limitation)
                GroupBox("当前能力") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("完整清单：不可读取；精确重置：禁用；后置验证：未验证。")
                        Text(profile.reason)
                        Text("旧版数据库适配器：未启用。未知系统或 build 不沿用旧版读写策略。")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                Text("导入的历史快照只能用于对照，不代表当前授权，也不能成为可执行计划的依据。权限重置不支持恢复旧授权。")
                Text("本页仅提供文字引导，不会代替你点击系统设置、申请无关权限或执行任何重置。")
                    .foregroundStyle(.secondary)
            }.padding(24).textSelection(.enabled)
        }
    }
}

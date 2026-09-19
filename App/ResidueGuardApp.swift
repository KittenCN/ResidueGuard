import SwiftUI
import Darwin

@main
struct ResidueGuardApp: App {
    var body: some Scene {
        WindowGroup("macOS 残留管家") {
            if geteuid() == 0 {
                ContentUnavailableView("请以普通用户启动", systemImage: "lock.shield", description: Text("主界面禁止以 root 身份运行。"))
            } else {
                WorkspaceView()
            }
        }
        .defaultSize(width: 1220, height: 780)
        Settings { SettingsView() }
    }
}

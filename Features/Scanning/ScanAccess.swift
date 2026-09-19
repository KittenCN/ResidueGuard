import AppKit
import Darwin
import Foundation
import ResidueCore
import ResiduePlatform

/// Only the explicit picker crosses into AppKit. No bookmarks or grants persist.
@MainActor
enum ScanAccess {
    static func isAllowedDirectory(_ url: URL, applicationRoots: Bool) -> Bool {
        guard let passwd = getpwuid(getuid()), let directory = passwd.pointee.pw_dir else { return false }
        let home = String(cString: directory)
        let path = url.standardizedFileURL.path
        if applicationRoots {
            return path == "/Applications" || path == "/System/Applications" || path.hasPrefix(home + "/")
        }
        return [home + "/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons",
                "/System/Library/LaunchAgents", "/System/Library/LaunchDaemons"].contains(path)
    }
    static func chooseDirectories(applicationRoots: Bool) -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true; panel.canCreateDirectories = false
        panel.title = applicationRoots ? "选择应用索引目录（只读）" : "选择启动配置目录（只读）"
        panel.message = applicationRoots
            ? "仅索引所选目录内的应用，不运行应用。授权在本次扫描后释放。"
            : "选择当前用户或共享的 LaunchAgents / LaunchDaemons 目录。不会读取其他用户私有数据，不修改配置。"
        panel.prompt = "授权只读扫描"
        return panel.runModal() == .OK ? panel.urls : nil
    }
}

struct WorkspaceScanner: Sendable {
    var scan: @Sendable (ScanConfiguration) async -> ScanSnapshot
    static let live = WorkspaceScanner { configuration in
        let service = ScanService(configuration: configuration)
        return await withTaskCancellationHandler {
            await service.scan()
        } onCancel: {
            Task { await service.cancel() }
        }
    }
}

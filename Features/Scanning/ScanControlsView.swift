import SwiftUI

struct ScanControlsView: View {
    let store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("选择启动配置目录…") { store.chooseRoots(applications: false) }
                    .disabled(store.isScanning || store.isLoading).accessibilityIdentifier("scan.chooseLaunchRoots")
                Button("选择应用索引目录…") { store.chooseRoots(applications: true) }
                    .disabled(store.isScanning || store.isLoading)
            }
            HStack {
                Button(store.isSyntheticScan ? "扫描合成测试来源" : "开始只读扫描") { store.startScan() }
                    .disabled(store.isScanning || store.isLoading).accessibilityIdentifier("scan.start")
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Button(store.cancellationRequested ? "正在取消…" : "取消扫描") { store.cancelScan() }
                        .disabled(store.cancellationRequested).accessibilityIdentifier("scan.cancel")
                }
            }
            Text("仅扫描主动选择的目录；配置目录 \(store.configuredLaunchRoots.count) 个，应用索引目录 \(store.configuredApplicationRoots.count) 个。不运行所发现程序，不持久化授权。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal).padding(.bottom, 10)
    }
}

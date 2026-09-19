import SwiftUI

struct WorkspaceView: View {
    @State private var store = WorkspaceStore.production()
    @State private var showInspector = true
    var body: some View {
        NavigationSplitView {
            List(selection: $store.page) {
                ForEach(["工作台", "启动与后台", "权限", "管理"], id: \.self) { group in
                    Section(group) {
                        ForEach(WorkspacePage.allCases.filter { $0.group == group }) { page in
                            Label(page.rawValue, systemImage: page.symbol).tag(page)
                                .accessibilityIdentifier("page.\(page.rawValue)")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(store.modeTitle, systemImage: store.isDemo ? "testtube.2" : "lock.shield")
                        .font(.headline).accessibilityIdentifier("mode.banner")
                    Spacer()
                    if store.isDemo {
                        Button("退出演示") { store.unloadDemo() }.accessibilityIdentifier("demo.exit")
                    } else {
                        Button("载入合成演示") { Task { await store.loadDemo() } }
                            .disabled(store.isLoading || store.isScanning).accessibilityIdentifier("demo.load")
                    }
                }.padding()
                ScanControlsView(store: store)
                Divider()
                if store.page == .overview { OverviewView(store: store) }
                else if store.page.isPermission { PermissionGuidanceView(page: store.page) }
                else if store.page == .history || store.page == .ignore {
                    ContentUnavailableView(store.page.rawValue, systemImage: store.page.symbol,
                        description: Text(store.page == .history ? "P1 仅在内存中预演，不执行清理、不创建系统备份，也不提供恢复授权。" : "P1 尚未启用持久化忽略规则。没有自动清理或自动勾选。"))
                } else { RecordsView(store: store) }
                Divider()
                Text(store.notice).font(.caption).foregroundStyle(.secondary).padding(10).textSelection(.enabled)
            }
            .navigationTitle(store.page.rawValue)
            .toolbar { Button { showInspector.toggle() } label: { Label("详情", systemImage: "sidebar.right") } }
            .inspector(isPresented: $showInspector) { RecordInspector(record: store.inspected, loadedAt: store.loadedAt) }
            .inspectorColumnWidth(min: 240, ideal: 280, max: 400)
        }
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $store.showsReview) { CleanupReviewView(store: store) }
    }
}

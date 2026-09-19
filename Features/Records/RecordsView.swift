import SwiftUI
import ResidueCore

struct RecordsView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.isDemo {
                ContentUnavailableView("尚未采集此来源", systemImage: "doc.text.magnifyingglass", description: Text("当前没有真实扫描结果。可主动载入合成演示以验证界面与策略。"))
            } else {
                filters
                Text("来源：合成夹具；范围：演示用户 / 演示系统；真实来源未运行。登记与运行状态未知，不表示未运行。")
                    .font(.caption).foregroundStyle(.secondary)
                Table(store.visibleRecords, selection: $store.inspectedID) {
                    TableColumn("预演选择") { record in
                        Toggle("选择 \(record.name)", isOn: Binding(get: { store.selectedIDs.contains(record.id) }, set: { store.select(record, value: $0) }))
                            .labelsHidden().toggleStyle(.checkbox).disabled(!record.canSelect)
                            .help(record.actionLabel).accessibilityIdentifier("select.\(record.id)")
                    }.width(65)
                    TableColumn("软件名称") { record in
                        Label(record.name, systemImage: record.presence.symbol)
                            .foregroundStyle(record.presence == .highConfidenceOrphan ? Color.red : Color.primary)
                            .accessibilityIdentifier("record.\(record.id)")
                    }.width(min: 160, ideal: 210)
                    TableColumn("存在状态") { record in Text(record.presence.title) }.width(min: 100, ideal: 130)
                    TableColumn("登记 / 运行") { _ in Text("合成登记 / 未知").foregroundStyle(.secondary) }.width(115)
                    TableColumn("来源 / 范围") { record in VStack(alignment: .leading) { Text(record.source); Text(record.scope).font(.caption).foregroundStyle(.secondary) } }.width(min: 100, ideal: 150)
                    TableColumn("可用操作") { record in Text(record.actionLabel) }.width(min: 110, ideal: 140)
                }
                HStack {
                    Text("已选 \(store.selectedIDs.count) 项，其中 \(store.hiddenSelectedCount) 项当前隐藏")
                        .accessibilityIdentifier("selection.summary")
                    Button("查看全部已选") { store.showSelected() }.disabled(store.selectedIDs.isEmpty)
                    Spacer()
                    Button("检查所选操作（dry-run）") { store.makePlan() }
                        .disabled(store.selectedIDs.isEmpty).accessibilityIdentifier("review.open")
                }
            }
        }.padding(16)
    }
    private var filters: some View {
        VStack(alignment: .leading) {
            TextField("搜索名称、bundle ID 或路径", text: $store.search)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("records.search")
            HStack {
                Picker("状态", selection: $store.statusFilter) {
                    Text("全部").tag("全部")
                    ForEach(PresenceState.allCases, id: \.rawValue) { Text($0.title).tag($0.title) }
                }
                Picker("来源", selection: $store.sourceFilter) { ForEach(store.sourceOptions, id: \.self) { Text($0).tag($0) } }
                Picker("范围", selection: $store.scopeFilter) { ForEach(store.scopeOptions, id: \.self) { Text($0).tag($0) } }
                if store.onlySelected { Button("显示全部记录") { store.onlySelected = false } }
            }
        }
    }
}

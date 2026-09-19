import SwiftUI

struct RecordInspector: View {
    let record: DemoRecord?
    let loadedAt: Date?
    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 15) {
                    Label("合成记录详情", systemImage: "testtube.2").font(.headline)
                    Text(record.name).font(.title2)
                    field("存在状态", record.presence.title)
                    field("可用操作", record.actionLabel)
                    field("记录身份", record.id)
                    field("Bundle ID", record.bundleID)
                    field("Team ID / 签名", "未知 / 未验证（合成数据）")
                    field("路径（非真实文件）", record.path)
                    field("服务 Label", "synthetic.\(record.id)")
                    field("来源 / 用户范围", "\(record.source) / \(record.scope)")
                    field("来源文件", "Resources/demo-records.json")
                    field("归属证据与判定理由", record.reason)
                    field("实际影响身份", record.affectedIDs.joined(separator: "\n"))
                    field("登记 / 运行状态", "合成登记 / 未观测")
                    field("覆盖缺口", "真实提供器未运行；无任何本机存在性或操作能力证据。")
                    field("加载时间", loadedAt?.formatted() ?? "未知")
                }.padding().textSelection(.enabled)
            } else {
                ContentUnavailableView("记录详情", systemImage: "doc.text.magnifyingglass", description: Text("点击表格行查看证据。选中详情不会自动勾选预演操作。"))
            }
        }
    }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout) }
    }
}

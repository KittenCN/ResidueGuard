import SwiftUI

struct RecordInspector: View {
    let record: WorkspaceRecord?
    let loadedAt: Date?
    let retentionAvailable: Bool
    let retain: (WorkspaceRecord) -> Void
    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 15) {
                    Label(record.isSynthetic ? "合成记录详情" : "只读来源记录详情", systemImage: record.isSynthetic ? "testtube.2" : "doc.text").font(.headline)
                    Text(record.name).font(.title2)
                    field("存在状态", record.presence.title)
                    field("可用操作", record.actionLabel)
                    Button("保留这条记录30天") { retain(record) }
                        .disabled(!retentionAvailable || record.retentionObservation == nil || record.isRetained)
                        .accessibilityIdentifier("retention.add")
                    Text("只增加保护，不隐藏记录。来源内容变化或到期后失效；合成记录仅保留在本次会话。")
                        .font(.caption).foregroundStyle(.secondary)
                    field("记录身份", record.id)
                    field("Bundle ID", record.bundleID)
                    field("Team ID / 签名", "未知 / 未验证")
                    field(record.isSynthetic ? "路径（非真实文件）" : "目标路径", record.path)
                    field("来源原生身份", record.provenance?.id.nativeIdentity ?? "synthetic.\(record.id)")
                    field("来源 / 用户范围", "\(record.source) / \(record.scope)")
                    field("来源文件", record.provenance?.sourceArtifact ?? "Resources/demo-records.json")
                    field("归属证据与判定理由", record.reason)
                    field("实际影响身份", record.isSynthetic ? record.affectedIDs.joined(separator: "\n") : "尚未展开；真实写能力禁用，不能作为清理范围")
                    field("登记 / 运行状态", record.isSynthetic ? "合成登记 / 未观测" : "已读取来源配置 / 未验证")
                    field("能力限制", record.capabilityReason)
                    if let provenance = record.provenance {
                        field("扫描代次", provenance.generation)
                        field("解析警告", provenance.parseWarnings.isEmpty ? "无解析警告；不代表全系统覆盖完整" : provenance.parseWarnings.joined(separator: "\n"))
                        field("来源元数据（不执行内容）", provenance.rawMetadata.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                    }
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

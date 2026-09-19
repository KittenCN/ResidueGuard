import Foundation
import Observation
import ResidueCore

@MainActor @Observable
final class WorkspaceStore {
    var page: WorkspacePage = .overview {
        didSet {
            guard page != oldValue else { return }
            if !selectedIDs.isEmpty { notice = "已切换分类，清除了上一页的勾选。" }
            selectedIDs.removeAll(); inspectedID = nil; search = ""; statusFilter = "全部"; sourceFilter = "全部"; scopeFilter = "全部"; onlySelected = false
            review = nil
        }
    }
    private(set) var records: [DemoRecord] = []
    private(set) var isDemo = false
    private(set) var isLoading = false
    private(set) var loadedAt: Date?
    var selectedIDs: Set<String> = [] { didSet { review = nil } }
    var inspectedID: String?
    var search = ""
    var statusFilter = "全部"
    var sourceFilter = "全部"
    var scopeFilter = "全部"
    var onlySelected = false
    var notice = "尚未运行真实扫描；系统修改能力全部禁用。"
    var review: DryRunPlan?
    var showsReview = false
    private(set) var generation = UUID().uuidString
    var pageRecords: [DemoRecord] {
        records.filter { page == .applications || $0.page == page.rawValue }
    }
    var visibleRecords: [DemoRecord] {
        pageRecords.filter { record in
            (search.isEmpty || [record.name, record.bundleID, record.path].contains { $0.localizedCaseInsensitiveContains(search) }) &&
            (statusFilter == "全部" || record.presence.title == statusFilter) &&
            (sourceFilter == "全部" || record.source == sourceFilter) &&
            (scopeFilter == "全部" || record.scope == scopeFilter) &&
            (!onlySelected || selectedIDs.contains(record.id))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var hiddenSelectedCount: Int { selectedIDs.subtracting(visibleRecords.map(\.id)).count }
    var inspected: DemoRecord? { records.first { $0.id == inspectedID } }
    var sourceOptions: [String] { ["全部"] + Set(pageRecords.map(\.source)).sorted() }
    var scopeOptions: [String] { ["全部"] + Set(pageRecords.map(\.scope)).sorted() }

    func loadDemo() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let url = Bundle.main.url(forResource: "demo-records", withExtension: "json") else {
            notice = "演示资源缺失；未读取任何系统数据。"; return
        }
        do {
            let result = try await DemoLoader.load(from: url)
            guard !Task.isCancelled else { notice = "演示加载已取消。"; return }
            records = result; isDemo = true; loadedAt = Date(); generation = UUID().uuidString
            selectedIDs.removeAll(); inspectedID = nil
            notice = "已载入合成演示数据，不代表本机扫描结果。"
        } catch { notice = "演示加载失败：\(error.localizedDescription)" }
    }
    func unloadDemo() {
        records = []; isDemo = false; loadedAt = nil; generation = UUID().uuidString
        selectedIDs.removeAll(); inspectedID = nil; notice = "已退出演示；尚未运行真实扫描。"
    }
    func select(_ record: DemoRecord, value: Bool) {
        guard record.canSelect else { return }
        if value { selectedIDs.insert(record.id) } else { selectedIDs.remove(record.id) }
    }
    func showSelected() { search = ""; statusFilter = "全部"; sourceFilter = "全部"; scopeFilter = "全部"; onlySelected = true }
    func makePlan(expandedImpactApproved: Bool = false) {
        let snapshot = PlanSnapshot(generation: generation, osBuild: "synthetic", records: records.map {
            PlanningRecord(id: $0.id, operationKey: "synthetic.configuration.\($0.id)", affectedTargetIDs: $0.affectedIDs,
                capability: CapabilityDescriptor(profileID: "synthetic-demo-only", state: $0.preciseOperation ? .supportedVerified : .guidedOnly,
                    testedOSBuilds: ["synthetic"], reason: "仅用于合成策略预演，不赋予系统执行能力", operations: [.removeRegistration: $0.preciseOperation ? .supportedVerified : .guidedOnly]),
                fingerprint: "synthetic-v1:\($0.id)")
        }, targets: records.map {
            ImpactTarget(id: $0.id, displayName: $0.name, presence: $0.presence, isProtectedOrManaged: $0.protected,
                         fingerprint: "synthetic-v1:\($0.id)")
        }, observedAt: loadedAt ?? .distantPast)
        review = DryRunPlanner.makePlan(selectedRecordIDs: selectedIDs, snapshot: snapshot,
                                       expandedImpactApproved: expandedImpactApproved, now: Date())
        showsReview = true
    }
}

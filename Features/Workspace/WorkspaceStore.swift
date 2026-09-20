import Foundation
import Observation
import ResidueCore
import ResiduePlatform

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
    private var sourceRecords: [WorkspaceRecord] = []
    let retention = RetentionStore()
    private(set) var ownershipGraph: CandidateOwnershipGraph?
    private var lastProtectedIDs: Set<String> = []
    var retentionIsSessionOnly: Bool { isDemo || isSyntheticScan }
    var records: [WorkspaceRecord] {
        let rules = Dictionary(uniqueKeysWithValues: (retentionIsSessionOnly ? retention.sessionRules : retention.localRules).map { ($0.recordIdentity, $0) })
        let now = Date()
        return sourceRecords.map { source in
            var copy = source
            if let observation = source.retentionObservation, let identity = observation.identity, let rule = rules[identity] {
                copy.isRetained = RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: now) == .protected
            }
            return copy
        }
    }
    private(set) var isDemo = false
    private(set) var coverage: [ScanCoverage] = []
    private(set) var isScanning = false
    private(set) var cancellationRequested = false
    private(set) var isSyntheticScan = false
    private(set) var configuredLaunchRoots: [URL] = []
    private(set) var configuredApplicationRoots: [URL] = []
    private var scanTask: Task<Void, Never>?
    private var previousSourceRecords: [SourceRecord]?
    private let scanner: WorkspaceScanner
    init(scanner: WorkspaceScanner = .live, syntheticScan: Bool = false) {
        self.scanner = scanner; self.isSyntheticScan = syntheticScan
    }
    var hasSnapshot: Bool { loadedAt != nil }
    var modeTitle: String {
        if isDemo { return "演示模式 · 合成数据，非真实系统扫描" }
        if isSyntheticScan { return "测试注入 · 合成扫描结果，非本机数据" }
        return hasSnapshot ? "只读扫描结果 · 仅限声明范围" : "只读模式 · 尚未运行真实系统扫描"
    }
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
    var pageRecords: [WorkspaceRecord] {
        records.filter { page == .applications || $0.page == page.rawValue }
    }
    var visibleRecords: [WorkspaceRecord] {
        pageRecords.filter { record in
            (search.isEmpty || [record.name, record.bundleID, record.path].contains { $0.localizedCaseInsensitiveContains(search) }) &&
            (statusFilter == "全部" || record.presence.title == statusFilter) &&
            (sourceFilter == "全部" || record.source == sourceFilter) &&
            (scopeFilter == "全部" || record.scope == scopeFilter) &&
            (!onlySelected || selectedIDs.contains(record.id))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var hiddenSelectedCount: Int { selectedIDs.subtracting(visibleRecords.map(\.id)).count }
    var inspected: WorkspaceRecord? { records.first { $0.id == inspectedID } }
    var sourceOptions: [String] { ["全部"] + Set(pageRecords.map(\.source)).sorted() }
    var scopeOptions: [String] { ["全部"] + Set(pageRecords.map(\.scope)).sorted() }

    func loadDemo() async {
        guard !isLoading && !isScanning else { return }
        isLoading = true
        defer { isLoading = false }
        guard let url = Bundle.main.url(forResource: "demo-records", withExtension: "json") else {
            notice = "演示资源缺失；未读取任何系统数据。"; return
        }
        do {
            let result = try await DemoLoader.load(from: url)
            guard !Task.isCancelled else { notice = "演示加载已取消。"; return }
            previousSourceRecords = nil
            ownershipGraph = nil
            sourceRecords = result.map(WorkspaceRecord.init(demo:)); coverage = []; isDemo = true; loadedAt = Date(); generation = UUID().uuidString
            selectedIDs.removeAll(); inspectedID = nil
            notice = "已载入合成演示数据，不代表本机扫描结果。"
        } catch { notice = "演示加载失败：\(error.localizedDescription)" }
    }
    func unloadDemo() {
        ownershipGraph = nil
        previousSourceRecords = nil
        sourceRecords = []; coverage = []; isDemo = false; loadedAt = nil; generation = UUID().uuidString
        selectedIDs.removeAll(); inspectedID = nil; notice = "已退出演示；尚未运行真实扫描。"
    }

    func chooseRoots(applications: Bool) {
        guard !isScanning, !isLoading else { return }
        guard let urls = ScanAccess.chooseDirectories(applicationRoots: applications) else { return }
        guard urls.allSatisfy({ ScanAccess.isAllowedDirectory($0, applicationRoots: applications) }) else {
            notice = "所选目录不属于允许的只读范围。启动配置限本用户 LaunchAgents 或系统/共享标准目录；应用索引限本用户目录、/Applications 或 /System/Applications。"; return
        }
        if applications { configuredApplicationRoots = urls } else { configuredLaunchRoots = urls }
        notice = "扫描目录已更新；点击只读扫描后才会读取。授权不持久化。"
    }
    func startScan() {
        guard !isScanning, !isLoading else { return }
        guard isSyntheticScan || !configuredLaunchRoots.isEmpty else {
            notice = "请先选择启动配置目录，明确授权只读范围。"; return
        }
        ownershipGraph = nil
        sourceRecords = []; coverage = []; isDemo = false; loadedAt = nil
        selectedIDs.removeAll(); inspectedID = nil; review = nil; showsReview = false
        generation = UUID().uuidString
        let requestedGeneration = generation
        isScanning = true; cancellationRequested = false
        notice = "正在只读采集；旧结果已清除，未访问的目录不会计为空。"
        let roots = configuredLaunchRoots
        let apps = configuredApplicationRoots
        let configuration = ScanConfiguration(launchRoots: roots.map {
            ScanRoot(url: $0, scope: $0.lastPathComponent == "LaunchDaemons" ? "systemDaemons" : ($0.path.hasPrefix("/Library/") || $0.path.hasPrefix("/System/") ? "sharedAgents" : "currentUser"))
        }, applicationRoots: apps)
        let accessURLs = roots + apps
        let granted = accessURLs.filter { $0.startAccessingSecurityScopedResource() }
        scanTask = Task {
            defer {
                granted.forEach { $0.stopAccessingSecurityScopedResource() }
                isScanning = false; scanTask = nil
            }
            let snapshot = await scanner.scan(configuration)
            guard generation == requestedGeneration else { return }
            sourceRecords = snapshot.rows.map(WorkspaceRecord.init(scan:))
            ownershipGraph = snapshot.ownershipGraph
            coverage = snapshot.coverage; loadedAt = snapshot.observedAt
            generation = snapshot.generation
            let currentSources = snapshot.rows.map(\.record)
            let comparison = previousSourceRecords.map { SnapshotComparison.compare(previous: $0, current: currentSources) }
            previousSourceRecords = currentSources
            notice = cancellationRequested
                ? "扫描已取消；显示已返回的部分结果。未访问范围不代表没有记录。"
                : "已完成本次只读采集；请检查来源覆盖与未验证范围。所有系统修改仍禁用。"
            if let comparison {
                notice += " 本次新增观察 \(comparison.added.count)、变化 \(comparison.changed.count)、未再次观察到 \(comparison.notObserved.count)（不代表已删除）、身份冲突 \(comparison.ambiguous.count)。"
            }
        }
    }
    func cancelScan() {
        guard isScanning else { return }
        cancellationRequested = true
        notice = "已请求取消；正在收拢部分结果。"
        scanTask?.cancel()
    }
    func select(_ record: WorkspaceRecord, value: Bool) {
        guard !retention.isBusy, record.canSelect else { return }
        if value { selectedIDs.insert(record.id) } else { selectedIDs.remove(record.id) }
    }
    func showSelected() { search = ""; statusFilter = "全部"; sourceFilter = "全部"; scopeFilter = "全部"; onlySelected = true }
    func makePlan(expandedImpactApproved: Bool = false) {
        guard isDemo && !isScanning && !retention.isBusy else { review = nil; showsReview = false; return }
        let snapshot = PlanSnapshot(generation: generation, osBuild: "synthetic", records: records.map {
            PlanningRecord(id: $0.id, operationKey: "synthetic.configuration.\($0.id)", affectedTargetIDs: $0.affectedIDs,
                capability: CapabilityDescriptor(profileID: "synthetic-demo-only", state: $0.preciseOperation ? .supportedVerified : .guidedOnly,
                    testedOSBuilds: ["synthetic"], reason: "仅用于合成策略预演，不赋予系统执行能力", operations: [.removeRegistration: $0.preciseOperation ? .supportedVerified : .guidedOnly]),
                fingerprint: "synthetic-v1:\($0.id)")
        }, targets: records.map {
            ImpactTarget(id: $0.id, displayName: $0.name, presence: $0.presence, isProtectedOrManaged: $0.protected || $0.isRetained,
                         fingerprint: "synthetic-v1:\($0.id)")
        }, observedAt: loadedAt ?? .distantPast)
        review = DryRunPlanner.makePlan(selectedRecordIDs: selectedIDs, snapshot: snapshot,
                                       expandedImpactApproved: expandedImpactApproved, now: Date())
        showsReview = true
    }
}

extension WorkspaceStore {
    func refreshRetentionProtection() {
        guard !isScanning else { return }
        let current = Set(records.filter(\.isRetained).map(\.id))
        guard current != lastProtectedIDs else { return }
        lastProtectedIDs = current
        invalidateRetentionSelection()
    }
    private func invalidateRetentionSelection() {
        selectedIDs.removeAll(); review = nil; showsReview = false
        generation = UUID().uuidString
    }
    func retainRecord(_ record: WorkspaceRecord) async {
        guard !isScanning, !isLoading else { return }
        guard let observation = record.retentionObservation,
              let identity = observation.identity, let fingerprint = observation.fingerprint else { return }
        invalidateRetentionSelection()
        await retention.add(identity: identity, fingerprint: fingerprint, sessionOnly: retentionIsSessionOnly)
        refreshRetentionProtection()
        notice = retention.message
    }
    func removeRetentionRule(_ rule: RetentionRule, sessionOnly: Bool) async {
        guard !isScanning, !isLoading else { return }
        invalidateRetentionSelection()
        await retention.remove(rule, sessionOnly: sessionOnly)
        refreshRetentionProtection()
        notice = retention.message
    }
    func retentionState(_ rule: RetentionRule, sessionOnly: Bool, now: Date) -> RetentionMatchState {
        let observation = sessionOnly == retentionIsSessionOnly
            ? sourceRecords.compactMap(\.retentionObservation).first(where: { $0.identity == rule.recordIdentity }) : nil
        return RetentionRuleMatcher.evaluate(rule: rule, observation: observation, now: now)
    }
}

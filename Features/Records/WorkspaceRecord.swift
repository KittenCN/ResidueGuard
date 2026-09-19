import Foundation
import ResidueCore
import ResiduePlatform

/// Source-aware presentation: synthetic policy fixtures never become live evidence.
struct WorkspaceRecord: Identifiable, Sendable {
    let id: String
    let name: String
    let page: String
    let presence: PresenceState
    let bundleID: String
    let path: String
    let source: String
    let scope: String
    let reason: String
    let protected: Bool
    let preciseOperation: Bool
    let affectedIDs: [String]
    let isSynthetic: Bool
    let provenance: SourceRecord?
    let capabilityReason: String
    var canSelect: Bool {
        isSynthetic && !protected && preciseOperation && (presence == .present || presence == .highConfidenceOrphan)
    }
    var actionLabel: String {
        if !isSynthetic { return "只读 · 系统修改禁用" }
        if protected { return "受保护，禁止操作" }
        if !preciseOperation { return "需系统设置处理" }
        return canSelect ? "仅可预演" : "证据不足，禁止操作"
    }
    init(demo: DemoRecord) {
        id = demo.id; name = demo.name; page = demo.page; presence = demo.presence
        bundleID = demo.bundleID; path = demo.path; source = demo.source; scope = demo.scope
        reason = demo.reason; protected = demo.protected; preciseOperation = demo.preciseOperation
        affectedIDs = demo.affectedIDs; isSynthetic = true; provenance = nil
        capabilityReason = "仅用于合成策略预演，不赋予系统执行能力"
    }
    init(scan: ScanRow) {
        let record = scan.record
        // Length-delimited components avoid collisions from separators inside native identities.
        id = [record.id.providerID, record.id.scope, record.id.nativeIdentity].map { "\($0.utf8.count):\($0)" }.joined()
        name = record.displayName; presence = scan.presence; bundleID = record.declaredAppIDs.joined(separator: "、")
        path = record.targetReferences.joined(separator: "\n"); source = record.id.providerID; scope = record.id.scope
        switch record.id.providerID == "launchd.configuration" ? "launchConfiguration" : record.category {
        case "backgroundItems", "background": page = WorkspacePage.backgroundItems.rawValue
        case "loginItems", "login": page = WorkspacePage.loginItems.rawValue
        default:
            if record.sourceArtifact.contains("/LaunchDaemons/") { page = WorkspacePage.daemons.rawValue }
            else if record.id.scope == "sharedAgents" || record.id.scope == "system" { page = WorkspacePage.sharedAgents.rawValue }
            else { page = WorkspacePage.userAgents.rawValue }
        }
        reason = (scan.evidence + record.parseWarnings).joined(separator: "\n")
        protected = false; preciseOperation = false; affectedIDs = []
        isSynthetic = false; provenance = record; capabilityReason = scan.capability.reason
    }
}

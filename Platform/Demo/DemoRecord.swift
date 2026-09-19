import Foundation
import ResidueCore

/// Presentation metadata for explicitly opted-in synthetic records only.
struct DemoRecord: Codable, Identifiable, Sendable {
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

}

extension PresenceState {
    var title: String {
        switch self {
        case .present: "已安装"
        case .highConfidenceOrphan: "高可信残留"
        case .suspectedOrphan: "疑似残留"
        case .unknown: "归属未知"
        case .volumeUnavailable: "原卷未连接"
        case .inTrash: "尚在废纸篓"
        case .sharedComponentActive: "其他应用仍在使用"
        case .permissionDenied: "未能核实：无访问权限"
        }
    }
    var symbol: String {
        switch self {
        case .present: "checkmark.circle"
        case .highConfidenceOrphan: "exclamationmark.triangle.fill"
        case .volumeUnavailable: "externaldrive.badge.questionmark"
        default: "questionmark.circle"
        }
    }
}

struct DemoEnvelope: Decodable, Sendable {
    let fixtureType: String
    let records: [DemoRecord]
}

enum DemoLoader {
    static func load(from url: URL) async throws -> [DemoRecord] {
        try await Task.detached(priority: .userInitiated) {
            let envelope = try JSONDecoder().decode(DemoEnvelope.self, from: Data(contentsOf: url))
            guard envelope.fixtureType == "synthetic-not-user-data" else { throw CocoaError(.fileReadCorruptFile) }
            return envelope.records
        }.value
    }
}

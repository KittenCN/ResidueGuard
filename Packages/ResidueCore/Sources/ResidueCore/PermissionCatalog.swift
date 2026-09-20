import Foundation

public enum PermissionCategory: String, CaseIterable, Codable, Sendable {
    case accessibility, fullDisk, screen, input, camera, microphone, automation, files
    case contacts, calendars, reminders, photos, bluetooth, speech, developer
    case network, location, notifications, unknown

    public var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .fullDisk: "完全磁盘访问"
        case .screen: "屏幕与系统音频录制"
        case .input: "输入监控"
        case .camera: "摄像头"
        case .microphone: "麦克风"
        case .automation: "自动化"
        case .files: "文件与文件夹"
        case .contacts: "通讯录"
        case .calendars: "日历"
        case .reminders: "提醒事项"
        case .photos: "照片"
        case .bluetooth: "蓝牙"
        case .speech: "语音识别"
        case .developer: "开发者工具"
        case .network: "本地网络"
        case .location: "定位"
        case .notifications: "通知"
        case .unknown: "其他与未知权限"
        }
    }
}
public enum PermissionMechanism: String, Codable, Sendable {
    case privacyFramework, localNetwork, locationServices, userNotifications, unknown
}
public enum PermissionScopeShape: String, Codable, Sendable {
    case applicationCategory, callerTargetRelationship, resourceSubset, independentMechanism, unknown
}
public struct PermissionCategoryDescriptor: Sendable {
    public let category: PermissionCategory
    public let mechanism: PermissionMechanism
    public let scope: PermissionScopeShape
    public let guidance: String
    public let limitation: String
    /// No private token discovery or assumed tccutil service spelling is provided.
    public var resetServiceToken: String? { nil }
}
public enum PermissionCatalog {
    public static var all: [PermissionCategoryDescriptor] { PermissionCategory.allCases.map(descriptor) }
    public static func descriptor(_ category: PermissionCategory) -> PermissionCategoryDescriptor {
        let mechanism: PermissionMechanism
        let scope: PermissionScopeShape
        switch category {
        case .network: mechanism = .localNetwork; scope = .independentMechanism
        case .location: mechanism = .locationServices; scope = .independentMechanism
        case .notifications: mechanism = .userNotifications; scope = .independentMechanism
        case .unknown: mechanism = .unknown; scope = .unknown
        case .automation: mechanism = .privacyFramework; scope = .callerTargetRelationship
        case .files, .photos, .contacts: mechanism = .privacyFramework; scope = .resourceSubset
        default: mechanism = .privacyFramework; scope = .applicationCategory
        }
        let guidance: String
        switch category {
        case .unknown:
            guidance = "打开系统设置，按来源描述查找对应类别；无法识别时保留记录并手动核对。系统设置不存在统一的‘其他与未知权限’页面。"
        case .notifications:
            guidance = "打开 系统设置 → 通知，手动检查对应应用。"
        case .location:
            guidance = "打开 系统设置 → 隐私与安全性 → 定位服务，手动检查对应应用。"
        default:
            guidance = "打开 系统设置 → 隐私与安全性 → \(category.title)，手动核对。页面名称可能随系统版本变化。"
        }
        let limitation: String
        switch scope {
        case .callerTargetRelationship:
            limitation = "自动化保留调用者 → 被控制者关系。若底层能力影响调用者的全部关系，必须完整展开影响集合并重新批准；影响不明时阻断。"
        case .resourceSubset:
            limitation = "授权可能只覆盖部分资源；允许、拒绝、受限、受管理和未知状态不得合并。页面分类不保证对应单一操作范围。"
        case .independentMechanism:
            limitation = "此类别使用独立机制，不套用猜测的 TCC service 名称，不提供重置操作。"
        case .unknown:
            limitation = "无法识别的类别不猜测服务名称、设置页面或操作范围。"
        case .applicationCategory:
            limitation = "本应用自身权限查询不代表第三方应用完整清单；登记状态也不等于实时有效访问能力。"
        }
        return .init(category: category, mechanism: mechanism, scope: scope, guidance: guidance, limitation: limitation)
    }
}

public struct PermissionCapabilityProfile: Sendable {
    public let enumeration: CapabilityState
    public let guidance: CapabilityState
    public let targetedReset: CapabilityState
    public let legacyDatabaseRead: CapabilityState
    public let reason: String
}
public enum PermissionCapabilityRegistry {
    /// These are guidance profiles only, not proof of OS enumeration or reset support.
    public static func profile(category: PermissionCategory, osMajorVersion: Int, recognizedEnvironment: Bool) -> PermissionCapabilityProfile {
        let known = recognizedEnvironment && [14, 15, 26, 27].contains(osMajorVersion) && category != .unknown
        return .init(enumeration: known ? .unsupported : .blockedByPolicy,
                     guidance: .guidedOnly, targetedReset: .blockedByPolicy,
                     legacyDatabaseRead: osMajorVersion >= 27 || !known ? .blockedByPolicy : .unverified,
                     reason: known ? "没有已验证的第三方完整清单提供器或精确重置适配器；仅提供手动指引。" : "系统、build 或来源未验证；自动读取和操作保持阻断，手动指引仍可用。")
    }
}

public enum PermissionObservationOrigin: String, Codable, Sendable { case live, importedHistorical }
public struct PermissionObservation: Codable, Sendable {
    public let category: PermissionCategory
    public let clientIdentity: String
    public let indirectTargetIdentity: String?
    public let observedAt: Date
    public let origin: PermissionObservationOrigin
    public init(category: PermissionCategory, clientIdentity: String, indirectTargetIdentity: String? = nil, observedAt: Date, origin: PermissionObservationOrigin) {
        self.category = category; self.clientIdentity = clientIdentity; self.indirectTargetIdentity = indirectTargetIdentity
        self.observedAt = observedAt; self.origin = origin
    }
    public var isCurrent: Bool { origin == .live }
    /// Observation alone never authorizes mutation, including when freshly collected.
    public var authorizesMutation: Bool { false }
}
public enum PermissionBackendScope: Sendable { case exactSelection, callerCategory, globalReset }
public enum PermissionImpactReview: Equatable, Sendable {
    case blocked(String)
    case needsExpandedApproval(Set<String>)
    /// Only suitable for a later capability/confirmation planner. This is not execution consent.
    case reviewable(Set<String>)
}
public enum PermissionImpactPolicy {
    public static func review(selected: Set<String>, actualAffected: Set<String>?, approvedImpact: Set<String>?,
                              backendScope: PermissionBackendScope, origin: PermissionObservationOrigin) -> PermissionImpactReview {
        guard origin == .live else { return .blocked("历史快照不代表当前状态，不能作为写操作依据") }
        guard backendScope != .globalReset else { return .blocked("禁止全量重置") }
        guard !selected.isEmpty, selected.allSatisfy({ !$0.isEmpty }),
              let actualAffected, !actualAffected.isEmpty, actualAffected.allSatisfy({ !$0.isEmpty }),
              selected.isSubset(of: actualAffected) else { return .blocked("实际影响集合不完整或身份不匹配") }
        if backendScope == .exactSelection && actualAffected != selected {
            return .blocked("操作声明的精确范围与实际影响不符")
        }
        if actualAffected != selected && approvedImpact != actualAffected {
            return .needsExpandedApproval(actualAffected)
        }
        if let approvedImpact, approvedImpact != actualAffected {
            return .blocked("影响集合改变，旧批准失效")
        }
        return .reviewable(actualAffected)
    }
}

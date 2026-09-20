import Foundation
import Testing
@testable import ResidueCore

@Test func permissionCatalogHasDistinctMechanismsAndHonestRoutes() {
    #expect(PermissionCatalog.all.count == 19)
    #expect(Set(PermissionCatalog.all.map(\.category)).count == 19)
    #expect(PermissionCatalog.all.allSatisfy { $0.resetServiceToken == nil && !$0.guidance.isEmpty })
    #expect(PermissionCatalog.descriptor(.network).mechanism == .localNetwork)
    #expect(PermissionCatalog.descriptor(.location).mechanism == .locationServices)
    #expect(PermissionCatalog.descriptor(.notifications).mechanism == .userNotifications)
    #expect(PermissionCatalog.descriptor(.automation).scope == .callerTargetRelationship)
    #expect(!PermissionCatalog.descriptor(.unknown).guidance.contains("→ 其他"))
    #expect(PermissionCatalog.descriptor(.location).guidance.contains("定位服务"))
}
@Test func permissionProfilesNeverEnableUnverifiedReadOrReset() {
    for category in PermissionCategory.allCases {
        for version in [13, 14, 15, 16, 25, 26, 27, 28] {
            for known in [true, false] {
                let profile = PermissionCapabilityRegistry.profile(category: category, osMajorVersion: version, recognizedEnvironment: known)
                #expect(profile.enumeration != .supportedVerified)
                #expect(profile.guidance == .guidedOnly)
                #expect(profile.targetedReset == .blockedByPolicy)
                #expect(profile.legacyDatabaseRead != .supportedVerified)
                if version >= 27 || !known { #expect(profile.legacyDatabaseRead == .blockedByPolicy) }
                if ![14, 15, 26, 27].contains(version) || !known || category == .unknown { #expect(profile.enumeration == .blockedByPolicy) }
            }
        }
    }
}
@Test func historicalPermissionRecordsNeverAuthorizeCurrentChanges() {
    let historical = PermissionObservation(category: .automation, clientIdentity: "synthetic.caller", indirectTargetIdentity: "synthetic.target", observedAt: .distantPast, origin: .importedHistorical)
    #expect(!historical.isCurrent)
    #expect(!historical.authorizesMutation)
    let live = PermissionObservation(category: .camera, clientIdentity: "synthetic.live", observedAt: Date(), origin: .live)
    #expect(live.isCurrent)
    #expect(!live.authorizesMutation)
    #expect(PermissionImpactPolicy.review(selected: ["one"], actualAffected: ["one"], approvedImpact: ["one"], backendScope: .exactSelection, origin: .importedHistorical) == .blocked("历史快照不代表当前状态，不能作为写操作依据"))
}
@Test func permissionImpactExpansionCannotSilentlyResetAllRelationships() {
    let actual: Set<String> = ["caller-targetA", "caller-targetB"]
    #expect(PermissionImpactPolicy.review(selected: [], actualAffected: [], approvedImpact: [], backendScope: .exactSelection, origin: .live) == .blocked("实际影响集合不完整或身份不匹配"))
    #expect(PermissionImpactPolicy.review(selected: ["missing"], actualAffected: actual, approvedImpact: actual, backendScope: .callerCategory, origin: .live) == .blocked("实际影响集合不完整或身份不匹配"))
    #expect(PermissionImpactPolicy.review(selected: [""], actualAffected: [""], approvedImpact: [""], backendScope: .exactSelection, origin: .live) == .blocked("实际影响集合不完整或身份不匹配"))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: actual, approvedImpact: nil, backendScope: .callerCategory, origin: .live) == .needsExpandedApproval(actual))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: actual, approvedImpact: ["caller-targetA"], backendScope: .callerCategory, origin: .live) == .needsExpandedApproval(actual))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: actual, approvedImpact: actual, backendScope: .callerCategory, origin: .live) == .reviewable(actual))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: nil, approvedImpact: actual, backendScope: .callerCategory, origin: .live) == .blocked("实际影响集合不完整或身份不匹配"))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: actual, approvedImpact: actual, backendScope: .globalReset, origin: .live) == .blocked("禁止全量重置"))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: actual, approvedImpact: actual, backendScope: .exactSelection, origin: .live) == .blocked("操作声明的精确范围与实际影响不符"))
    #expect(PermissionImpactPolicy.review(selected: ["caller-targetA"], actualAffected: ["caller-targetA"], approvedImpact: actual, backendScope: .exactSelection, origin: .live) == .blocked("影响集合改变，旧批准失效"))
}

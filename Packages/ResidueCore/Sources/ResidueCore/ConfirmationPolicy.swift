import Foundation

public enum ConfirmationRequirement: String, Codable, Sendable { case noAction, blocked, one, two }
public struct ConfirmationInput: Codable, Sendable {
    public let selectedRecordCount: Int
    public let affectedPresence: [String]
    public let allOperationsSupported: Bool
    public let hasProtectedOrManagedTarget: Bool
    public let scopeBounded: Bool
    public let expandedImpactExplicitlyApproved: Bool
    public let planFresh: Bool
    public init(selectedRecordCount: Int, affectedPresence: [String], allOperationsSupported: Bool,
                hasProtectedOrManagedTarget: Bool, scopeBounded: Bool,
                expandedImpactExplicitlyApproved: Bool, planFresh: Bool) {
        self.selectedRecordCount = selectedRecordCount; self.affectedPresence = affectedPresence
        self.allOperationsSupported = allOperationsSupported; self.hasProtectedOrManagedTarget = hasProtectedOrManagedTarget
        self.scopeBounded = scopeBounded; self.expandedImpactExplicitlyApproved = expandedImpactExplicitlyApproved; self.planFresh = planFresh
    }
}
public enum ConfirmationPolicy {
    public static let version = "p1-dry-run-1"
    public static func evaluate(_ input: ConfirmationInput) -> ConfirmationRequirement {
        if input.selectedRecordCount == 0 { return .noAction }
        guard input.selectedRecordCount > 0, input.allOperationsSupported,
              !input.hasProtectedOrManagedTarget, input.scopeBounded,
              input.expandedImpactExplicitlyApproved, input.planFresh,
              !input.affectedPresence.isEmpty,
              input.affectedPresence.allSatisfy({ $0 == "present" || $0 == "highConfidenceOrphan" }) else { return .blocked }
        return input.affectedPresence.contains("present") ? .two : .one
    }
}

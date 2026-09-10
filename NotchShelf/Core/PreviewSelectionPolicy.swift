import Foundation

enum PreviewSelectionPolicy {
    static func isManaged(
        itemID: String,
        rule: MenuItemRule,
        isProtected: Bool,
        automaticAvoidanceEnabled: Bool,
        automaticManagedIDs: Set<String>
    ) -> Bool {
        guard !isProtected else { return false }

        switch rule {
        case .automatic:
            return automaticAvoidanceEnabled && automaticManagedIDs.contains(itemID)
        case .alwaysVisible:
            return false
        case .alwaysHidden:
            return true
        }
    }
}

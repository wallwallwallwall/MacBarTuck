import Foundation

enum MenuItemVisibility: Equatable {
    case visible, hidden, partial, unknown

    static func evaluate(_ visibleCopies: [Bool?]) -> MenuItemVisibility {
        guard !visibleCopies.isEmpty, visibleCopies.allSatisfy({ $0 != nil }) else { return .unknown }
        if visibleCopies.allSatisfy({ $0 == false }) { return .hidden }
        if visibleCopies.allSatisfy({ $0 == true }) { return .visible }
        return .partial
    }
}

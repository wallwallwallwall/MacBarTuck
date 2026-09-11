enum ActivationPresentation: Equatable {
    case leaveLayoutUnchanged
    case keepVisibleUntilRetucked
}

enum MenuBarInteractionPolicy {
    static func activationPresentation(didRevealItem: Bool, isManaged: Bool,
                                       layoutEnabled: Bool) -> ActivationPresentation {
        guard didRevealItem, isManaged, layoutEnabled else { return .leaveLayoutUnchanged }
        return .keepVisibleUntilRetucked
    }

    static func allowsHoverReveal(enabled: Bool, isApplyingLayout: Bool,
                                  isShowingContextMenu: Bool, isSuppressed: Bool) -> Bool {
        enabled && !isApplyingLayout && !isShowingContextMenu && !isSuppressed
    }

    static func allowsAutomaticLayout(hasTemporarilyVisibleItems: Bool) -> Bool {
        !hasTemporarilyVisibleItems
    }
}

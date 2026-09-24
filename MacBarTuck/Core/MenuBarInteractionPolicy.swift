import Foundation

enum ActivationPresentation: Equatable {
    case leaveLayoutUnchanged
    case keepVisibleUntilRetucked
}

final class HoverRevealDelayController {
    typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void

    static let preferenceKey = "hoverRevealDelaySeconds"
    static let defaultDelay: TimeInterval = 1.5
    static let minimumDelay: TimeInterval = 0.5
    static let maximumDelay: TimeInterval = 5.0

    private let scheduler: Scheduler
    private var cancelScheduledAction: (() -> Void)?
    private var generation = 0

    init(schedule: @escaping Scheduler) {
        scheduler = schedule
    }

    var hasPendingReveal: Bool { cancelScheduledAction != nil }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        generation &+= 1
        let scheduledGeneration = generation
        cancelScheduledAction = scheduler(Self.normalizedDelay(delay)) { [weak self] in
            guard let self, self.generation == scheduledGeneration else { return }
            self.cancelScheduledAction = nil
            action()
        }
    }

    func cancel() {
        generation &+= 1
        let cancellation = cancelScheduledAction
        cancelScheduledAction = nil
        cancellation?()
    }

    static func normalizedDelay(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultDelay }
        return min(max(value, minimumDelay), maximumDelay)
    }
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

    static func shouldDeferLayout(isAutomatic: Bool, leftButtonPressed: Bool,
                                  rightButtonPressed: Bool) -> Bool {
        isAutomatic && (leftButtonPressed || rightButtonPressed)
    }
}

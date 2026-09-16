import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private final class AssessmentHandle: NSObject {
    let id: Int
    init(id: Int) { self.id = id }
}

@MainActor
private final class AssessmentRuntimeFixture: MenuBarAssessmentRuntime {
    var isAvailable = true
    private(set) var configurations = [MenuBarAssessmentConfiguration]()
    private(set) var handles = [AssessmentHandle]()
    private(set) var invalidatedHandleIDs = [Int]()
    private var completions = [(NSError?) -> Void]()

    func makeConfiguration(_ configuration: MenuBarAssessmentConfiguration) -> AnyObject? {
        configurations.append(configuration)
        return NSObject()
    }

    func makeAssertion() -> AnyObject? {
        let handle = AssessmentHandle(id: handles.count + 1)
        handles.append(handle)
        return handle
    }

    func activate(
        _ assertion: AnyObject,
        configuration: AnyObject,
        completion: @escaping (NSError?) -> Void
    ) {
        completions.append(completion)
    }

    func invalidate(_ assertion: AnyObject) {
        if let handle = assertion as? AssessmentHandle {
            invalidatedHandleIDs.append(handle.id)
        }
    }

    func finishLatest(error: NSError? = nil) {
        completions.removeLast()(error)
    }
}

@main
@MainActor
private enum MenuBarAssessmentModeTests {
    static func main() async throws {
        try planningUsesHostBundleAndSynchronizesSiblings()
        try temporarilyVisibleSiblingRevealsWholeBundle()
        try await controllerSwapsAssertionsWithoutDroppingLastGoodState()
        print("MenuBarAssessmentModeTests: bundle plans and assertion lifecycle passed")
    }

    private static func planningUsesHostBundleAndSynchronizesSiblings() throws {
        let items = [
            MenuBarAssessmentItem(
                id: "sensor",
                resolvedBundleIdentifier: "com.bjango.istatmenus",
                hostBundleIdentifier: "com.bjango.istatmenus.status",
                isSelected: false,
                isProtected: false,
                isTemporarilyVisible: false
            ),
            MenuBarAssessmentItem(
                id: "cpu",
                resolvedBundleIdentifier: "com.bjango.istatmenus",
                hostBundleIdentifier: "com.bjango.istatmenus.status",
                isSelected: true,
                isProtected: false,
                isTemporarilyVisible: false
            ),
            MenuBarAssessmentItem(
                id: "chatgpt",
                resolvedBundleIdentifier: "com.openai.codex",
                hostBundleIdentifier: nil,
                isSelected: false,
                isProtected: false,
                isTemporarilyVisible: false
            ),
            MenuBarAssessmentItem(
                id: "unresolved",
                resolvedBundleIdentifier: nil,
                hostBundleIdentifier: nil,
                isSelected: true,
                isProtected: false,
                isTemporarilyVisible: false
            )
        ]
        let expanded = MenuBarAssessmentModePolicy.expandedManagedItemIDs(
            items: items,
            managedItemIDs: ["cpu", "unresolved"]
        )
        try expect(expanded == ["sensor", "cpu", "unresolved"],
                   "Selecting one item must synchronize every item hosted by the same bundle.")

        let plan = MenuBarAssessmentModePolicy.plan(
            items: items,
            runningBundleIdentifiers: [
                "com.bjango.istatmenus.status", "com.openai.codex", "com.bartuck.app"
            ],
            ownBundleIdentifier: "com.bartuck.app"
        )
        try expect(plan.hiddenBundleIdentifiers == ["com.bjango.istatmenus.status"],
                   "The host process bundle must drive assessment-mode hiding.")
        try expect(plan.hiddenItemIDs == ["sensor", "cpu"],
                   "All status items from a hidden host bundle must share the actual hidden state.")
        try expect(plan.unresolvedSelectedItemIDs == ["unresolved"],
                   "Selected items without a host bundle must fail closed instead of hiding unrelated apps.")
        try expect(!plan.allowedBundleIdentifiers.contains("com.bjango.istatmenus.status") &&
                   plan.allowedBundleIdentifiers.contains("com.openai.codex") &&
                   plan.allowedBundleIdentifiers.contains("com.bartuck.app"),
                   "The allowlist must remove only hidden hosts and always retain MacBarTuck.")
    }

    private static func temporarilyVisibleSiblingRevealsWholeBundle() throws {
        let items = [
            MenuBarAssessmentItem(
                id: "sensor",
                resolvedBundleIdentifier: "com.bjango.istatmenus",
                hostBundleIdentifier: "com.bjango.istatmenus.status",
                isSelected: true,
                isProtected: false,
                isTemporarilyVisible: true
            ),
            MenuBarAssessmentItem(
                id: "cpu",
                resolvedBundleIdentifier: "com.bjango.istatmenus",
                hostBundleIdentifier: "com.bjango.istatmenus.status",
                isSelected: true,
                isProtected: false,
                isTemporarilyVisible: false
            )
        ]
        let plan = MenuBarAssessmentModePolicy.plan(
            items: items,
            runningBundleIdentifiers: ["com.bjango.istatmenus.status", "com.bartuck.app"],
            ownBundleIdentifier: "com.bartuck.app"
        )
        try expect(plan.hiddenBundleIdentifiers.isEmpty && plan.hiddenItemIDs.isEmpty,
                   "Temporarily revealing one item must reveal its whole host bundle.")
    }

    private static func controllerSwapsAssertionsWithoutDroppingLastGoodState() async throws {
        let runtime = AssessmentRuntimeFixture()
        var scheduledTimeouts = [() -> Void]()
        let controller = MenuBarAssessmentModeController(
            runtime: runtime,
            scheduleTimeout: { _, work in scheduledTimeouts.append(work) }
        )
        let first = MenuBarAssessmentConfiguration(
            allowedSystemItems: Array(0...8),
            allowedBundleIdentifiers: ["com.bartuck.app", "com.openai.codex"]
        )
        let second = MenuBarAssessmentConfiguration(
            allowedSystemItems: Array(0...8),
            allowedBundleIdentifiers: ["com.bartuck.app"]
        )
        let third = MenuBarAssessmentConfiguration(
            allowedSystemItems: Array(0...8),
            allowedBundleIdentifiers: ["com.bartuck.app", "com.tencent.xinWeChat"]
        )

        var results = [MenuBarAssessmentApplyResult]()
        controller.apply(first) { results.append($0) }
        runtime.finishLatest()
        await settleMainActorTasks()
        try expect(results == [.applied(changed: true)] && controller.activeConfiguration == first,
                   "The first accepted assertion must become active.")

        controller.apply(first) { results.append($0) }
        try expect(results.last == .applied(changed: false) && runtime.handles.count == 1,
                   "Reapplying the same allowlist must be a no-op.")

        controller.apply(second) { results.append($0) }
        runtime.finishLatest(error: NSError(domain: "fixture", code: 1))
        await settleMainActorTasks()
        try expect(controller.activeConfiguration == first,
                   "A rejected replacement must retain the last valid assertion.")
        try expect(runtime.invalidatedHandleIDs == [2],
                   "Only the rejected replacement should be invalidated.")

        controller.apply(third) { results.append($0) }
        runtime.finishLatest()
        await settleMainActorTasks()
        try expect(controller.activeConfiguration == third,
                   "A successful replacement must publish the new configuration.")
        try expect(runtime.invalidatedHandleIDs == [2, 1],
                   "The old valid assertion must be released only after replacement succeeds.")

        controller.apply(second) { results.append($0) }
        scheduledTimeouts.last?()
        await settleMainActorTasks()
        try expect(results.last == .timedOut && controller.activeConfiguration == third,
                   "A timed-out replacement must leave the previous assertion active.")
        try expect(runtime.invalidatedHandleIDs == [2, 1, 4],
                   "A timed-out pending assertion must be invalidated.")

        controller.invalidate()
        try expect(controller.activeConfiguration == nil && runtime.invalidatedHandleIDs == [2, 1, 4, 3],
                   "Explicit restore must release the active assertion.")
    }

    private static func settleMainActorTasks() async {
        for _ in 0..<3 { await Task.yield() }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(description: message) }
    }
}

import AppKit

private struct MaskControllerTestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class FakeMaskWindow: MenuBarMaskWindow {
    private(set) var maskFrame: CGRect
    private(set) var isMaskVisible = false
    private(set) var setFrameCount = 0
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var closeCount = 0

    init(frame: CGRect) {
        maskFrame = frame
    }

    func setMaskFrame(_ frame: CGRect) {
        maskFrame = frame
        setFrameCount += 1
    }

    func showMask() {
        isMaskVisible = true
        showCount += 1
    }

    func hideMask() {
        isMaskVisible = false
        hideCount += 1
    }

    func closeMask() {
        isMaskVisible = false
        closeCount += 1
    }
}

@main
@MainActor
private enum MenuBarMaskingControllerTests {
    static func main() throws {
        _ = NSApplication.shared
        let builtIn = MenuBarMaskDisplay(
            id: 1,
            quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            menuBarHeight: 25
        )
        let external = MenuBarMaskDisplay(
            id: 2,
            quartzFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            appKitFrame: CGRect(x: -1_920, y: -98, width: 1_920, height: 1_080),
            menuBarHeight: 25
        )
        var displays = [builtIn, external]
        var windows = [FakeMaskWindow]()
        let controller = MenuBarMaskingController(
            displayProvider: { displays },
            windowFactory: { placement in
                let window = FakeMaskWindow(frame: placement.frame)
                windows.append(window)
                return window
            }
        )
        let item = MenuBarItem(
            id: "utility",
            title: "Utility",
            ownerName: "Utility",
            bundleIdentifier: "com.example.utility",
            frame: CGRect(x: 1_200, y: 4.5, width: 28, height: 18),
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )

        let first = controller.apply(items: [item])
        try expect(first.maskedItemIDs == [item.id] && first.failedItemIDs.isEmpty,
                   "Both display masks must be visible before an item is reported as hidden.")
        try expect(first.changedWindowCount == 2 && windows.count == 2,
                   "The initial apply must create exactly one mask per display.")
        try expect(windows.allSatisfy { $0.isMaskVisible && $0.showCount == 1 },
                   "New mask windows must be shown exactly once.")

        let unchanged = controller.apply(items: [item])
        try expect(unchanged.changedWindowCount == 0 && windows.count == 2,
                   "An unchanged refresh must not create, move, or remove mask windows.")
        try expect(windows.allSatisfy { $0.setFrameCount == 0 && $0.showCount == 1 },
                   "No-op applies must not republish panel frames or visibility.")

        item.frame = item.frame.offsetBy(dx: -8, dy: 0)
        let moved = controller.apply(items: [item])
        try expect(moved.changedWindowCount == 2 && windows.allSatisfy { $0.setFrameCount == 1 },
                   "A changed status position must move existing masks without recreating them.")

        controller.setRevealed(true, itemID: item.id)
        try expect(windows.allSatisfy { !$0.isMaskVisible && $0.hideCount == 1 },
                   "Activation must temporarily reveal only the selected menu-bar item.")
        controller.setRevealed(false, itemID: item.id)
        try expect(windows.allSatisfy { $0.isMaskVisible && $0.showCount == 2 },
                   "The same masks must return after the native menu receives the click.")

        displays = [builtIn]
        let disconnected = controller.apply(items: [item])
        try expect(disconnected.changedWindowCount == 1 && windows.filter { $0.closeCount == 1 }.count == 1,
                   "A display disconnect must close only that display's mask.")

        let removedCount = controller.removeAll()
        try expect(removedCount == 1 && controller.maskedItemIDs.isEmpty,
                   "Disabling layout must synchronously remove every remaining mask.")

        let invalid = MenuBarItem(
            id: "invalid",
            title: "Invalid",
            ownerName: "Invalid",
            bundleIdentifier: nil,
            frame: CGRect(x: 100, y: 200, width: 28, height: 18),
            axElement: nil,
            isSelected: true,
            supportsPressAction: false
        )
        let failed = controller.apply(items: [invalid])
        try expect(failed.maskedItemIDs.isEmpty && failed.failedItemIDs == [invalid.id],
                   "An item without a trustworthy menu-bar frame must not report a false success.")

        var roundedWindows = [FakeMaskWindow]()
        let roundedController = MenuBarMaskingController(
            displayProvider: { [builtIn] },
            windowFactory: { placement in
                let roundedFrame = placement.frame.offsetBy(dx: 0.25, dy: -0.25)
                let window = FakeMaskWindow(frame: roundedFrame)
                roundedWindows.append(window)
                return window
            }
        )
        let rounded = roundedController.apply(items: [item])
        try expect(rounded.maskedItemIDs == [item.id] && rounded.failedItemIDs.isEmpty,
                   "AppKit sub-point frame rounding must not discard a visible mask.")
        try expect(roundedWindows.first?.closeCount == 0,
                   "A mask within the reconciliation tolerance must remain installed.")

        var liveFrame = CGRect(x: 1_200, y: 4.5, width: 28, height: 18)
        var liveWindows = [FakeMaskWindow]()
        let liveController = MenuBarMaskingController(
            displayProvider: { [builtIn] },
            representationFrameProvider: { _ in liveFrame },
            windowFactory: { placement in
                let window = FakeMaskWindow(frame: placement.frame)
                liveWindows.append(window)
                return window
            }
        )
        let staleItem = MenuBarItem(
            id: "live-utility",
            title: "Live Utility",
            ownerName: "Live Utility",
            bundleIdentifier: "com.example.live-utility",
            frame: liveFrame,
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )
        _ = liveController.apply(items: [staleItem])
        liveFrame = liveFrame.offsetBy(dx: 18, dy: 0)
        let corrected = liveController.apply(items: [staleItem])
        try expect(corrected.changedWindowCount == 1 && liveWindows.count == 1,
                   "A live menu-bar reflow must move the existing mask without recreating it.")
        try expect(liveWindows[0].maskFrame.minX == liveFrame.minX - 1,
                   "Mask placement must follow the live Accessibility frame instead of stale scan data.")

        let panelPlacement = MenuBarMaskPlacement(
            key: "capture|1",
            itemID: "capture",
            displayID: 1,
            frame: CGRect(x: 1_100, y: 957, width: 32, height: 25)
        )
        let panel = MenuBarMaskPanel(placement: panelPlacement)
        try expect(panel.sharingType == .readOnly,
                   "Mask windows must appear in screenshots so captured evidence matches the visible menu bar.")
        panel.closeMask()

        print("MenuBarMaskingControllerTests: window lifecycle passed")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw MaskControllerTestFailure(description: message) }
    }
}

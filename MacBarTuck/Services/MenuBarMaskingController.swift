import AppKit
import ApplicationServices
import CoreGraphics

struct MenuBarMaskApplicationResult: Equatable {
    let maskedItemIDs: Set<String>
    let failedItemIDs: Set<String>
    let changedWindowCount: Int
}

@MainActor
protocol MenuBarMaskWindow: AnyObject {
    var maskFrame: CGRect { get }
    var isMaskVisible: Bool { get }
    func setMaskFrame(_ frame: CGRect)
    func showMask()
    func hideMask()
    func closeMask()
}

@MainActor
final class MenuBarMaskingController {
    typealias DisplayProvider = @MainActor () -> [MenuBarMaskDisplay]
    typealias RepresentationFrameProvider = @MainActor (MenuBarItem) -> CGRect?
    typealias WindowFactory = @MainActor (MenuBarMaskPlacement) -> any MenuBarMaskWindow

    private let displayProvider: DisplayProvider
    private let representationFrameProvider: RepresentationFrameProvider
    private let windowFactory: WindowFactory
    private var windows = [String: any MenuBarMaskWindow]()
    private var placements = [String: MenuBarMaskPlacement]()
    private var revealedItemIDs = Set<String>()
    private(set) var maskedItemIDs = Set<String>()

    init(
        displayProvider: @escaping DisplayProvider = MenuBarMaskingController.currentDisplays,
        representationFrameProvider: @escaping RepresentationFrameProvider = MenuBarMaskingController.currentFrame,
        windowFactory: @escaping WindowFactory = { MenuBarMaskPanel(placement: $0) }
    ) {
        self.displayProvider = displayProvider
        self.representationFrameProvider = representationFrameProvider
        self.windowFactory = windowFactory
    }

    @discardableResult
    func apply(items: [MenuBarItem]) -> MenuBarMaskApplicationResult {
        let displays = displayProvider()
        let displayIDs = Set(displays.map(\.id))
        var seenItemIDs = Set<String>()
        var desiredPlacements = [MenuBarMaskPlacement]()
        var failedItemIDs = Set<String>()

        for item in items where seenItemIDs.insert(item.id).inserted {
            let itemPlacements = MenuBarMaskLayoutPolicy.placements(
                itemID: item.id,
                representationFrames: item.windowRepresentations.compactMap(
                    representationFrameProvider
                ),
                displays: displays
            )
            guard !displayIDs.isEmpty,
                  Set(itemPlacements.map(\.displayID)) == displayIDs else {
                failedItemIDs.insert(item.id)
                continue
            }
            desiredPlacements.append(contentsOf: itemPlacements)
        }

        let currentFrames = windows.mapValues(\.maskFrame)
        let reconciliation = MenuBarMaskLayoutPolicy.reconcile(
            current: currentFrames,
            desired: desiredPlacements
        )

        for key in reconciliation.removals {
            windows.removeValue(forKey: key)?.closeMask()
            placements.removeValue(forKey: key)
        }
        for placement in reconciliation.updates {
            windows[placement.key]?.setMaskFrame(placement.frame)
            placements[placement.key] = placement
        }
        for placement in reconciliation.additions {
            let window = windowFactory(placement)
            windows[placement.key] = window
            placements[placement.key] = placement
            if !revealedItemIDs.contains(placement.itemID) {
                window.showMask()
            }
        }

        let desiredByItem = Dictionary(grouping: desiredPlacements, by: \.itemID)
        var verifiedItemIDs = Set<String>()
        for (itemID, itemPlacements) in desiredByItem {
            let isRevealed = revealedItemIDs.contains(itemID)
            let isVerified = itemPlacements.allSatisfy { placement in
                guard let window = windows[placement.key] else { return false }
                return MenuBarMaskLayoutPolicy.framesMatch(window.maskFrame, placement.frame) &&
                    (isRevealed || window.isMaskVisible)
            }
            if isVerified {
                verifiedItemIDs.insert(itemID)
            } else {
                failedItemIDs.insert(itemID)
            }
        }

        if !failedItemIDs.isEmpty {
            let failedKeys = placements.values
                .filter { failedItemIDs.contains($0.itemID) }
                .map(\.key)
            for key in failedKeys {
                windows.removeValue(forKey: key)?.closeMask()
                placements.removeValue(forKey: key)
            }
            verifiedItemIDs.subtract(failedItemIDs)
        }

        revealedItemIDs.formIntersection(verifiedItemIDs)
        maskedItemIDs = verifiedItemIDs
        return MenuBarMaskApplicationResult(
            maskedItemIDs: verifiedItemIDs,
            failedItemIDs: failedItemIDs,
            changedWindowCount: reconciliation.removals.count +
                reconciliation.additions.count + reconciliation.updates.count
        )
    }

    func setRevealed(_ revealed: Bool, itemID: String) {
        if revealed {
            guard maskedItemIDs.contains(itemID), revealedItemIDs.insert(itemID).inserted else {
                return
            }
        } else {
            guard revealedItemIDs.remove(itemID) != nil else { return }
        }
        for placement in placements.values where placement.itemID == itemID {
            if revealed {
                windows[placement.key]?.hideMask()
            } else {
                windows[placement.key]?.showMask()
            }
        }
    }

    @discardableResult
    func removeAll() -> Int {
        let count = windows.count
        for window in windows.values { window.closeMask() }
        windows.removeAll()
        placements.removeAll()
        revealedItemIDs.removeAll()
        maskedItemIDs.removeAll()
        return count
    }

    private static func currentDisplays() -> [MenuBarMaskDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            let displayID = number.uint32Value
            let visibleInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let menuBarHeight = min(
                50,
                max(22, NSStatusBar.system.thickness, visibleInset, screen.safeAreaInsets.top)
            )
            return MenuBarMaskDisplay(
                id: displayID,
                quartzFrame: CGDisplayBounds(displayID),
                appKitFrame: screen.frame,
                menuBarHeight: menuBarHeight
            )
        }
    }

    private static func currentFrame(for item: MenuBarItem) -> CGRect? {
        guard let element = item.axElement else { return item.frame }
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &value
        ) == .success,
              let positionValue = value,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              AXValueGetType(positionValue as! AXValue) == .cgPoint else {
            return item.frame
        }
        var position = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)

        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &value
        ) == .success,
              let sizeValue = value,
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetType(sizeValue as! AXValue) == .cgSize else {
            return item.frame
        }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}

@MainActor
final class MenuBarMaskPanel: NSPanel, MenuBarMaskWindow {
    init(placement: MenuBarMaskPlacement) {
        super.init(
            contentRect: placement.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        title = "MacBarTuck Mask"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        sharingType = .readOnly
        contentView = MenuBarMaskView(frame: CGRect(origin: .zero, size: placement.frame.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var maskFrame: CGRect { frame }
    var isMaskVisible: Bool { isVisible }

    func setMaskFrame(_ frame: CGRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            setFrame(frame, display: true)
        }
    }

    func showMask() {
        guard !isVisible else { return }
        orderFrontRegardless()
        displayIfNeeded()
    }

    func hideMask() {
        guard isVisible else { return }
        orderOut(nil)
    }

    func closeMask() {
        orderOut(nil)
        close()
    }
}

private final class MenuBarMaskView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .menu
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        updateTint()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTint()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func isAccessibilityElement() -> Bool { false }

    private func updateTint() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor(
            calibratedWhite: isDark ? 0.08 : 0.94,
            alpha: 0.72
        ).cgColor
    }
}

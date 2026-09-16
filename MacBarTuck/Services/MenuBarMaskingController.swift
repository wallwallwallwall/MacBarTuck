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
    func setMaskArtwork(_ artwork: NSImage?)
    func setCaptureExcluded(_ excluded: Bool)
    func showMask()
    func hideMask()
    func closeMask()
}

extension MenuBarMaskWindow {
    func setMaskArtwork(_ artwork: NSImage?) {}
    func setCaptureExcluded(_ excluded: Bool) {}
}

@MainActor
final class MenuBarMaskingController {
    typealias DisplayProvider = @MainActor () -> [MenuBarMaskDisplay]
    typealias RepresentationFrameProvider = @MainActor (MenuBarItem) -> CGRect?
    typealias SnapshotProvider = @MainActor ([MenuBarMaskDisplay]) ->
        MenuBarMaskSnapshotRenderer.DisplaySnapshots
    typealias WindowFactory = @MainActor (MenuBarMaskPlacement) -> any MenuBarMaskWindow

    private let displayProvider: DisplayProvider
    private let representationFrameProvider: RepresentationFrameProvider
    private let snapshotProvider: SnapshotProvider
    private let windowFactory: WindowFactory
    private var windows = [String: any MenuBarMaskWindow]()
    private var placements = [String: MenuBarMaskPlacement]()
    private var revealedItemIDs = Set<String>()
    private(set) var maskedItemIDs = Set<String>()

    init(
        displayProvider: @escaping DisplayProvider = MenuBarMaskingController.currentDisplays,
        representationFrameProvider: @escaping RepresentationFrameProvider = MenuBarMaskingController.currentFrame,
        snapshotProvider: @escaping SnapshotProvider = MenuBarMaskSnapshotRenderer.captureMenuBars,
        windowFactory: @escaping WindowFactory = { MenuBarMaskPanel(placement: $0) }
    ) {
        self.displayProvider = displayProvider
        self.representationFrameProvider = representationFrameProvider
        self.snapshotProvider = snapshotProvider
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
        let changedPlacements = reconciliation.additions + reconciliation.updates
        let artwork = artworkByPlacement(
            changedPlacements,
            displays: displays
        )

        for key in reconciliation.removals {
            windows.removeValue(forKey: key)?.closeMask()
            placements.removeValue(forKey: key)
        }
        for placement in reconciliation.updates {
            if let image = artwork[placement.key] {
                windows[placement.key]?.setMaskArtwork(image)
            }
            windows[placement.key]?.setMaskFrame(placement.frame)
            placements[placement.key] = placement
        }
        for placement in reconciliation.additions {
            let window = windowFactory(placement)
            if let image = artwork[placement.key] {
                window.setMaskArtwork(image)
            }
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
            refreshAppearance(itemIDs: [itemID])
        }
        for placement in placements.values where placement.itemID == itemID {
            if revealed {
                windows[placement.key]?.hideMask()
            } else {
                windows[placement.key]?.showMask()
            }
        }
    }

    func refreshAppearance() {
        refreshAppearance(itemIDs: maskedItemIDs)
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

    private func refreshAppearance(itemIDs: Set<String>) {
        guard !itemIDs.isEmpty else { return }
        let targetPlacements = placements.values.filter { itemIDs.contains($0.itemID) }
        let displays = displayProvider()
        let artwork = artworkByPlacement(targetPlacements, displays: displays)
        for placement in targetPlacements {
            if let image = artwork[placement.key] {
                windows[placement.key]?.setMaskArtwork(image)
            }
        }
    }

    private func artworkByPlacement(
        _ targetPlacements: [MenuBarMaskPlacement],
        displays: [MenuBarMaskDisplay]
    ) -> [String: NSImage] {
        guard !targetPlacements.isEmpty else { return [:] }
        let targetDisplayIDs = Set(targetPlacements.map(\.displayID))
        let targetDisplays = displays.filter { targetDisplayIDs.contains($0.id) }
        let displaysByID = Dictionary(uniqueKeysWithValues: targetDisplays.map { ($0.id, $0) })
        let capturedWindows = placements.values.compactMap { placement -> (any MenuBarMaskWindow)? in
            guard targetDisplayIDs.contains(placement.displayID) else { return nil }
            return windows[placement.key]
        }
        capturedWindows.forEach { $0.setCaptureExcluded(true) }
        defer { capturedWindows.forEach { $0.setCaptureExcluded(false) } }
        let snapshots = snapshotProvider(targetDisplays)
        return Dictionary(uniqueKeysWithValues: targetPlacements.compactMap { placement in
            let image = displaysByID[placement.displayID].flatMap { display in
                snapshots[placement.displayID].flatMap { snapshot in
                    MenuBarMaskSnapshotRenderer.artwork(
                        for: placement,
                        display: display,
                        snapshot: snapshot
                    )
                }
            }
            return image.map { (placement.key, $0) }
        })
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
    init(placement: MenuBarMaskPlacement, artwork: NSImage? = nil) {
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
        contentView = MenuBarMaskView(
            frame: CGRect(origin: .zero, size: placement.frame.size),
            artwork: artwork
        )
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

    func setMaskArtwork(_ artwork: NSImage?) {
        (contentView as? MenuBarMaskView)?.setArtwork(artwork)
    }

    func setCaptureExcluded(_ excluded: Bool) {
        sharingType = excluded ? .none : .readOnly
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

private final class MenuBarMaskView: NSView {
    private let imageView: NSImageView

    init(frame frameRect: NSRect, artwork: NSImage?) {
        imageView = NSImageView(frame: CGRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]

        let fallback = Self.makeFallbackView(frame: bounds)
        fallback.autoresizingMask = [.width, .height]
        addSubview(fallback)

        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        setArtwork(artwork)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func isAccessibilityElement() -> Bool { false }

    func setArtwork(_ artwork: NSImage?) {
        imageView.image = artwork
        imageView.isHidden = artwork == nil
    }

    private static func makeFallbackView(frame: CGRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = 0
            glass.tintColor = .clear
            glass.style = .clear
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = false
            }
            return glass
        }
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .titlebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        return effect
    }
}

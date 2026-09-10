import AppKit
import OSLog

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let hiddenSectionItem: NSStatusItem
    private let store: MenuBarItemStore
    private let panelController: OverflowPanelController
    private let menuProvider: () -> NSMenu
    private var isShowingContextMenu = false
    private let logger = Logger(subsystem: "com.bartuck.app", category: "status")
    private var hoverMonitor: Any?
    private var pointerIsAtMenuBar = false
    private var hoverRevealSuppressedUntilPointerLeaves = false
    private var hiddenSectionReflowWorkItem: DispatchWorkItem?
    private var requestedHiddenSectionLength: CGFloat?
    private var isApplyingLayout = false
    private var isTerminating = false

    init(store: MenuBarItemStore, menuProvider: @escaping () -> NSMenu) {
        let defaults = UserDefaults.standard
        let arrowName = "BarTuckControlItem"
        let hiddenName = "BarTuckHiddenSection"
        // Keep the registration sequence used by the working 1.0.17 build.
        // macOS 26 creates the Control Center host during statusItem(withLength:);
        // registering a second item before the first host is attached makes
        // the whole client enter Control Center's blocked list.
        defaults.set(0.0, forKey: "NSStatusItem Preferred Position \(arrowName)")
        defaults.set(1.0, forKey: "NSStatusItem Preferred Position \(hiddenName)")
        defaults.set(true, forKey: "NSStatusItem Visible \(arrowName)")
        defaults.set(true, forKey: "NSStatusItem Visible \(hiddenName)")
        let visibleLength = max(NSStatusBar.system.thickness, 18)
        let hiddenLength: CGFloat = {
            if #available(macOS 27.0, *) { return 0 }
            return 20
        }()
        statusItem = NSStatusBar.system.statusItem(withLength: visibleLength)
        statusItem.autosaveName = arrowName
        hiddenSectionItem = NSStatusBar.system.statusItem(withLength: hiddenLength)
        hiddenSectionItem.autosaveName = hiddenName
        self.store = store
        self.menuProvider = menuProvider
        panelController = OverflowPanelController(store: store)
        super.init()
        configureHiddenSectionItem()
        store.onImagesReady = { [weak self] in
            guard let self else { return }
            self.updateHiddenSectionLength()
            // Do not synthesize Command-drag events during startup. Those
            // events alter WindowServer's global pointer state even when the
            // user has not interacted with BarTuck. Layout is applied by
            // an explicit user action (or when onboarding is completed).
        }
        store.onLayoutStateChanged = { [weak self] in self?.updateHiddenSectionLength() }
        store.onLayoutOperationStateChanged = { [weak self] applying in
            self?.isApplyingLayout = applying
            self?.updateHiddenSectionLength()
        }
        let button = statusItem.button
        statusItem.length = visibleLength
        statusItem.isVisible = true
        if #unavailable(macOS 27.0) {
            hiddenSectionItem.isVisible = true
        }
        button?.image = Self.statusBarImage(isExpanded: false)
        button?.imagePosition = .imageOnly
        button?.toolTip = "打开 BarTuck 托盘；右键显示菜单"
        button?.setAccessibilityLabel("BarTuck 菜单栏托盘")
        button?.target = self
        button?.action = #selector(togglePanel)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateHiddenSectionLength()
        panelController.onVisibilityChanged = { [weak self] isVisible in
            self?.statusItem.button?.image = Self.statusBarImage(isExpanded: isVisible)
        }
        panelController.onItemActivation = { [weak self] in
            // The activation path posts a real session click at a temporary
            // menu-bar position. Some macOS versions emit a synthetic
            // mouseMoved for that event; keep the hover revealer dormant
            // until the pointer has actually left the menu bar, otherwise
            // the panel can reopen on top of the menu just opened.
            self?.hoverRevealSuppressedUntilPointerLeaves = true
            self?.pointerIsAtMenuBar = true
        }
        // Observe mouse movement without consuming or synthesizing events.
        // This removes the old 250ms polling interval plus 120ms debounce, so
        // the panel starts its animation on the first movement into the menu
        // bar while remaining passive for all other applications.
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.handleHoverPointer() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.statusHostsReady = true
            self.updateHiddenSectionLength()
            self.publishStatusItemWindowIDs()
            self.storeControlItemFrame(for: button)
            if ProcessInfo.processInfo.arguments.contains("--show-panel") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.panelController.show(relativeTo: button)
                }
            }
        }
        // Control Center publishes the hosted window title/ID asynchronously;
        // retry the read while the scene settles so layout never captures a
        // transient zero ID.
        for delay in [2.0, 4.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.statusHostsReady = true
                self.updateHiddenSectionLength()
                self.publishStatusItemWindowIDs()
            }
        }
    }

    private var statusHostsReady = false
    private func configureHiddenSectionItem() {
        hiddenSectionItem.button?.image = nil
        // Control Center rejects Command-drag drops into a disabled hosted
        // status item, even though the WindowServer target still exists.
        hiddenSectionItem.button?.cell?.isEnabled = true
    }

    deinit {
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
    }

    private func handleHoverPointer() {
        guard !isShowingContextMenu else { return }
        guard hoverRevealEnabled,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
            pointerIsAtMenuBar = false
            return
        }
        let atMenuBar = NSEvent.mouseLocation.y >= screen.frame.maxY - NSStatusBar.system.thickness - 2
        if !atMenuBar {
            pointerIsAtMenuBar = false
            hoverRevealSuppressedUntilPointerLeaves = false
            return
        }
        guard !hoverRevealSuppressedUntilPointerLeaves else { return }
        guard atMenuBar != pointerIsAtMenuBar else { return }
        pointerIsAtMenuBar = atMenuBar
        guard atMenuBar, let button = statusItem.button else { return }
        storeControlItemFrame(for: button)
        panelController.show(relativeTo: button)
    }

    func prepareForTermination() {
        isTerminating = true
        hiddenSectionReflowWorkItem?.cancel()
        hiddenSectionReflowWorkItem = nil
        requestedHiddenSectionLength = 0
        hiddenSectionItem.isVisible = false
        hiddenSectionItem.length = 0
    }

    @objc private func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            panelController.close()
            hoverRevealSuppressedUntilPointerLeaves = true
            isShowingContextMenu = true
            defer { isShowingContextMenu = false }
            menuProvider().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        guard let button = statusItem.button else { return }
        storeControlItemFrame(for: button)
        panelController.toggle(relativeTo: button)
    }

    func showPanel() {
        guard let button = statusItem.button else { return }
        storeControlItemFrame(for: button)
        panelController.show(relativeTo: button)
    }

    private func storeControlItemFrame(for button: NSStatusBarButton) {
        publishStatusItemWindowIDs()
        if let frame = button.barTuckScreenFrame { store.updateControlItemFrame(frame) }
    }

    private func publishStatusItemWindowIDs() {
        let controlWindowID = statusWindowID(for: statusItem)
        let hiddenWindowID = statusWindowID(for: hiddenSectionItem)
        logger.info("Published status item windows control=\(controlWindowID ?? 0, privacy: .public) hidden=\(hiddenWindowID ?? 0, privacy: .public)")
        if let button = statusItem.button {
            let appKitFrame = button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } ?? .zero
            let axFrame = button.accessibilityFrame()
            logger.info("Status item diagnostics visible=\(self.statusItem.isVisible, privacy: .public) length=\(self.statusItem.length, privacy: .public) hidden=\(button.isHidden, privacy: .public) alpha=\(button.alphaValue, privacy: .public) buttonFrame=\(String(describing: button.frame), privacy: .public) window=\(button.window?.windowNumber ?? 0, privacy: .public) windowFrame=\(String(describing: button.window?.frame ?? .zero), privacy: .public) windowVisible=\(button.window?.isVisible ?? false, privacy: .public) appKitFrame=\(String(describing: appKitFrame), privacy: .public) axFrame=\(String(describing: axFrame), privacy: .public) image=\(button.image != nil, privacy: .public)")
        }
        store.updateStatusItemWindowIDs(control: controlWindowID, hidden: hiddenWindowID)
    }

    private func statusWindowID(for item: NSStatusItem) -> CGWindowID? {
        let hidden = item === hiddenSectionItem
        let exactTitle = hidden ? "BarTuckHiddenSection" : "BarTuckControlItem"
        let windows = MenuBarWindowServer.windowInfo()
        if let exact = windows.compactMap({ info -> (id: CGWindowID, width: CGFloat)? in
            guard MenuBarWindowServer.isStatusItemLayer(info),
                  let ownerPID = MenuBarWindowServer.integer(kCGWindowOwnerPID as String, in: info),
                  ownerPID == Int(getpid()) || NSRunningApplication(processIdentifier: pid_t(ownerPID))?.bundleIdentifier == "com.apple.controlcenter",
                  (info[kCGWindowName as String] as? String) == exactTitle,
                  let rawID = MenuBarWindowServer.integer(kCGWindowNumber as String, in: info),
                  rawID > 0,
                  rawID <= Int(CGWindowID.max),
                  let bounds = MenuBarWindowServer.bounds(in: info) else { return nil }
            return (CGWindowID(rawID), bounds.width)
        }).max(by: { $0.id < $1.id }) {
            return exact.id
        }
        // Generic Item-0/Item-1 windows can belong to unrelated apps.
        // Wait for our exact title instead of guessing by age or width.
        return nil
    }

    private func updateHiddenSectionLength() {
        guard !isTerminating else { return }
        if #available(macOS 27.0, *) {
            // macOS 27 owns the overflow slot and renders the menu bar as a
            // composite host. Keeping a staging item would compete with it.
            hiddenSectionItem.length = 0
            hiddenSectionItem.isVisible = false
            requestedHiddenSectionLength = 0
            return
        }
        let desiredLength = StatusItemLayoutPolicy.separatorLength(
            enabled: store.layoutManagementEnabled,
            ready: store.isHiddenSectionActive,
            hasSelection: store.isHiddenSectionActive,
            isApplying: isApplyingLayout,
            screenWidths: NSScreen.screens.map { $0.frame.width }
        )
        guard statusHostsReady else { return }
        let item = hiddenSectionItem
        guard requestedHiddenSectionLength != desiredLength else { return }
        DiagnosticLog.shared.record("separator.resize", ["width": Int(desiredLength), "arranging": isApplyingLayout ? 1 : 0])
        requestedHiddenSectionLength = desiredLength
        hiddenSectionReflowWorkItem?.cancel()

        if desiredLength == 0 {
            item.isVisible = false
            item.length = 0
            publishStatusItemWindowIDs()
            return
        }

        // Keep the separator identity while arranging, then expand it only
        // after the move. Dropping before an expanded host is offscreen.
        item.length = desiredLength
        item.isVisible = true
        let work = DispatchWorkItem { [weak self] in
            self?.hiddenSectionReflowWorkItem = nil
            self?.publishStatusItemWindowIDs()
        }
        hiddenSectionReflowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private var hoverRevealEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "hoverRevealEnabled") == nil || defaults.bool(forKey: "hoverRevealEnabled")
    }

    private static func statusBarImage(isExpanded: Bool) -> NSImage? {
        let names = isExpanded
            ? ["rectangle.stack.fill", "rectangle.3.group.fill", "chevron.up"]
            : ["rectangle.stack", "rectangle.3.group", "chevron.down"]
        guard let image = names.lazy.compactMap({
            NSImage(
                systemSymbolName: $0,
                accessibilityDescription: isExpanded ? "收起 BarTuck" : "展开 BarTuck"
            )
        }).first else { return nil }
        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        ) ?? image
        configured.isTemplate = true
        return configured
    }
}

extension NSStatusBarButton {
    var barTuckScreenFrame: CGRect? {
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let matchedWindow = windows.first(where: {
            guard MenuBarWindowServer.isStatusItemLayer($0) else { return false }
            if let windowNumber = window?.windowNumber, windowNumber > 0,
               MenuBarWindowServer.integer(kCGWindowNumber as String, in: $0) == windowNumber {
                return true
            }
            return ($0[kCGWindowName as String] as? String) == "BarTuckControlItem"
        })
        var frames: [CGRect] = []
        if let matchedWindow, let quartzFrame = MenuBarWindowServer.bounds(in: matchedWindow),
           let primary = NSScreen.screens.first {
            frames.append(MenuBarGeometry.appKitFrame(fromQuartz: quartzFrame, primaryScreenHeight: primary.frame.maxY))
        }
        if let window {
            frames.append(window.convertToScreen(convert(bounds, to: nil)))
        }
        frames.append(accessibilityFrame())
        return MenuBarGeometry.panelAnchor(
            buttonFrames: frames, pointer: NSEvent.mouseLocation,
            displayFrames: NSScreen.screens.map(\.frame), menuBarHeight: NSStatusBar.system.thickness
        )
    }
}

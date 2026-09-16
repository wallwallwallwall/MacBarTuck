import AppKit
import OSLog

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private var hiddenSectionItems: [NSStatusItem]
    private let store: MenuBarItemStore
    private let panelController: OverflowPanelController
    private let menuProvider: () -> NSMenu
    private let language: AppLanguageController
    private let platformPolicy: MenuBarPlatformPolicy
    private var isShowingContextMenu = false
    private let logger = Logger(subsystem: "com.bartuck.app", category: "status")
    private var hoverMonitor: Any?
    private var pointerIsAtMenuBar = false
    private var hoverRevealSuppressedUntilPointerLeaves = false
    private var hiddenSectionReflowWorkItem: DispatchWorkItem?
    private var requestedHiddenSectionLengths: [CGFloat]?
    private var isApplyingLayout = false
    private var isTerminating = false

    init(store: MenuBarItemStore, language: AppLanguageController = .shared,
         menuProvider: @escaping () -> NSMenu) {
        let platformPolicy = MenuBarPlatformPolicy.current
        let defaults = UserDefaults.standard
        let hoverMigrationKey = "didDisableHoverRevealByDefaultV1"
        if defaults.object(forKey: hoverMigrationKey) == nil {
            defaults.set(false, forKey: "hoverRevealEnabled")
            defaults.set(true, forKey: hoverMigrationKey)
        }
        // Keep the legacy autosave names so upgrades retain menu bar positions.
        let arrowName = "BarTuckControlItem"
        // Keep the registration sequence used by the working 1.0.17 build.
        // macOS 26 creates the Control Center host during statusItem(withLength:);
        // registering a second item before the first host is attached makes
        // the whole client enter Control Center's blocked list.
        defaults.set(0.0, forKey: "NSStatusItem Preferred Position \(arrowName)")
        defaults.set(true, forKey: "NSStatusItem Visible \(arrowName)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(arrowName)")
        let visibleLength = max(NSStatusBar.system.thickness, 18)
        let hiddenCount = Self.hiddenSectionItemCount(for: platformPolicy)
        let hiddenLength: CGFloat = platformPolicy.usesHiddenSection
            ? StatusItemLayoutPolicy.compactSeparatorLength
            : 0
        statusItem = NSStatusBar.system.statusItem(withLength: visibleLength)
        statusItem.autosaveName = arrowName
        hiddenSectionItems = (0..<hiddenCount).map {
            Self.makeHiddenSectionItem(
                index: $0,
                length: hiddenLength,
                defaults: defaults
            )
        }
        self.store = store
        self.language = language
        self.menuProvider = menuProvider
        self.platformPolicy = platformPolicy
        panelController = OverflowPanelController(store: store, language: language)
        super.init()
        hiddenSectionItems.forEach(configureHiddenSectionItem)
        publishStatusItemFrameProviders()
        store.onImagesReady = { [weak self] in
            guard let self else { return }
            self.updateHiddenSectionLength()
            // Do not synthesize Command-drag events during startup. Those
            // events alter WindowServer's global pointer state even when the
            // user has not interacted with MacBarTuck. Layout is applied by
            // an explicit user action (or when onboarding is completed).
        }
        store.onLayoutStateChanged = { [weak self] in self?.updateHiddenSectionLength() }
        store.onLayoutOperationStateChanged = { [weak self] applying in
            guard let self else { return }
            self.isApplyingLayout = applying
            if applying {
                self.panelController.close()
                self.hoverRevealSuppressedUntilPointerLeaves = true
            }
            self.updateHiddenSectionLength()
        }
        let button = statusItem.button
        statusItem.length = visibleLength
        statusItem.isVisible = true
        if platformPolicy.usesHiddenSection {
            hiddenSectionItems.forEach { $0.isVisible = true }
        } else {
            hiddenSectionItems.forEach(withdrawHiddenSectionItem)
        }
        button?.image = Self.statusBarImage(language: language)
        button?.imagePosition = .imageOnly
        updateLocalization()
        button?.target = self
        button?.action = #selector(togglePanel)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateHiddenSectionLength()
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
    private func configureHiddenSectionItem(_ item: NSStatusItem) {
        item.button?.image = nil
        item.button?.title = ""
        applyHiddenSectionPresentation(
            to: item,
            length: item.length,
            isApplyingLayout: false
        )
    }

    deinit {
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
    }

    private func handleHoverPointer() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
            pointerIsAtMenuBar = false
            return
        }
        let atMenuBar = NSEvent.mouseLocation.y >= screen.frame.maxY - NSStatusBar.system.thickness - 2
        if !atMenuBar {
            pointerIsAtMenuBar = false
            hoverRevealSuppressedUntilPointerLeaves = false
            return
        }
        guard MenuBarInteractionPolicy.allowsHoverReveal(
            enabled: hoverRevealEnabled,
            isApplyingLayout: store.isInteractionBusy,
            isShowingContextMenu: isShowingContextMenu,
            isSuppressed: hoverRevealSuppressedUntilPointerLeaves
        ) else { return }
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
        let terminalLength = platformPolicy.usesHiddenSection
            ? StatusItemLayoutPolicy.compactSeparatorLength
            : 0
        requestedHiddenSectionLengths = hiddenSectionItems.map { _ in terminalLength }
        for item in hiddenSectionItems {
            applyHiddenSectionPresentation(
                to: item,
                length: terminalLength,
                isApplyingLayout: false
            )
            item.length = terminalLength
            item.isVisible = terminalLength > 0
        }
        publishStatusItemWindowIDs()
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
        guard !store.isInteractionBusy else { return }
        guard let button = statusItem.button else { return }
        storeControlItemFrame(for: button)
        panelController.toggle(relativeTo: button)
    }

    func showPanel() {
        guard !store.isInteractionBusy, let button = statusItem.button else { return }
        storeControlItemFrame(for: button)
        panelController.show(relativeTo: button)
    }

    func updateLocalization() {
        statusItem.button?.toolTip = language.text("status.tooltip")
        statusItem.button?.setAccessibilityLabel(language.text("status.accessibility"))
        statusItem.button?.image = Self.statusBarImage(language: language)
        panelController.updateLocalization()
    }

    private func storeControlItemFrame(for button: NSStatusBarButton) {
        publishStatusItemWindowIDs()
        if let frame = button.macBarTuckScreenFrame { store.updateControlItemFrame(frame) }
    }

    private func publishStatusItemWindowIDs() {
        let controlWindowID = statusWindowID(for: statusItem)
        let hiddenWindowIDs = hiddenSectionItems.compactMap(statusWindowID)
        logger.info("Published status item windows control=\(controlWindowID ?? 0, privacy: .public) hiddenCount=\(hiddenWindowIDs.count, privacy: .public)")
        if let button = statusItem.button {
            let appKitFrame = button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } ?? .zero
            let axFrame = button.accessibilityFrame()
            logger.info("Status item diagnostics visible=\(self.statusItem.isVisible, privacy: .public) length=\(self.statusItem.length, privacy: .public) hidden=\(button.isHidden, privacy: .public) alpha=\(button.alphaValue, privacy: .public) buttonFrame=\(String(describing: button.frame), privacy: .public) window=\(button.window?.windowNumber ?? 0, privacy: .public) windowFrame=\(String(describing: button.window?.frame ?? .zero), privacy: .public) windowVisible=\(button.window?.isVisible ?? false, privacy: .public) appKitFrame=\(String(describing: appKitFrame), privacy: .public) axFrame=\(String(describing: axFrame), privacy: .public) image=\(button.image != nil, privacy: .public)")
        }
        store.updateStatusItemWindowIDs(control: controlWindowID, hidden: hiddenWindowIDs)
        publishStatusItemFrameProviders()
    }

    private func statusWindowID(for item: NSStatusItem) -> CGWindowID? {
        let exactTitle = item.autosaveName ?? ""
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
        reconcileHiddenSectionItemCount()
        if !platformPolicy.usesHiddenSection {
            for item in hiddenSectionItems {
                item.length = 0
                withdrawHiddenSectionItem(item)
            }
            requestedHiddenSectionLengths = hiddenSectionItems.map { _ in 0 }
            return
        }
        let desiredLengths = desiredHiddenSectionLengths()
        guard statusHostsReady else { return }
        guard requestedHiddenSectionLengths != desiredLengths else { return }
        DiagnosticLog.shared.record("separator.resize", [
            "width": Int(desiredLengths.reduce(0, +)),
            "count": desiredLengths.filter { $0 > 0 }.count,
            "arranging": isApplyingLayout ? 1 : 0,
            "interactive": isApplyingLayout ? desiredLengths.filter { $0 > 0 }.count : 0
        ])
        requestedHiddenSectionLengths = desiredLengths
        hiddenSectionReflowWorkItem?.cancel()

        for (item, desiredLength) in zip(hiddenSectionItems, desiredLengths) {
            applyHiddenSectionPresentation(
                to: item,
                length: desiredLength,
                isApplyingLayout: isApplyingLayout
            )
            if desiredLength == 0 {
                item.length = 0
                withdrawHiddenSectionItem(item)
                continue
            }
            item.length = desiredLength
            item.isVisible = true
        }
        let work = DispatchWorkItem { [weak self] in
            self?.hiddenSectionReflowWorkItem = nil
            self?.publishStatusItemWindowIDs()
        }
        hiddenSectionReflowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func desiredHiddenSectionLengths() -> [CGFloat] {
        if platformPolicy.movement == .nativeOverflow {
            let plan = Self.nativeOverflowSpacerPlan()
            let length: CGFloat
            if isApplyingLayout {
                length = StatusItemLayoutPolicy.compactSeparatorLength
            } else if store.layoutManagementEnabled && store.isHiddenSectionActive {
                length = plan.itemLength
            } else {
                length = 0
            }
            return Array(repeating: length, count: hiddenSectionItems.count)
        }
        let length = StatusItemLayoutPolicy.separatorLength(
            enabled: store.layoutManagementEnabled,
            ready: store.isHiddenSectionActive,
            hasSelection: store.isHiddenSectionActive,
            isApplying: isApplyingLayout,
            screenWidths: NSScreen.screens.map { $0.frame.width }
        )
        return [length]
    }

    private func reconcileHiddenSectionItemCount() {
        guard platformPolicy.movement == .nativeOverflow else { return }
        let desiredCount = Self.nativeOverflowSpacerPlan().itemCount
        guard desiredCount != hiddenSectionItems.count else { return }
        if desiredCount < hiddenSectionItems.count {
            for item in hiddenSectionItems.dropFirst(desiredCount) {
                NSStatusBar.system.removeStatusItem(item)
            }
            hiddenSectionItems.removeLast(hiddenSectionItems.count - desiredCount)
        } else {
            let defaults = UserDefaults.standard
            for index in hiddenSectionItems.count..<desiredCount {
                let item = Self.makeHiddenSectionItem(
                    index: index,
                    length: StatusItemLayoutPolicy.compactSeparatorLength,
                    defaults: defaults
                )
                configureHiddenSectionItem(item)
                hiddenSectionItems.append(item)
            }
        }
        requestedHiddenSectionLengths = nil
        publishStatusItemFrameProviders()
    }

    private func publishStatusItemFrameProviders() {
        let hiddenProviders: [() -> CGRect?] = hiddenSectionItems.indices.map { index in
            { [weak self] in
                guard let self, self.hiddenSectionItems.indices.contains(index) else { return nil }
                return self.quartzFrame(for: self.hiddenSectionItems[index])
            }
        }
        store.updateStatusItemFrameProviders(
            control: { [weak self] in
                guard let self else { return nil }
                return self.quartzFrame(for: self.statusItem)
            },
            hidden: hiddenProviders
        )
    }

    private func quartzFrame(for item: NSStatusItem) -> CGRect? {
        guard item.isVisible,
              item.length > 0,
              let button = item.button,
              let primaryHeight = NSScreen.screens.first?.frame.maxY else { return nil }
        let frame = button.accessibilityFrame()
        guard frame.width > 1, frame.height > 1 else { return nil }
        return MenuBarGeometry.quartzFrame(
            fromAppKit: frame,
            primaryScreenHeight: primaryHeight
        )
    }

    private func withdrawHiddenSectionItem(_ item: NSStatusItem) {
        let key = "NSStatusItem Preferred Position \(item.autosaveName ?? "")"
        let position = UserDefaults.standard.object(forKey: key)
        item.isVisible = false
        if let position { UserDefaults.standard.set(position, forKey: key) }
        item.button?.isEnabled = false
        item.button?.cell?.isEnabled = false
    }

    private func applyHiddenSectionPresentation(
        to item: NSStatusItem,
        length: CGFloat,
        isApplyingLayout: Bool
    ) {
        guard platformPolicy.movement == .nativeOverflow else {
            let enabled = length > 0
            item.button?.alphaValue = 1
            item.button?.isEnabled = enabled
            item.button?.cell?.isEnabled = enabled
            item.button?.appearsDisabled = false
            return
        }
        let presentation = StatusItemLayoutPolicy.nativeOverflowSpacerPresentation(
            isApplyingLayout: isApplyingLayout,
            length: length
        )
        item.button?.alphaValue = presentation.alphaValue
        item.button?.isEnabled = presentation.isEnabled
        item.button?.cell?.isEnabled = presentation.isEnabled
        item.button?.appearsDisabled = presentation.appearsDisabled
    }

    private static func hiddenSectionItemCount(
        for policy: MenuBarPlatformPolicy
    ) -> Int {
        guard policy.usesHiddenSection else {
            return StatusItemLayoutPolicy.hiddenSectionItemCount(usesHiddenSection: false)
        }
        return policy.movement == .nativeOverflow
            ? nativeOverflowSpacerPlan().itemCount
            : StatusItemLayoutPolicy.hiddenSectionItemCount(usesHiddenSection: true)
    }

    private static func nativeOverflowSpacerPlan() -> NativeOverflowSpacerPlan {
        StatusItemLayoutPolicy.nativeOverflowSpacerPlan(
            screenWidths: NSScreen.screens.map { $0.frame.width },
            statusRegionWidths: NSScreen.screens.map {
                StatusItemLayoutPolicy.statusRegionWidth(
                    screenWidth: $0.frame.width,
                    auxiliaryTopRightWidth: $0.auxiliaryTopRightArea?.width
                )
            }
        )
    }

    private static func hiddenSectionName(index: Int) -> String {
        index == 0 ? "BarTuckHiddenSection" : "BarTuckHiddenSection\(index + 1)"
    }

    private static func makeHiddenSectionItem(
        index: Int,
        length: CGFloat,
        defaults: UserDefaults
    ) -> NSStatusItem {
        let name = hiddenSectionName(index: index)
        defaults.set(Double(index + 1), forKey: "NSStatusItem Preferred Position \(name)")
        defaults.set(true, forKey: "NSStatusItem Visible \(name)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(name)")
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.autosaveName = name
        return item
    }

    private var hoverRevealEnabled: Bool {
        UserDefaults.standard.bool(forKey: "hoverRevealEnabled")
    }

    private static func statusBarImage(language: AppLanguageController) -> NSImage? {
        let names = ["rectangle.stack", "rectangle.3.group", "chevron.down"]
        guard let image = names.lazy.compactMap({
            NSImage(
                systemSymbolName: $0,
                accessibilityDescription: language.text("status.expand")
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
    var macBarTuckScreenFrame: CGRect? {
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

import AppKit
import ApplicationServices
import Combine
import OSLog

@MainActor
final class MenuBarItemStore: ObservableObject {
    @Published private(set) var items: [MenuBarItem] = []
    @Published var lastActivationError: String?
    @Published private(set) var activatingItemID: String?
    @Published private(set) var layoutManagementEnabled = false
    @Published private(set) var layoutOperationMessage: String?
    @Published private(set) var iconCaptureMessage: String?
    @Published private(set) var isReadyForManagedLayout = false
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var automaticAvoidanceEnabled = true
    @Published private(set) var requiresScreenRecording = false
    let isUIPreviewMode: Bool

    private let logger = Logger(subsystem: "com.bartuck.app", category: "items")
    private let preferences = PreferencesStore()
    private let scanner = MenuBarScanner()
    private let captureService = MenuBarCaptureService()
    private let activator = MenuBarItemActivator()
    private let layoutManager: MenuBarLayoutManager
    private var ownedStatusWindowIDs: Set<CGWindowID> = []
    private var controlItemFrame: CGRect?
    private var rehideWorkItem: DispatchWorkItem?
    private var menuTrackingBeginObserver: NSObjectProtocol?
    private var menuTrackingEndObserver: NSObjectProtocol?
    private var menuDismissMonitor: Any?
    private var transientDismissCheck: DispatchWorkItem?
    private var pendingRehideItem: MenuBarItem?
    // NSMenu can nest tracking sessions (for example, a submenu opened from
    // a status-item menu). Keep a depth instead of a Boolean so an inner
    // didEndTracking notification cannot make us rehide while the parent
    // menu is still interactive.
    private var menuTrackingDepth = 0
    private var layoutWorkItem: DispatchWorkItem?
    private var layoutStartWorkItem: DispatchWorkItem?
    private var layoutStartGeneration = 0
    private var automaticLayoutWorkItem: DispatchWorkItem?
    private var refreshWorkItem: DispatchWorkItem?
    private var captureTask: Task<Void, Never>?
    private var monitorTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastWindowSignature = Set<String>()
    private var captureGeneration = 0
    private var isRefreshing = false
    private var isCapturing = false
    private var refreshAgain = false
    private var isApplyingLayout = false
    private var shouldApplyLayoutAgain = false
    private var layoutRepairAttempts = 0
    var onImagesReady: (() -> Void)?
    var onLayoutStateChanged: (() -> Void)?
    var onLayoutOperationStateChanged: ((Bool) -> Void)?

    init() {
        isUIPreviewMode = ProcessInfo.processInfo.arguments.contains("--ui-preview")
        layoutManager = MenuBarLayoutManager(preferences: preferences)
        layoutManagementEnabled = layoutManager.isEnabled
        automaticAvoidanceEnabled = preferences.automaticAvoidanceEnabled
        displays = DisplaySnapshotProvider.snapshots()
        menuTrackingBeginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.menuTrackingDepth += 1 }
        }
        menuTrackingEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                guard self.menuTrackingDepth == 0 else { return }
                if let item = self.pendingRehideItem,
                   self.hasVisibleTransientWindow(for: item) {
                    self.scheduleTransientDismissCheck(for: item)
                } else {
                    self.rehidePendingItem()
                }
            }
        }
    }

    deinit {
        monitorTimer?.invalidate()
        refreshWorkItem?.cancel()
        layoutWorkItem?.cancel()
        layoutStartWorkItem?.cancel()
        automaticLayoutWorkItem?.cancel()
        captureTask?.cancel()
        transientDismissCheck?.cancel()
        if let menuTrackingBeginObserver { NotificationCenter.default.removeObserver(menuTrackingBeginObserver) }
        if let menuTrackingEndObserver { NotificationCenter.default.removeObserver(menuTrackingEndObserver) }
        if let menuDismissMonitor { NSEvent.removeMonitor(menuDismissMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    /// Items currently managed by the effective manual and automatic rules.
    var selectedItems: [MenuBarItem] {
        items.filter { $0.isSelected && !$0.isAlwaysVisibleSystemItem }
    }

    var automaticConstraintWidth: Double? {
        DisplayConstraint.minimumAvailableWidth(
            from: displays.map(\.constraintCandidate)
        )
    }

    /// Items currently in BarTuck's off-screen staging area but absent
    /// from the persisted selection set. This recovers protected macOS
    /// controls left there by an older build, including generic Control
    /// Center windows whose accessibility description is only "status menu"
    /// (for example Bluetooth on macOS 26).
    var overflowItems: [MenuBarItem] {
        let selectedIDs = Set(selectedItems.map(\.id))
        return items
            .filter { selectedIDs.contains($0.id) || isOffscreen($0) }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private func isOffscreen(_ item: MenuBarItem) -> Bool {
        item.windowRepresentations.contains {
            MenuBarGeometry.isOffscreenMenuItem($0.frame,
                displayBounds: $0.sourceDisplayBounds.map { [$0] } ?? displays.map(\.frame))
        }
    }

    /// Starts resilient discovery. Polling is intentional: NSWorkspace launch
    /// notifications omit LSUIElement/background applications, and status
    /// items can be created or replaced without their process launching.
    func startMonitoring() {
        guard monitorTimer == nil else { return }
        lastWindowSignature = scanner.windowSignature()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh(after: 0.35, reason: "workspace change") }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenParametersChanged() }
        }
        // Menu-bar changes are intentionally sampled at a low duty cycle.
        // Launch/terminate notifications and explicit panel refreshes still
        // provide immediate discovery; this timer is only the safety net for
        // background status-item processes that emit no notifications.
        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfWindowSetChanged() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer

        // Login items do not become ready at the same time. These bounded
        // rescans fill in late windows/icons without requiring user action.
        for delay in [0.8, 2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.items.isEmpty || !self.isReadyForManagedLayout else { return }
                self.scheduleRefresh(after: 0, reason: "startup retry")
            }
        }
    }

    func refresh() {
        if isUIPreviewMode {
            displays = DisplaySnapshotProvider.snapshots()
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            requiresScreenRecording = true
            captureGeneration += 1
            captureTask?.cancel()
            captureTask = nil
            isCapturing = false
            items = []
            displays = DisplaySnapshotProvider.snapshots()
            isReadyForManagedLayout = false
            iconCaptureMessage = "菜单栏读取权限未就绪"
            onLayoutStateChanged?()
            return
        }
        requiresScreenRecording = false
        guard !isRefreshing, !isCapturing else { refreshAgain = true; return }
        isRefreshing = true
        let previousByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let previousByWindowID = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.windowID.map { ($0, item) }
        })
        let knownBefore = preferences.knownItemIDs
        let knownWindowIDsBefore = preferences.knownWindowIDs
        let selectedBefore = preferences.selectedIDs
        let scanned = scanner.scan(selectedIDs: selectedBefore).filter { item in
            guard let windowID = item.windowID else { return true }
            return !ownedStatusWindowIDs.contains(windowID)
        }
        let currentIDs = Set(scanned.map(\.id))
        let currentWindowIDs = Set(scanned.compactMap(\.windowID))

        for item in scanned {
            let previous = previousByID[item.id] ?? item.windowID.flatMap { previousByWindowID[$0] }
            item.iconImage = previous?.iconImage
            item.rule = preferences.rule(for: item)
        }

        items = scanned
        displays = DisplaySnapshotProvider.snapshots()
        recomputeManagedSelection()
        preferences.saveKnownItems(knownBefore.union(currentIDs))
        preferences.saveKnownWindowIDs(knownWindowIDsBefore.union(currentWindowIDs))
        if !preferences.didApplyDefaultLayout, !scanned.isEmpty {
            preferences.didApplyDefaultLayout = true
        }
        lastWindowSignature = scanner.windowSignature()
        isRefreshing = false
        onLayoutStateChanged?()
        isReadyForManagedLayout = selectedItems.allSatisfy(\.hasUsableDisplayIcon)
        onImagesReady?()
        // Reconcile selected items that are still visible after a WindowServer
        // refresh. This is delayed until capture completes and guarded by the
        // same real-button check as explicit layout actions, so new status
        // items do not remain beside BarTuck while avoiding a drag during
        // an active user click.

        let captureCandidates = items.filter { $0.iconImage == nil }
        refreshImages(for: captureCandidates) { [weak self] in
            guard let self else { return }
            self.onLayoutStateChanged?()
            self.onImagesReady?()
            self.scheduleAutomaticLayoutIfNeeded()
            if self.refreshAgain {
                self.refreshAgain = false
                self.scheduleRefresh(after: 0.2, reason: "coalesced refresh")
            }
        }
    }

    func refreshIfWindowSetChanged(immediate: Bool = false) {
        let signature = scanner.windowSignature()
        guard signature != lastWindowSignature else { return }
        lastWindowSignature = signature
        if immediate {
            refresh()
        } else {
            scheduleRefresh(after: 0.4, reason: "menu bar window set changed")
        }
    }

    private func scheduleRefresh(after delay: TimeInterval, reason: String) {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.logger.debug("Refreshing after \(reason, privacy: .public)")
            self?.refresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func rule(for item: MenuBarItem) -> MenuItemRule { item.rule }

    func setRule(_ rule: MenuItemRule, for item: MenuBarItem) {
        guard !item.isAlwaysVisibleSystemItem else { return }
        if isUIPreviewMode {
            item.rule = rule
            item.isSelected = isManagedInPreview(item)
            objectWillChange.send()
            return
        }
        let wasManaged = item.isSelected
        item.rule = rule
        preferences.saveRule(rule, for: item.id)
        recomputeManagedSelection()

        if item.isSelected, layoutManagementEnabled {
            applyLayout()
        } else if wasManaged {
            layoutManager.show(item)
        }
    }

    func setSelected(_ item: MenuBarItem, selected: Bool) {
        setRule(selected ? .alwaysHidden : .alwaysVisible, for: item)
    }

    func selectAll(_ selected: Bool) {
        let previouslySelected = selectedItems
        var rules = preferences.itemRules
        for item in items where !item.isAlwaysVisibleSystemItem {
            item.rule = selected ? .alwaysHidden : .alwaysVisible
            rules[item.id] = item.rule
        }
        preferences.saveRules(rules)
        recomputeManagedSelection()
        if selected {
            applyLayout()
        } else if let controlItemFrame {
            layoutOperationMessage = "正在恢复菜单栏项目…"
            onLayoutOperationStateChanged?(false)
            layoutManager.restore(previouslySelected, relativeTo: controlItemFrame) { [weak self] count in
                self?.layoutOperationMessage = count > 0 ? "已恢复 \(count) 个菜单栏项目。" : "所有菜单栏项目均已显示。"
            }
        }
        onLayoutStateChanged?()
    }

    func resetRulesToAutomatic() {
        if isUIPreviewMode {
            for item in items where !item.isAlwaysVisibleSystemItem {
                item.rule = .automatic
                item.isSelected = isManagedInPreview(item)
            }
            objectWillChange.send()
            return
        }
        let previouslySelected = selectedItems
        var rules = preferences.itemRules
        for item in items where !item.isAlwaysVisibleSystemItem {
            item.rule = .automatic
            rules[item.id] = .automatic
        }
        preferences.saveRules(rules)
        recomputeManagedSelection()
        restoreItems(previouslySelected.filter { !$0.isSelected })
        if layoutManagementEnabled { applyLayout() }
    }

    func setAutomaticAvoidanceEnabled(_ enabled: Bool) {
        if isUIPreviewMode {
            automaticAvoidanceEnabled = enabled
            for item in items {
                item.isSelected = isManagedInPreview(item)
            }
            objectWillChange.send()
            return
        }
        let previouslySelected = selectedItems
        preferences.automaticAvoidanceEnabled = enabled
        automaticAvoidanceEnabled = enabled
        recomputeManagedSelection()
        restoreItems(previouslySelected.filter { !$0.isSelected })
        if enabled, layoutManagementEnabled { applyLayout() }
    }

    private func handleScreenParametersChanged() {
        let previouslySelected = selectedItems
        displays = DisplaySnapshotProvider.snapshots()
        recomputeManagedSelection()
        restoreItems(previouslySelected.filter { !$0.isSelected })
        scheduleRefresh(after: 0.35, reason: "display configuration changed")
    }

    private func recomputeManagedSelection() {
        let constrainedDisplay = displays
            .filter { $0.availableMenuWidth != nil }
            .min {
                ($0.availableMenuWidth ?? .greatestFiniteMagnitude) <
                    ($1.availableMenuWidth ?? .greatestFiniteMagnitude)
            }

        let policySource: [MenuBarItem]
        if let constrainedDisplay {
            policySource = items.filter { item in
                item.rule == .alwaysHidden ||
                    isOffscreen(item) ||
                    item.representation(on: constrainedDisplay.frame) != nil
            }
        } else {
            policySource = items
        }

        let policyItems = policySource.map { item in
            let geometryItem = constrainedDisplay.flatMap { item.representation(on: $0.frame) } ?? item
            let effectiveRule: MenuItemRule = if item.isAlwaysVisibleSystemItem {
                .alwaysVisible
            } else if !automaticAvoidanceEnabled && item.rule == .automatic {
                .alwaysVisible
            } else {
                item.rule
            }

            return OverflowPolicyItem(
                id: item.id,
                width: Double(geometryItem.frame.width),
                position: Double(geometryItem.frame.minX),
                rule: effectiveRule,
                isProtected: item.isAlwaysVisibleSystemItem,
                isOffscreen: MenuBarGeometry.isOffscreenMenuItem(geometryItem.frame,
                    displayBounds: constrainedDisplay.map { [$0.frame] } ?? displays.map(\.frame))
            )
        }

        let managedIDs = OverflowPolicy.managedItemIDs(
            from: policyItems,
            availableWidth: automaticAvoidanceEnabled
                ? constrainedDisplay?.availableMenuWidth
                : nil
        )

        for item in items {
            item.isSelected = !item.isAlwaysVisibleSystemItem && managedIDs.contains(item.id)
        }
        preferences.saveSelected(Set(items.filter(\.isSelected).map(\.id)))
        isReadyForManagedLayout = selectedItems.allSatisfy(\.hasUsableDisplayIcon)
        objectWillChange.send()
        onLayoutStateChanged?()
    }

    private func restoreItems(_ itemsToRestore: [MenuBarItem]) {
        guard !itemsToRestore.isEmpty, let controlItemFrame else { return }
        layoutOperationMessage = "正在恢复应常显的项目…"
        layoutManager.restore(itemsToRestore, relativeTo: controlItemFrame) { [weak self] count in
            self?.layoutOperationMessage = count > 0
                ? "已恢复 \(count) 个菜单栏项目。"
                : "所有菜单栏项目均已显示。"
        }
    }

    func refreshImages(for target: [MenuBarItem]? = nil, completion: (() -> Void)? = nil) {
        if isUIPreviewMode {
            completion?()
            return
        }
        guard CGPreflightScreenCaptureAccess() else { completion?(); return }
        // A panel open can arrive while the startup refresh is still
        // capturing. Do not launch a second ScreenCaptureKit enumeration;
        // overlapping captures were a major source of memory spikes and
        // apparent hangs.
        guard !isCapturing else { return }
        captureGeneration += 1
        let generation = captureGeneration
        let candidates = target ?? overflowItems
        isCapturing = true
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            let images = await self.captureService.capture(candidates)
            guard generation == self.captureGeneration else { return }
            self.captureTask = nil
            self.isCapturing = false
            for (id, image) in images {
                self.items.first(where: { $0.id == id })?.iconImage = image
            }
            let availableCount = self.items.filter { $0.iconImage != nil }.count
            self.iconCaptureMessage = self.items.isEmpty
                ? nil
                : "已载入 \(availableCount)/\(self.items.count) 个菜单栏图标。"
            self.isReadyForManagedLayout = self.selectedItems.allSatisfy(\.hasUsableDisplayIcon)
            self.objectWillChange.send()
            completion?()
        }
    }

    func updateControlItemFrame(_ frame: CGRect) { controlItemFrame = frame }

    func updateStatusItemWindowIDs(control: CGWindowID?, hidden: CGWindowID?) {
        let previousOwnedStatusWindowIDs = ownedStatusWindowIDs
        ownedStatusWindowIDs.formUnion([control, hidden].compactMap { $0 })
        scanner.setOwnedStatusWindowIDs(ownedStatusWindowIDs)
        layoutManager.setStatusItemWindowIDs(control: control, hidden: hidden)
        if ownedStatusWindowIDs != previousOwnedStatusWindowIDs, !items.isEmpty {
            scheduleRefresh(after: 0, reason: "owned status windows changed")
        }
    }

    func setLayoutManagementEnabled(_ enabled: Bool) {
        if isUIPreviewMode {
            layoutManagementEnabled = enabled
            layoutOperationMessage = enabled ? "预览：菜单栏布局管理已开启。" : "预览：仅保留规则，不移动原图标。"
            return
        }
        guard !enabled || (AXIsProcessTrusted() && CGPreflightScreenCaptureAccess()) else {
            layoutOperationMessage = "请先授予辅助功能和屏幕录制权限。"
            return
        }
        layoutManager.isEnabled = enabled
        layoutManagementEnabled = enabled
        onLayoutStateChanged?()
        if enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.applyLayout() }
        } else {
            automaticLayoutWorkItem?.cancel()
            restoreLayout()
        }
    }

    private func scheduleAutomaticLayoutIfNeeded() {
        guard preferences.hasCompletedOnboarding,
              layoutManagementEnabled,
              !isApplyingLayout,
              !selectedItems.isEmpty,
              isReadyForManagedLayout,
              selectedItems.contains(where: layoutManager.isVisible) else { return }
        automaticLayoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.automaticLayoutWorkItem = nil
            self.applyLayout()
        }
        automaticLayoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func applyLayout() {
        if isUIPreviewMode {
            layoutOperationMessage = "预览：当前三态规则已应用。"
            return
        }
        guard layoutManagementEnabled, !selectedItems.isEmpty else { return }
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            layoutOperationMessage = "权限未就绪，未执行菜单栏移动。"
            return
        }
        guard isReadyForManagedLayout else {
            layoutOperationMessage = "正在等待所选图标准备完成，暂未应用布局。"
            return
        }
        if isApplyingLayout {
            shouldApplyLayoutAgain = true
            return
        }
        // Never begin a WindowServer status-item move while the user is in the
        // middle of a real click or drag.
        if CGEventSource.buttonState(.combinedSessionState, button: .left) ||
            CGEventSource.buttonState(.combinedSessionState, button: .right) {
            scheduleLayoutRetry(after: 0.2)
            return
        }
        automaticLayoutWorkItem?.cancel()
        automaticLayoutWorkItem = nil
        isApplyingLayout = true
        layoutOperationMessage = "正在应用收纳布局…"
        onLayoutOperationStateChanged?(true)
        layoutStartGeneration += 1
        let startGeneration = layoutStartGeneration
        let start = DispatchWorkItem { [weak self] in
            guard let self, self.layoutStartGeneration == startGeneration, self.isApplyingLayout else { return }
            self.layoutStartWorkItem = nil
            self.layoutManager.hide(selectedItems, relativeTo: self.controlItemFrame ?? .zero) { [weak self] count in
                guard let self else { return }
                // Re-expand the staging host before judging visibility. The
                // enlarged host is what pushes the newly adjacent items off
                // the active display. Keep the operation active during this
                // settling window so a WindowServer refresh cannot re-enter
                // `applyLayout` and shrink the staging host again.
                self.onLayoutOperationStateChanged?(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isApplyingLayout = false
                    let remaining = self.selectedItems.filter(self.layoutManager.needsHiding)
                    if remaining.isEmpty {
                        self.layoutRepairAttempts = 0
                        self.layoutOperationMessage = count > 0 ? "收纳布局已更新，移动了 \(count) 个项目。" : "当前项目均已处于正确位置。"
                    } else if self.layoutRepairAttempts < 2 {
                        self.layoutRepairAttempts += 1
                        self.layoutOperationMessage = "正在修复收纳布局，剩余 \(remaining.count) 个项目…"
                        self.scheduleLayoutRetry(after: 0.4)
                    } else {
                        self.layoutOperationMessage = "仍有 \(remaining.count) 个项目未收纳，请再次点击“应用当前布局”。"
                    }
                    if self.shouldApplyLayoutAgain {
                        self.shouldApplyLayoutAgain = false
                        self.scheduleLayoutRetry(after: 0.2)
                    }
                }
            }
        }
        layoutStartWorkItem = start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: start)
    }

    private func scheduleLayoutRetry(after delay: TimeInterval) {
        layoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.applyLayout() }
        layoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func restoreLayout(completion: @escaping () -> Void = {}) {
        if isUIPreviewMode {
            layoutOperationMessage = "预览：原菜单栏图标已恢复显示。"
            completion()
            return
        }
        layoutStartWorkItem?.cancel()
        layoutStartWorkItem = nil
        layoutStartGeneration += 1
        isApplyingLayout = false
        guard let controlItemFrame else { completion(); return }
        layoutOperationMessage = "正在恢复菜单栏项目…"
        onLayoutOperationStateChanged?(false)
        layoutManager.restore(selectedItems, relativeTo: controlItemFrame) { [weak self] count in
            self?.layoutOperationMessage = count > 0 ? "已恢复 \(count) 个菜单栏项目。" : "所有菜单栏项目均已显示。"
            completion()
        }
    }

    func restoreAllAndDisable() {
        if isUIPreviewMode {
            layoutManagementEnabled = false
            layoutOperationMessage = "预览：已完成安全重置。"
            for item in items where !item.isAlwaysVisibleSystemItem {
                item.rule = .automatic
                item.isSelected = false
            }
            objectWillChange.send()
            return
        }
        layoutManager.isEnabled = false
        layoutManagementEnabled = false
        onLayoutStateChanged?()
        restoreLayout { [weak self] in
            guard let self else { return }
            self.preferences.resetLayoutState()
            self.items.forEach { $0.isSelected = false }
            self.restoreProtectedSystemItems { [weak self] in
                self?.refresh()
            }
        }
    }

    func prepareForTermination(completion: @escaping () -> Void) {
        captureGeneration += 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        restoreLayout(completion: completion)
    }

    func restoreProtectedSystemItems(completion: @escaping () -> Void = {}) {
        layoutManager.restoreProtectedSystemItems { _ in completion() }
    }

    func prepareForUIPreview() {
        guard isUIPreviewMode else { return }
        displays = DisplaySnapshotProvider.snapshots()
        let displayFrame = displays.first(where: \.isMain)?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let startX = displayFrame.maxX - 520
        let y = displayFrame.minY

        let samples: [(String, String, String, MenuItemRule, Bool, Bool, String)] = [
            ("preview-window", "窗口布局", "WindowPilot", .automatic, true, false, "macwindow"),
            ("preview-focus", "专注计时", "Focus Flow", .alwaysVisible, false, false, "timer"),
            ("preview-clipboard", "剪贴板", "ClipStack", .automatic, true, false, "doc.on.clipboard"),
            ("preview-vpn", "VPN", "Shield Link", .alwaysHidden, true, false, "lock.shield"),
            ("preview-wifi", "WiFi", "系统菜单栏", .automatic, false, true, "wifi"),
            ("preview-audio", "声音", "系统菜单栏", .alwaysVisible, false, true, "speaker.wave.2"),
            ("preview-recording", "Screen Recording", "系统菜单栏", .alwaysVisible, false, true, "record.circle")
        ]

        items = samples.enumerated().map { index, sample in
            MenuBarItem(
                id: sample.0,
                title: sample.1,
                ownerName: sample.2,
                bundleIdentifier: sample.5 ? "com.apple.controlcenter" : "com.bartuck.preview",
                frame: CGRect(x: startX + CGFloat(index * 42), y: y, width: 28, height: 24),
                axElement: nil,
                iconImage: NSImage(systemSymbolName: sample.6, accessibilityDescription: sample.1),
                isSelected: sample.4,
                supportsPressAction: true,
                isProtectedSystemItem: sample.5,
                rule: sample.3
            )
        }
        layoutManagementEnabled = true
        automaticAvoidanceEnabled = true
        isReadyForManagedLayout = true
        iconCaptureMessage = "安全预览 · 7 个菜单项"
        layoutOperationMessage = nil
    }

    private var previewAutomaticManagedIDs: Set<String> {
        ["preview-window", "preview-clipboard"]
    }

    private func isManagedInPreview(_ item: MenuBarItem) -> Bool {
        PreviewSelectionPolicy.isManaged(
            itemID: item.id,
            rule: item.rule,
            isProtected: item.isAlwaysVisibleSystemItem,
            automaticAvoidanceEnabled: automaticAvoidanceEnabled,
            automaticManagedIDs: previewAutomaticManagedIDs
        )
    }

    func activate(_ requestedItem: MenuBarItem, mouseButton: CGMouseButton = .left, retryCount: Int = 0) {
        guard AXIsProcessTrusted() else {
            lastActivationError = "请先授予辅助功能权限。"
            return
        }
        let logicalItem = items.first { $0.id == requestedItem.id } ?? requestedItem
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let display = mouseScreen.flatMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        let item = logicalItem.activationTarget(on: display)
        guard activatingItemID == nil else { return }
        cancelPendingRehide()
        activatingItemID = item.id
        lastActivationError = nil
        if mouseButton == .left, activator.activateDirectly(item) {
            rehideAfterNextUserClick(item)
            finishActivation()
            return
        }
        // WindowServer-backed items can be clicked directly without a global
        // Accessibility hit-test. This avoids an unbounded AX IPC call and
        // removes the extra round trip from the common visible-item path.
        if mouseButton == .left,
           item.windowID != nil,
           layoutManager.isVisible(item) {
            activator.activateMovedItem(item, mouseButton: .left) { [weak self] success in
                guard let self else { return }
                guard success else {
                    self.retryActivation(item, mouseButton: .left, retryCount: retryCount, message: "无法激活 \(item.tooltip)。")
                    return
                }
                self.rehideAfterNextUserClick(item)
                self.finishActivation()
            }
            return
        }
        // An AX element can go stale after a status-item rebuild. Refresh it
        // only when we already had an AX-backed item; window-backed items skip
        // this expensive full-tree walk and use the direct per-process path
        // after their short reveal.
        if mouseButton == .left, item.axElement != nil, activateUsingFreshAccessibility(item) {
            rehideAfterNextUserClick(item)
            finishActivation()
            return
        }
        if mouseButton == .left,
           item.windowID == nil,
           activator.activateViaAccessibilityHitTest(item) {
            rehideAfterNextUserClick(item)
            finishActivation()
            return
        }
        if mouseButton == .right, layoutManager.isVisible(item) {
            let pointer = layoutManager.currentPointerLocation()
            activator.activateRightClick(item) { [weak self] success in
                guard let self else { return }
                self.layoutManager.restorePointerLocation(pointer)
                guard success else {
                    self.retryActivation(item, mouseButton: mouseButton, retryCount: retryCount, message: "无法打开 \(item.tooltip) 的右键菜单。")
                    return
                }
                self.finishActivation()
            }
            return
        }
        // Preserve the real pointer across the complete reveal → click →
        // rehide transaction. Each synthetic event can otherwise overwrite
        // WindowServer's logical location before the next phase starts.
        activateByTemporarilyRevealing(item, mouseButton: mouseButton, restoreCursorLocation: layoutManager.currentPointerLocation(), retryCount: retryCount)
    }

    private func activateUsingFreshAccessibility(_ item: MenuBarItem) -> Bool {
        guard let fresh = scanner.refreshAccessibility(for: item), fresh.supportsPress else { return false }
        item.axElement = fresh.element
        item.supportsPressAction = true
        return activator.activateDirectly(item)
    }

    private func activateByTemporarilyRevealing(_ item: MenuBarItem, mouseButton: CGMouseButton, restoreCursorLocation: CGPoint?, retryCount: Int) {
        layoutManager.reveal(item, restoreCursorLocation: restoreCursorLocation) { [weak self] moved in
            guard let self else { return }
            guard moved else {
                self.retryActivation(item, mouseButton: mouseButton, retryCount: retryCount, message: "无法临时显示 \(item.tooltip)。")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                // Once the item is visible again, resolve the current
                // WindowServer element instead of relying on the stale AX
                // reference captured during scanning. This is both faster
                // and safer than injecting a mouse event into Control Center.
                if mouseButton == .left,
                   self.itemUsesAccessibility(item),
                   self.activator.activateDirectly(item)
                    || self.activator.activateViaAccessibilityHitTest(item) {
                    self.rehideAfterNextUserClick(item)
                    self.finishActivation()
                    return
                }
                self.activator.activateMovedItem(item, mouseButton: mouseButton) { [weak self] success in
                    guard let self else { return }
                    self.layoutManager.restorePointerLocation(restoreCursorLocation)
                    guard success else {
                        self.layoutManager.rehide(item, restoreCursorLocation: restoreCursorLocation)
                        self.retryActivation(item, mouseButton: mouseButton, retryCount: retryCount, message: "无法激活 \(item.tooltip)。")
                        return
                    }
                    self.rehideAfterNextUserClick(item)
                    self.finishActivation()
                }
            }
        }
    }

    private func retryActivation(_ item: MenuBarItem, mouseButton: CGMouseButton, retryCount: Int, message: String) {
        guard retryCount < 1 else {
            lastActivationError = message
            finishActivation()
            return
        }
        finishActivation()
        // Control Center can replace a status-item window between the scan
        // and the click. A single fresh pass handles that race without
        // returning to the old multi-second activation transaction.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.refresh()
            self?.activate(item, mouseButton: mouseButton, retryCount: retryCount + 1)
        }
    }

    private func finishActivation() { activatingItemID = nil }

    private func itemUsesAccessibility(_ item: MenuBarItem) -> Bool {
        item.windowID == nil
    }

    private func rehideAfterNextUserClick(_ item: MenuBarItem) {
        guard layoutManagementEnabled, item.isSelected, !item.isAlwaysVisibleSystemItem else { return }
        pendingRehideItem = item

        // Popovers do not emit NSMenu tracking notifications. Install this
        // monitor after the originating click has completed. While an NSMenu
        // is tracking, menu-item clicks must be allowed to reach that menu;
        // the persistent didEndTracking observer above performs the rehide
        // after the menu has actually closed. Foreign-process menus are
        // handled by the bounded window-presence check below.
        if let menuDismissMonitor { NSEvent.removeMonitor(menuDismissMonitor) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.pendingRehideItem != nil else { return }
            self.menuDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          let item = self.pendingRehideItem,
                          self.menuTrackingDepth == 0 else { return }
                    // Check after the click has had time to open or dismiss a
                    // foreign-process menu. Never use the stale hardware
                    // pointer location as the deciding signal: synthetic
                    // activation events can leave it behind the menu item.
                    self.scheduleTransientDismissCheck(for: item)
                }
            }
        }

        // Some Control Center modules use a popover instead of NSMenu and do
        // not emit didEndTracking. Keep the item visible long enough for the
        // popover to open, then use a bounded fallback to restore the layout.
        rehideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let item = self.pendingRehideItem else { return }
            if self.hasVisibleTransientWindow(for: item) {
                self.scheduleTransientDismissCheck(for: item)
            } else {
                self.rehidePendingItem()
            }
        }
        rehideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func rehidePendingItem() {
        guard let item = pendingRehideItem else { return }
        pendingRehideItem = nil
        rehideWorkItem?.cancel()
        rehideWorkItem = nil
        transientDismissCheck?.cancel()
        transientDismissCheck = nil
        if let menuDismissMonitor {
            NSEvent.removeMonitor(menuDismissMonitor)
            self.menuDismissMonitor = nil
        }
        // Capture the pointer inside the actual menu/popover interaction. The
        // original panel position is stale by this point and restoring it
        // would reopen hover UI or leave other apps with a false hit target.
        onLayoutOperationStateChanged?(true)
        layoutManager.rehide(item, restoreCursorLocation: nil) { [weak self] _ in
            self?.onLayoutOperationStateChanged?(false)
        }
    }

    private func cancelPendingRehide() {
        rehideWorkItem?.cancel()
        rehideWorkItem = nil
        transientDismissCheck?.cancel()
        transientDismissCheck = nil
        if let menuDismissMonitor {
            NSEvent.removeMonitor(menuDismissMonitor)
            self.menuDismissMonitor = nil
        }
        pendingRehideItem = nil
    }

    /// Control Center's menus are foreign-process windows and never produce
    /// our NSMenu tracking notifications. Poll only after a user click rather
    /// than while idle, so a menu item click is never followed by an immediate
    /// rehide that dismisses the menu itself.
    private func hasVisibleTransientWindow(for item: MenuBarItem) -> Bool {
        guard let ownerPID = item.ownerPID else { return false }
        let protectedOwner = item.bundleIdentifier == "Control Center" ||
            NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == "com.apple.controlcenter"
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { info in
            guard let windowPID = MenuBarWindowServer.integer(kCGWindowOwnerPID as String, in: info),
                  let layer = MenuBarWindowServer.integer(kCGWindowLayer as String, in: info),
                  let bounds = MenuBarWindowServer.bounds(in: info) else { return false }
            let windowOwner = (info[kCGWindowOwnerName as String] as? String) ?? ""
            let sameOwner = pid_t(windowPID) == ownerPID || (protectedOwner && windowOwner == "Control Center")
            guard sameOwner else { return false }
            let width = bounds.width
            let height = bounds.height
            guard layer > 25 || (layer == 25 && height > 40) else { return false }
            return width > 4 && height > 4
        }
    }

    private func scheduleTransientDismissCheck(for item: MenuBarItem, attempt: Int = 0) {
        guard pendingRehideItem?.id == item.id else { return }
        transientDismissCheck?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pendingRehideItem?.id == item.id else { return }
            if self.hasVisibleTransientWindow(for: item) {
                // Keep a low-duty check alive for menus that remain open
                // beyond the normal eight-second safety window.
                self.scheduleTransientDismissCheck(for: item, attempt: min(attempt + 1, 80))
            } else {
                self.rehidePendingItem()
            }
        }
        transientDismissCheck = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}

import AppKit
import ApplicationServices
import Combine
import OSLog

@MainActor
final class MenuBarItemStore: ObservableObject {
    let permissions: PermissionManager
    let language: AppLanguageController
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
    @Published private(set) var temporarilyVisibleItemIDs = Set<String>()
    private(set) var isHiddenSectionActive = false
    private(set) var maskedItemIDs = Set<String>()
    let isUIPreviewMode: Bool

    private let logger = Logger(subsystem: "com.bartuck.app", category: "items")
    private let preferences: PreferencesStore
    private let scanner: MenuBarScanner
    private let platformPolicy: MenuBarPlatformPolicy
    private let captureOverride: (([MenuBarItem]) async -> [String: NSImage])?
    private let visibilityOverride: ((MenuBarItem) -> MenuItemVisibility)?
    typealias HideHandler = ([MenuBarItem], CGRect, @escaping (Int) -> Void) -> Void
    typealias NativeOverflowApplyHandler = (
        [MenuBarItem], [MenuBarItem], @escaping (NativeOverflowTransactionResult) -> Void
    ) -> Void
    typealias NativeOverflowRestoreHandler = (
        [MenuBarItem], @escaping (NativeOverflowTransactionResult) -> Void
    ) -> Void
    private let hideOverride: HideHandler?
    private let nativeOverflowApplyOverride: NativeOverflowApplyHandler?
    private let nativeOverflowRestoreOverride: NativeOverflowRestoreHandler?
    private let assessmentModeManager: any MenuBarAssessmentModeManaging
    private let runningBundleIdentifiers: () -> Set<String>
    private let ownBundleIdentifier: String?
    private let maskingController: MenuBarMaskingController
    private let captureService = MenuBarCaptureService()
    private let activator: any MenuBarItemActivating
    private let layoutManager: MenuBarLayoutManager
    private var ownedStatusWindowIDs: Set<CGWindowID> = []
    private var controlItemFrame: CGRect?
    private var layoutWorkItem: DispatchWorkItem?
    private var layoutStartWorkItem: DispatchWorkItem?
    private var layoutStartGeneration = 0
    private var automaticLayoutWorkItem: DispatchWorkItem?
    private var refreshWorkItem: DispatchWorkItem?
    private var maskAppearanceWorkItem: DispatchWorkItem?
    private var captureTask: Task<Void, Never>?
    private var monitorTimer: Timer?
    private var maskGeometryTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastWindowSignature = Set<String>()
    private var captureGeneration = 0
    private var isRefreshing = false
    private var isCapturing = false
    private var refreshAgain = false
    private var isApplyingLayout = false
    private var shouldApplyLayoutAgain = false
    private var automaticLayoutSuspended = false
    private var automaticInputIDs = Set<String>()
    private var isRestoringLayout = false
    private var isTerminating = false
    private var failedLayoutIDs = Set<String>()
    private var nativeOverflowItemIDs = Set<String>()
    private var nativeOverflowSpacerCount = 0
    private var nativeOverflowAppliedSpacerCount = 0
    private var assessmentHiddenItemIDs = Set<String>()

    private struct ItemPresentation: Equatable {
        let id: String
        let title: String
        let ownerName: String
        let bundleIdentifier: String?
        let menuBarHostBundleIdentifier: String?
        let resolvedTitle: String?
        let isSelected: Bool
        let rule: MenuItemRule
        let visibility: MenuItemVisibility
        let isProtected: Bool
        let hasWindow: Bool
        let menuBarImage: ObjectIdentifier?
        let displayImage: ObjectIdentifier?
        let menuBarImageIsTemplate: Bool
        let displayImageIsTemplate: Bool
    }

    private struct RefreshPresentation: Equatable {
        let items: [ItemPresentation]
        let displays: [DisplaySnapshot]
        let temporarilyVisibleItemIDs: Set<String>
        let isReadyForManagedLayout: Bool
        let requiresScreenRecording: Bool
        let iconCaptureMessage: String?
    }

    enum RefreshSource: Int {
        case manual, startup, externalChange, observation
    }
    var onImagesReady: (() -> Void)?
    var onLayoutStateChanged: (() -> Void)?
    var onLayoutOperationStateChanged: ((Bool) -> Void)?

    init(permissions: PermissionManager? = nil, preferences: PreferencesStore = PreferencesStore(),
         language: AppLanguageController = .shared,
         scanner: MenuBarScanner = MenuBarScanner(),
         captureOverride: (([MenuBarItem]) async -> [String: NSImage])? = nil,
         platformPolicy: MenuBarPlatformPolicy = .current,
         assessmentModeManager: (any MenuBarAssessmentModeManaging)? = nil,
         runningBundleIdentifiers: @escaping () -> Set<String> = {
             Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
         },
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
         visibilityOverride: ((MenuBarItem) -> MenuItemVisibility)? = nil,
         hideOverride: HideHandler? = nil,
         nativeOverflowApplyOverride: NativeOverflowApplyHandler? = nil,
         nativeOverflowRestoreOverride: NativeOverflowRestoreHandler? = nil,
         maskingController: MenuBarMaskingController? = nil,
         activator: any MenuBarItemActivating = MenuBarItemActivator()) {
        self.language = language
        self.permissions = permissions ?? PermissionManager(language: language)
        self.preferences = preferences
        self.scanner = scanner
        self.platformPolicy = platformPolicy
        self.assessmentModeManager = assessmentModeManager ?? MenuBarAssessmentModeController()
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.ownBundleIdentifier = ownBundleIdentifier
        self.captureOverride = captureOverride
        self.visibilityOverride = visibilityOverride
        self.hideOverride = hideOverride
        self.nativeOverflowApplyOverride = nativeOverflowApplyOverride
        self.nativeOverflowRestoreOverride = nativeOverflowRestoreOverride
        self.maskingController = maskingController ?? MenuBarMaskingController()
        self.activator = activator
        isUIPreviewMode = ProcessInfo.processInfo.arguments.contains("--ui-preview")
        layoutManager = MenuBarLayoutManager(
            preferences: preferences,
            platformPolicy: platformPolicy
        )
        layoutManager.setAccessibilityElementRefresher { item in
            scanner.refreshAccessibility(for: item)?.element
        }
        layoutManagementEnabled = layoutManager.isEnabled
        automaticAvoidanceEnabled = preferences.automaticAvoidanceEnabled
        displays = DisplaySnapshotProvider.snapshots()
    }

    deinit {
        monitorTimer?.invalidate()
        maskGeometryTimer?.invalidate()
        refreshWorkItem?.cancel()
        maskAppearanceWorkItem?.cancel()
        layoutWorkItem?.cancel()
        layoutStartWorkItem?.cancel()
        automaticLayoutWorkItem?.cancel()
        captureTask?.cancel()
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

    /// Rule selection is intent, not evidence that a window was hidden.
    var overflowItems: [MenuBarItem] {
        return items
            .filter {
                ($0.visibility == .hidden || temporarilyVisibleItemIDs.contains($0.id)) &&
                    !$0.isAlwaysVisibleSystemItem
            }
    }

    var temporarilyVisibleItems: [MenuBarItem] {
        items.filter { temporarilyVisibleItemIDs.contains($0.id) }
    }

    var isInteractionBusy: Bool {
        isApplyingLayout || isRestoringLayout || activatingItemID != nil || isTerminating
    }

    var hasActiveMaskOverlay: Bool {
        platformPolicy.movement == .maskOverlay && !maskedItemIDs.isEmpty
    }

    var hasActiveAssessmentMode: Bool {
        platformPolicy.movement == .assessmentMode &&
            assessmentModeManager.activeConfiguration != nil
    }

    func isTemporarilyVisible(_ item: MenuBarItem) -> Bool {
        temporarilyVisibleItemIDs.contains(item.id)
    }

    func visibilityDescription(for item: MenuBarItem) -> String {
        if isTemporarilyVisible(item) { return language.text("items.visibility.temporary") }
        if item.isSelected && failedLayoutIDs.contains(item.id) {
            return language.text("items.visibility.failed")
        }
        switch item.visibility {
        case .hidden: return language.text("items.visibility.hidden")
        case .partial: return language.text("items.visibility.partial")
        case .unknown: return language.text("items.visibility.unknown")
        case .visible:
            if !item.isSelected { return language.text("items.visibility.visible") }
            return layoutManagementEnabled
                ? language.text("items.visibility.pending")
                : language.text("items.visibility.disabled")
        }
    }

    private func refreshVisibilityFromWindows() {
        let presentationBefore = refreshPresentation()
        let frames = Dictionary(MenuBarWindowServer.windowInfo().compactMap { info -> (CGWindowID, CGRect)? in
            guard let number = MenuBarWindowServer.integer(kCGWindowNumber as String, in: info),
                  number > 0, number <= Int(CGWindowID.max), let frame = MenuBarWindowServer.bounds(in: info) else { return nil }
            return (CGWindowID(number), frame)
        }, uniquingKeysWith: { first, _ in first })
        for item in items {
            if platformPolicy.movement == .assessmentMode,
               assessmentHiddenItemIDs.contains(item.id),
               !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else if platformPolicy.movement == .maskOverlay,
               maskedItemIDs.contains(item.id),
               !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else if platformPolicy.movement == .nativeOverflow,
                      nativeOverflowItemIDs.contains(item.id),
                      !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else {
                item.updateVisibility(
                    displayBounds: displays.map(\.frame),
                    currentFrames: frames,
                    frameProvider: layoutManager.currentFrame(for:)
                )
            }
        }
        reconcileTemporarilyVisibleItems()
        publishRefreshCallbacksIfNeeded(previous: presentationBefore, itemsWereReplaced: false)
    }

    private func reconcileTemporarilyVisibleItems() {
        let currentIDs = Set(items.map(\.id))
        let managedIDs = Set(items.filter(\.isSelected).map(\.id))
        let visibleIDs = Set(items.filter { $0.visibility != .hidden }.map(\.id))
        let retained = temporarilyVisibleItemIDs.intersection(
            currentIDs.intersection(managedIDs).intersection(visibleIDs)
        )
        if temporarilyVisibleItemIDs != retained { temporarilyVisibleItemIDs = retained }
    }

    private func refreshPresentation() -> RefreshPresentation {
        RefreshPresentation(
            items: items.map { item in
                ItemPresentation(
                    id: item.id,
                    title: item.title,
                    ownerName: item.ownerName,
                    bundleIdentifier: item.bundleIdentifier,
                    menuBarHostBundleIdentifier: item.menuBarHostBundleIdentifier,
                    resolvedTitle: item.resolvedTitle,
                    isSelected: item.isSelected,
                    rule: item.rule,
                    visibility: item.visibility,
                    isProtected: item.isProtectedSystemItem,
                    hasWindow: item.windowID != nil,
                    menuBarImage: item.menuBarImage.map { ObjectIdentifier($0) },
                    displayImage: item.displayImage.map { ObjectIdentifier($0) },
                    menuBarImageIsTemplate: item.usesTemplateMenuBarIcon,
                    displayImageIsTemplate: item.usesTemplateIcon
                )
            },
            displays: displays,
            temporarilyVisibleItemIDs: temporarilyVisibleItemIDs,
            isReadyForManagedLayout: isReadyForManagedLayout,
            requiresScreenRecording: requiresScreenRecording,
            iconCaptureMessage: iconCaptureMessage
        )
    }

    private func publishRefreshCallbacksIfNeeded(previous: RefreshPresentation,
                                                 itemsWereReplaced: Bool) {
        guard previous != refreshPresentation() else { return }
        if !itemsWereReplaced { objectWillChange.send() }
        onLayoutStateChanged?()
        onImagesReady?()
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
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scanner.invalidateApplicationIdentityCache()
                    self?.scheduleRefresh(after: 0.35, reason: "workspace change")
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.handleWorkspaceAppearanceChanged(notification.name)
                }
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

        if platformPolicy.movement == .maskOverlay {
            let maskTimer = Timer(
                timeInterval: MenuBarMaskLayoutPolicy.liveGeometrySyncInterval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor in self?.reconcileLiveMaskGeometry() }
            }
            RunLoop.main.add(maskTimer, forMode: .common)
            maskGeometryTimer = maskTimer
        }

        // Login items do not become ready at the same time. These bounded
        // rescans fill in late windows/icons without requiring user action.
        for delay in [0.8, 2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.items.isEmpty || !self.isReadyForManagedLayout else { return }
                self.scheduleRefresh(after: 0, reason: "startup retry")
            }
        }
    }

    func refresh(source: RefreshSource = .manual) {
        DiagnosticLog.shared.record("refresh.request", ["source": source.rawValue, "layout": isApplyingLayout ? 1 : 0])
        if isUIPreviewMode {
            let latestDisplays = DisplaySnapshotProvider.snapshots()
            if displays != latestDisplays { displays = latestDisplays }
            return
        }
        guard !isTerminating else { return }
        guard !isApplyingLayout, !isRestoringLayout, activatingItemID == nil else {
            refreshAgain = true
            DiagnosticLog.shared.record("refresh.deferred")
            return
        }
        let presentationBefore = refreshPresentation()
        permissions.refresh(updateTimestamp: false)
        guard permissions.screenRecordingGranted else {
            if !requiresScreenRecording { requiresScreenRecording = true }
            captureGeneration += 1
            captureTask?.cancel()
            captureTask = nil
            isCapturing = false
            if platformPolicy.movement == .assessmentMode {
                assessmentModeManager.invalidate()
                assessmentHiddenItemIDs.removeAll()
                failedLayoutIDs.removeAll()
                temporarilyVisibleItemIDs.removeAll()
                automaticLayoutSuspended = false
                DiagnosticLog.shared.record("assessment.permission_revoked")
            }
            if platformPolicy.movement == .maskOverlay {
                let maskedCount = maskedItemIDs.union(maskingController.maskedItemIDs).count
                let removedWindows = maskingController.removeAll()
                maskedItemIDs.removeAll()
                failedLayoutIDs.removeAll()
                temporarilyVisibleItemIDs.removeAll()
                isHiddenSectionActive = false
                automaticLayoutSuspended = false
                if maskedCount > 0 || removedWindows > 0 {
                    DiagnosticLog.shared.record("mask.permission_revoked", [
                        "items": maskedCount,
                        "windows": removedWindows
                    ])
                }
            }
            if !items.isEmpty { items = [] }
            let latestDisplays = DisplaySnapshotProvider.snapshots()
            if displays != latestDisplays { displays = latestDisplays }
            if isReadyForManagedLayout { isReadyForManagedLayout = false }
            let permissionMessage = language.text("store.capture.permission")
            if iconCaptureMessage != permissionMessage { iconCaptureMessage = permissionMessage }
            publishRefreshCallbacksIfNeeded(previous: presentationBefore, itemsWereReplaced: true)
            return
        }
        if requiresScreenRecording { requiresScreenRecording = false }
        guard !isRefreshing, !isCapturing else { refreshAgain = true; return }
        isRefreshing = true
        let previousItems = Self.uniqueItemsPreservingFirstOccurrence(items)
        let removedPreviousDuplicates = items.count - previousItems.count
        if removedPreviousDuplicates > 0 {
            DiagnosticLog.shared.record("refresh.previous_duplicate_ids", [
                "removed": removedPreviousDuplicates
            ])
        }
        let previousByID = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.id, $0) })
        let previousByWindowID = Dictionary(previousItems.flatMap { item in
            item.windowRepresentations.compactMap { representation in representation.windowID.map { ($0, item) } }
        }, uniquingKeysWith: { first, _ in first })
        let previousOrder = Dictionary(uniqueKeysWithValues: previousItems.enumerated().map { ($0.element.id, $0.offset) })
        let knownBefore = preferences.knownItemIDs
        let knownWindowIDsBefore = preferences.knownWindowIDs
        let selectedBefore = preferences.selectedIDs
        let scannedItems = visibleScannedItems(selectedIDs: selectedBefore)
        let scanned = Self.uniqueItemsPreservingFirstOccurrence(scannedItems)
        let removedScannedDuplicates = scannedItems.count - scanned.count
        if removedScannedDuplicates > 0 {
            DiagnosticLog.shared.record("refresh.scanned_duplicate_ids", [
                "removed": removedScannedDuplicates
            ])
        }
        let currentIDs = Set(scanned.map(\.id))
        let currentWindowIDs = Set(scanned.compactMap(\.windowID))
        let latestDisplays = DisplaySnapshotProvider.snapshots()
        let displayBounds = latestDisplays.map(\.frame)

        let refreshed = scanned.map { scannedItem -> MenuBarItem in
            if let previous = previousByID[scannedItem.id] {
                previous.updateRuntimeState(from: scannedItem, displayBounds: displayBounds)
                previous.rule = preferences.rule(for: previous)
                return previous
            }
            let previous = scannedItem.windowID.flatMap { previousByWindowID[$0] }
            scannedItem.iconImage = previous?.iconImage
            scannedItem.rule = preferences.rule(for: scannedItem)
            return scannedItem
        }
        let merged = refreshed.sorted {
            let left = previousOrder[$0.id] ?? Int.max
            let right = previousOrder[$1.id] ?? Int.max
            return left == right ? $0.id < $1.id : left < right
        }
        let itemsWereReplaced = items.map(\.id) != merged.map(\.id)
        if itemsWereReplaced { items = merged }
        if displays != latestDisplays { displays = latestDisplays }
        for item in items {
            if platformPolicy.movement == .assessmentMode,
               assessmentHiddenItemIDs.contains(item.id),
               !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else if platformPolicy.movement == .maskOverlay,
               maskedItemIDs.contains(item.id),
               !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else if platformPolicy.movement == .nativeOverflow,
                      nativeOverflowItemIDs.contains(item.id),
                      !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else {
                item.updateVisibility(displayBounds: displays.map(\.frame))
            }
        }
        if platformPolicy.movement == .nativeOverflow {
            nativeOverflowItemIDs.formIntersection(currentIDs)
            if nativeOverflowItemIDs.isEmpty, isHiddenSectionActive {
                isHiddenSectionActive = false
                nativeOverflowAppliedSpacerCount = 0
            }
        }
        recomputeManagedSelection(publish: false)
        reconcileAppliedAssessmentModeAfterRefresh()
        reconcileAppliedMaskOverlayAfterRefresh()
        reconcileTemporarilyVisibleItems()
        preferences.saveKnownItems(knownBefore.union(currentIDs))
        preferences.saveKnownWindowIDs(knownWindowIDsBefore.union(currentWindowIDs))
        if !preferences.didApplyDefaultLayout, !scanned.isEmpty {
            preferences.didApplyDefaultLayout = true
        }
        lastWindowSignature = scanner.windowSignature()
        isRefreshing = false
        let ready = selectedItems.allSatisfy(\.hasUsableDisplayIcon)
        if isReadyForManagedLayout != ready { isReadyForManagedLayout = ready }
        let stableIDs = Set(items.filter { !$0.id.hasPrefix("session|") && !$0.isAlwaysVisibleSystemItem }.map(\.id))
        let canApplyNewItems = (source == .startup || source == .externalChange) && !stableIDs.subtracting(automaticInputIDs).isEmpty
        automaticInputIDs = stableIDs
        let presentationChanged = presentationBefore != refreshPresentation()
        publishRefreshCallbacksIfNeeded(previous: presentationBefore, itemsWereReplaced: itemsWereReplaced)
        DiagnosticLog.shared.record("refresh.result", ["source": source.rawValue, "items": items.count,
            "selected": selectedItems.count, "capture": items.filter { $0.iconImage == nil }.count,
            "changed": presentationChanged ? 1 : 0])
        let captureCandidates = items.filter { $0.iconImage == nil }
        refreshImages(for: captureCandidates) { [weak self] in
            guard let self else { return }
            if canApplyNewItems {
                self.scheduleAutomaticLayoutIfNeeded()
            }
            if self.refreshAgain {
                self.refreshAgain = false
                self.scheduleRefresh(after: 0.2, reason: "coalesced refresh", source: .observation)
            }
        }
    }

    static func uniqueItemsPreservingFirstOccurrence(_ items: [MenuBarItem]) -> [MenuBarItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    func refreshIfWindowSetChanged(immediate: Bool = false) {
        let signature = scanner.windowSignature()
        guard signature != lastWindowSignature else { return }
        lastWindowSignature = signature
        if immediate {
            refresh(source: .externalChange)
        } else {
            scheduleRefresh(after: 0.4, reason: "menu bar window set changed")
        }
    }

    private func scheduleRefresh(after delay: TimeInterval, reason: String, source: RefreshSource = .externalChange) {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.logger.debug("Refreshing after \(reason, privacy: .public)")
            self?.refresh(source: source)
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleMaskAppearanceRefresh(after delay: TimeInterval, reason: String) {
        guard platformPolicy.movement == .maskOverlay else { return }
        maskAppearanceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.maskAppearanceWorkItem = nil
            guard !self.isTerminating else { return }
            if self.isApplyingLayout || self.isRestoringLayout || self.activatingItemID != nil {
                self.scheduleMaskAppearanceRefresh(after: 0.25, reason: reason)
                return
            }
            guard !self.maskedItemIDs.union(self.maskingController.maskedItemIDs).isEmpty else { return }
            self.maskingController.refreshAppearance()
            self.logger.debug("Refreshed mask appearance after \(reason, privacy: .public)")
            DiagnosticLog.shared.record("mask.appearance_refresh")
        }
        maskAppearanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func handleWorkspaceAppearanceChanged(_ name: Notification.Name) {
        scanner.invalidateApplicationIdentityCache()
        scheduleRefresh(after: 0.25, reason: name.rawValue, source: .observation)
        scheduleMaskAppearanceRefresh(after: 0.45, reason: name.rawValue)
    }

    private func visibleScannedItems(selectedIDs: Set<String>) -> [MenuBarItem] {
        scanner.scan(selectedIDs: selectedIDs).filter { item in
            guard let windowID = item.windowID else { return true }
            return !ownedStatusWindowIDs.contains(windowID)
        }
    }

    func rule(for item: MenuBarItem) -> MenuItemRule { item.rule }

    func setRule(_ rule: MenuItemRule, for item: MenuBarItem) {
        guard !item.isAlwaysVisibleSystemItem else { return }
        if isUIPreviewMode {
            item.rule = rule
            item.isSelected = isManagedInPreview(item)
            item.visibility = item.isSelected && layoutManagementEnabled ? .hidden : .visible
            objectWillChange.send()
            return
        }
        let affectedIDs = platformPolicy.movement == .assessmentMode
            ? MenuBarAssessmentModePolicy.groupItemIDs(
                items: assessmentItems,
                itemID: item.id
            )
            : [item.id]
        let affectedItems = items.filter { affectedIDs.contains($0.id) }
        guard affectedItems.contains(where: { $0.rule != rule }) else { return }
        let previouslyManaged = affectedItems.filter(\.isSelected)
        DiagnosticLog.shared.record("rule.changed", [
            "window": Int(item.windowID ?? 0),
            "items": affectedItems.count
        ])
        var rules = preferences.itemRules
        for affectedItem in affectedItems {
            affectedItem.rule = rule
            failedLayoutIDs.remove(affectedItem.id)
            rules[affectedItem.id] = rule
        }
        preferences.saveRules(rules)
        recomputeManagedSelection()

        if affectedItems.contains(where: \.isSelected), layoutManagementEnabled {
            layoutOperationMessage = language.text("store.layout.changes_pending")
        } else if !previouslyManaged.isEmpty, layoutManagementEnabled {
            temporarilyVisibleItemIDs.subtract(affectedIDs)
            restoreItems(previouslyManaged)
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
        } else {
            restoreItems(previouslySelected)
        }
        onLayoutStateChanged?()
    }

    func resetRulesToAutomatic() {
        if isUIPreviewMode {
            for item in items where !item.isAlwaysVisibleSystemItem {
                item.rule = .automatic
                item.isSelected = isManagedInPreview(item)
                item.visibility = item.isSelected && layoutManagementEnabled ? .hidden : .visible
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
                item.visibility = item.isSelected && layoutManagementEnabled ? .hidden : .visible
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
        DiagnosticLog.shared.record("display.changed")
        scheduleRefresh(after: 0.5, reason: "display configuration changed", source: .observation)
        scheduleMaskAppearanceRefresh(after: 0.75, reason: "display configuration changed")
    }

    private func recomputeManagedSelection(publish: Bool = true) {
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

        let policyManagedIDs = OverflowPolicy.managedItemIDs(
            from: policyItems,
            availableWidth: automaticAvoidanceEnabled
                ? constrainedDisplay?.availableMenuWidth
                : nil
        )
        let managedIDs = platformPolicy.movement == .assessmentMode
            ? MenuBarAssessmentModePolicy.expandedManagedItemIDs(
                items: assessmentItems,
                managedItemIDs: policyManagedIDs
            )
            : policyManagedIDs

        for item in items {
            let selected = !item.isAlwaysVisibleSystemItem && managedIDs.contains(item.id)
            if item.isSelected != selected { item.isSelected = selected }
        }
        let selectedIDs = Set(items.filter(\.isSelected).map(\.id))
        if preferences.selectedIDs != selectedIDs { preferences.saveSelected(selectedIDs) }
        let retainedTemporaryIDs = temporarilyVisibleItemIDs.intersection(selectedIDs)
        if temporarilyVisibleItemIDs != retainedTemporaryIDs {
            temporarilyVisibleItemIDs = retainedTemporaryIDs
        }
        let ready = selectedItems.allSatisfy(\.hasUsableDisplayIcon)
        if isReadyForManagedLayout != ready { isReadyForManagedLayout = ready }
        if publish {
            objectWillChange.send()
            onLayoutStateChanged?()
        }
    }

    private func restoreItems(_ itemsToRestore: [MenuBarItem]) {
        guard !itemsToRestore.isEmpty else { return }
        if platformPolicy.movement == .assessmentMode {
            applyAssessmentModeLayout(
                automatic: false,
                clearTemporaryItems: false
            )
            return
        }
        if platformPolicy.movement == .maskOverlay {
            restoreMaskedItems(itemsToRestore)
            return
        }
        if platformPolicy.movement == .nativeOverflow {
            guard isHiddenSectionActive else { return }
            if selectedItems.isEmpty {
                restoreLayout()
            } else {
                applyNativeOverflowLayout(automatic: false)
            }
            return
        }
        let wasHiddenSectionActive = isHiddenSectionActive
        let actualItemsToRestore = itemsToRestore.filter { $0.visibility != .visible }
        guard !actualItemsToRestore.isEmpty else {
            let shouldRemainActive = wasHiddenSectionActive && !selectedItems.isEmpty
            if isHiddenSectionActive != shouldRemainActive {
                isHiddenSectionActive = shouldRemainActive
                onLayoutStateChanged?()
            }
            DiagnosticLog.shared.record("layout.restore_skipped_visible", [
                "requested": itemsToRestore.count
            ])
            return
        }
        guard let controlItemFrame else { return }
        cancelLayoutWork()
        isRestoringLayout = true
        onLayoutOperationStateChanged?(true)
        layoutOperationMessage = language.text("store.restore.visible_items")
        let generation = layoutStartGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.layoutStartGeneration == generation else { return }
            self.layoutManager.restore(actualItemsToRestore, relativeTo: controlItemFrame) { [weak self] count in
                guard let self, self.layoutStartGeneration == generation else { return }
                self.isRestoringLayout = false
                self.isHiddenSectionActive = wasHiddenSectionActive && !self.selectedItems.isEmpty
                self.onLayoutOperationStateChanged?(false)
                self.layoutOperationMessage = count == actualItemsToRestore.count
                    ? self.language.text("store.restore.count", count)
                    : self.language.text("store.restore.partial")
                self.scheduleRefresh(after: 0.3, reason: "restore settled", source: .observation)
            }
        }
    }

    func refreshImages(for target: [MenuBarItem]? = nil, completion: (() -> Void)? = nil) {
        if isUIPreviewMode {
            completion?()
            return
        }
        permissions.refresh(updateTimestamp: false)
        guard permissions.screenRecordingGranted else { completion?(); return }
        guard !candidatesAreEmpty(target) else { completion?(); return }
        guard !isApplyingLayout, !isRestoringLayout else { completion?(); return }
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
            let presentationBefore = self.refreshPresentation()
            let images: [String: NSImage]
            if let capture = self.captureOverride { images = await capture(candidates) }
            else { images = await self.captureService.capture(candidates) }
            guard generation == self.captureGeneration else { return }
            self.captureTask = nil
            self.isCapturing = false
            for (id, image) in images {
                guard let item = self.items.first(where: { $0.id == id }) else { continue }
                if item.iconImage !== image { item.iconImage = image }
            }
            let availableCount = self.items.filter { $0.iconImage != nil }.count
            let captureMessage = self.items.isEmpty
                ? nil
                : self.language.text("store.capture.count", availableCount, self.items.count)
            if self.iconCaptureMessage != captureMessage { self.iconCaptureMessage = captureMessage }
            let ready = self.selectedItems.allSatisfy(\.hasUsableDisplayIcon)
            if self.isReadyForManagedLayout != ready { self.isReadyForManagedLayout = ready }
            DiagnosticLog.shared.record("capture.result", ["requested": candidates.count, "captured": images.count])
            self.publishRefreshCallbacksIfNeeded(previous: presentationBefore, itemsWereReplaced: false)
            completion?()
        }
    }

    private func candidatesAreEmpty(_ target: [MenuBarItem]?) -> Bool { (target ?? overflowItems).isEmpty }

    func updateControlItemFrame(_ frame: CGRect) { controlItemFrame = frame }

    func updateStatusItemWindowIDs(control: CGWindowID?, hidden: [CGWindowID]) {
        let previousOwnedStatusWindowIDs = ownedStatusWindowIDs
        ownedStatusWindowIDs = Set([control].compactMap { $0 } + hidden)
        scanner.setOwnedStatusWindowIDs(ownedStatusWindowIDs)
        layoutManager.setStatusItemWindowIDs(control: control, hidden: hidden)
        if ownedStatusWindowIDs != previousOwnedStatusWindowIDs, !items.isEmpty {
            scheduleRefresh(after: 0.4, reason: "owned status windows changed", source: .observation)
        }
    }

    func updateStatusItemFrameProviders(
        control: @escaping () -> CGRect?,
        hidden: [() -> CGRect?]
    ) {
        let previousCount = nativeOverflowSpacerCount
        nativeOverflowSpacerCount = hidden.count
        layoutManager.setStatusItemFrameProviders(control: control, hidden: hidden)
        guard platformPolicy.movement == .nativeOverflow,
              previousCount > 0,
              previousCount != hidden.count,
              isHiddenSectionActive,
              layoutManagementEnabled,
              !isTerminating else { return }
        nativeOverflowAppliedSpacerCount = 0
        scheduleLayoutRetry(after: 0.45)
    }

    func setLayoutManagementEnabled(_ enabled: Bool) {
        if isUIPreviewMode {
            layoutManagementEnabled = enabled
            for item in items { item.visibility = item.isSelected && enabled ? .hidden : .visible }
            layoutOperationMessage = enabled
                ? language.text("store.preview.layout_enabled")
                : language.text("store.preview.layout_disabled")
            return
        }
        permissions.refresh(updateTimestamp: false)
        guard !enabled || permissions.isReady else {
            layoutOperationMessage = language.text("store.permission.inactive")
            return
        }
        layoutManager.isEnabled = enabled
        layoutManagementEnabled = enabled
        if enabled {
            onLayoutStateChanged?()
            automaticLayoutSuspended = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.applyLayout() }
        } else {
            temporarilyVisibleItemIDs.removeAll()
            automaticLayoutWorkItem?.cancel()
            if platformPolicy.movement != .nativeOverflow {
                isHiddenSectionActive = false
                onLayoutStateChanged?()
            }
            restoreLayout()
        }
    }

    private func scheduleAutomaticLayoutIfNeeded() {
        guard !automaticLayoutSuspended, !isTerminating, !isRestoringLayout, preferences.hasCompletedOnboarding,
              MenuBarInteractionPolicy.allowsAutomaticLayout(hasTemporarilyVisibleItems: !temporarilyVisibleItemIDs.isEmpty),
              layoutManagementEnabled,
              !isApplyingLayout,
              !selectedItems.isEmpty,
              (platformPolicy.movement == .maskOverlay ||
                platformPolicy.movement == .assessmentMode ||
                isReadyForManagedLayout),
              selectedItems.contains(where: needsLayoutMovement) else { return }
        automaticLayoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.automaticLayoutWorkItem = nil
            self.applyLayout(automatic: true)
        }
        automaticLayoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func applyLayout(automatic: Bool = false) {
        if isUIPreviewMode {
            layoutOperationMessage = language.text("store.preview.rules_applied")
            return
        }
        if platformPolicy.movement == .assessmentMode {
            applyAssessmentModeLayout(automatic: automatic)
            return
        }
        if platformPolicy.movement == .maskOverlay {
            applyMaskOverlayLayout(automatic: automatic)
            return
        }
        if platformPolicy.movement == .nativeOverflow {
            applyNativeOverflowLayout(automatic: automatic)
            return
        }
        guard layoutManagementEnabled, !selectedItems.isEmpty else { return }
        guard !isTerminating, !isRestoringLayout, activatingItemID == nil else { return }
        if automatic && automaticLayoutSuspended { return }
        if automatic && !MenuBarInteractionPolicy.allowsAutomaticLayout(
            hasTemporarilyVisibleItems: !temporarilyVisibleItemIDs.isEmpty
        ) { return }
        permissions.refresh(updateTimestamp: false)
        guard permissions.isReady else {
            layoutOperationMessage = language.text("store.permission.not_ready")
            return
        }
        guard isReadyForManagedLayout else {
            layoutOperationMessage = language.text("store.layout.waiting_icons")
            return
        }
        if isApplyingLayout {
            if !automatic { shouldApplyLayoutAgain = true }
            return
        }
        let planned = selectedItems
        let needed = planned.filter(needsLayoutMovement).count
        if needed == 0 {
            failedLayoutIDs.subtract(planned.map(\.id))
            if !automatic { automaticLayoutSuspended = false }
            layoutOperationMessage = language.text("store.layout.correct")
            DiagnosticLog.shared.record("layout.noop", ["automatic": automatic ? 1 : 0,
                "selected": planned.count])
            return
        }
        let leftButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let rightButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .right)
        if MenuBarInteractionPolicy.shouldDeferLayout(
            isAutomatic: automatic,
            leftButtonPressed: leftButtonPressed,
            rightButtonPressed: rightButtonPressed
        ) {
            DiagnosticLog.shared.record("layout.deferred_input", [
                "left": leftButtonPressed ? 1 : 0,
                "right": rightButtonPressed ? 1 : 0
            ])
            return
        }
        automaticLayoutWorkItem?.cancel()
        automaticLayoutWorkItem = nil
        if !automatic { automaticLayoutSuspended = false }
        isApplyingLayout = true
        layoutOperationMessage = language.text("store.layout.applying")
        onLayoutOperationStateChanged?(true)
        layoutStartGeneration += 1
        let startGeneration = layoutStartGeneration
        failedLayoutIDs.subtract(planned.map(\.id))
        let wasActive = isHiddenSectionActive
        DiagnosticLog.shared.record("layout.begin", ["transaction": startGeneration, "automatic": automatic ? 1 : 0,
            "selected": planned.count, "visible": needed])
        let start = DispatchWorkItem { [weak self] in
            guard let self, self.layoutStartGeneration == startGeneration, self.isApplyingLayout else { return }
            self.layoutStartWorkItem = nil
            self.executeHide(planned, frame: self.controlItemFrame ?? .zero) { [weak self] count in
                guard let self, self.layoutStartGeneration == startGeneration else { return }
                self.isHiddenSectionActive = wasActive || count > 0
                // Re-expand the staging host before judging visibility. The
                // enlarged host is what pushes the newly adjacent items off
                // the active display. Keep the operation active during this
                // settling window so a WindowServer refresh cannot re-enter
                // `applyLayout` and shrink the staging host again.
                self.onLayoutOperationStateChanged?(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard self.layoutStartGeneration == startGeneration else { return }
                    self.isApplyingLayout = false
                    self.refreshVisibilityFromWindows()
                    let remaining = planned.filter { plannedItem in
                        self.items.first(where: { $0.id == plannedItem.id })?.visibility != .hidden
                    }
                    if remaining.isEmpty && count >= needed {
                        self.layoutOperationMessage = count > 0
                            ? self.language.text("store.layout.updated", count)
                            : self.language.text("store.layout.correct")
                    } else {
                        self.failedLayoutIDs.formUnion(remaining.map(\.id))
                        self.automaticLayoutSuspended = true
                        self.layoutOperationMessage = self.language.text("store.layout.partial")
                    }
                    DiagnosticLog.shared.record("layout.end", ["transaction": startGeneration, "moved": count,
                        "remaining": remaining.count, "paused": self.automaticLayoutSuspended ? 1 : 0])
                    if self.shouldApplyLayoutAgain {
                        self.shouldApplyLayoutAgain = false
                        if !self.automaticLayoutSuspended { self.scheduleLayoutRetry(after: 0.4) }
                    }
                    if self.refreshAgain {
                        self.refreshAgain = false
                    }
                    self.scheduleRefresh(after: 0.3, reason: "layout settled", source: .observation)
                }
            }
        }
        layoutStartWorkItem = start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: start)
    }

    private var assessmentItems: [MenuBarAssessmentItem] {
        items.map { item in
            MenuBarAssessmentItem(
                id: item.id,
                resolvedBundleIdentifier: item.bundleIdentifier,
                hostBundleIdentifier: item.menuBarHostBundleIdentifier,
                isSelected: item.isSelected,
                isProtected: item.isAlwaysVisibleSystemItem,
                isTemporarilyVisible: temporarilyVisibleItemIDs.contains(item.id)
            )
        }
    }

    private func assessmentPlan() -> MenuBarAssessmentPlan {
        let assessmentItems = assessmentItems
        var running = runningBundleIdentifiers()
        running.formUnion(assessmentItems.compactMap { item in
            MenuBarAssessmentModePolicy.effectiveBundleIdentifier(
                resolved: item.resolvedBundleIdentifier,
                host: item.hostBundleIdentifier
            )
        })
        return MenuBarAssessmentModePolicy.plan(
            items: assessmentItems,
            runningBundleIdentifiers: running,
            ownBundleIdentifier: ownBundleIdentifier
        )
    }

    private func assessmentConfiguration(
        for plan: MenuBarAssessmentPlan
    ) -> MenuBarAssessmentConfiguration {
        MenuBarAssessmentConfiguration(
            allowedSystemItems: MenuBarAssessmentModePolicy.allowedSystemItemIdentifiers,
            allowedBundleIdentifiers: plan.allowedBundleIdentifiers
        )
    }

    private func reconcileAppliedAssessmentModeAfterRefresh() {
        guard platformPolicy.movement == .assessmentMode,
              assessmentModeManager.activeConfiguration != nil,
              !isTerminating,
              !isApplyingLayout,
              !isRestoringLayout else { return }
        let plan = assessmentPlan()
        if selectedItems.isEmpty {
            restoreAssessmentModeLayout(reportsOperation: false)
            return
        }
        if plan.hiddenBundleIdentifiers.isEmpty,
           temporarilyVisibleItemIDs.isEmpty,
           !plan.unresolvedSelectedItemIDs.isEmpty {
            restoreAssessmentModeLayout(reportsOperation: false)
            failedLayoutIDs = plan.unresolvedSelectedItemIDs
            automaticLayoutSuspended = true
            layoutOperationMessage = language.text("store.layout.partial")
            return
        }
        let configuration = assessmentConfiguration(for: plan)
        if assessmentModeManager.activeConfiguration == configuration {
            let stateChanged = assessmentHiddenItemIDs != plan.hiddenItemIDs ||
                failedLayoutIDs != plan.unresolvedSelectedItemIDs
            guard stateChanged else { return }
            commitAssessmentPlan(plan, changed: false)
            return
        }
        applyAssessmentPlan(
            plan,
            automatic: true,
            reportsOperation: false,
            allowsActiveActivation: false
        )
    }

    private func applyAssessmentModeLayout(
        automatic: Bool,
        clearTemporaryItems: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard platformPolicy.movement == .assessmentMode,
              layoutManagementEnabled,
              !isTerminating,
              !isRestoringLayout else {
            completion?(false)
            return
        }
        if automatic && automaticLayoutSuspended {
            completion?(false)
            return
        }
        if automatic && !MenuBarInteractionPolicy.allowsAutomaticLayout(
            hasTemporarilyVisibleItems: !temporarilyVisibleItemIDs.isEmpty
        ) {
            completion?(false)
            return
        }
        if clearTemporaryItems && !automatic {
            temporarilyVisibleItemIDs.removeAll()
        }

        let plan = assessmentPlan()
        guard !plan.hiddenBundleIdentifiers.isEmpty else {
            restoreAssessmentModeLayout()
            if !plan.unresolvedSelectedItemIDs.isEmpty {
                failedLayoutIDs = plan.unresolvedSelectedItemIDs
                automaticLayoutSuspended = true
                layoutOperationMessage = language.text("store.layout.partial")
                objectWillChange.send()
                onLayoutStateChanged?()
                completion?(false)
            } else {
                completion?(true)
            }
            return
        }

        permissions.refresh(updateTimestamp: false)
        guard permissions.isReady else {
            layoutOperationMessage = language.text("store.permission.not_ready")
            completion?(false)
            return
        }
        let leftButtonPressed = CGEventSource.buttonState(
            .combinedSessionState,
            button: .left
        )
        let rightButtonPressed = CGEventSource.buttonState(
            .combinedSessionState,
            button: .right
        )
        if MenuBarInteractionPolicy.shouldDeferLayout(
            isAutomatic: automatic,
            leftButtonPressed: leftButtonPressed,
            rightButtonPressed: rightButtonPressed
        ) {
            completion?(false)
            return
        }
        applyAssessmentPlan(
            plan,
            automatic: automatic,
            reportsOperation: true,
            allowsActiveActivation: false,
            completion: completion
        )
    }

    private func applyAssessmentPlan(
        _ plan: MenuBarAssessmentPlan,
        automatic: Bool,
        reportsOperation: Bool,
        allowsActiveActivation: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard allowsActiveActivation || activatingItemID == nil else {
            completion?(false)
            return
        }
        let configuration = assessmentConfiguration(for: plan)
        if assessmentModeManager.activeConfiguration == configuration {
            commitAssessmentPlan(plan, changed: false)
            completion?(plan.unresolvedSelectedItemIDs.isEmpty)
            return
        }
        if isApplyingLayout {
            if !automatic { shouldApplyLayoutAgain = true }
            completion?(false)
            return
        }

        automaticLayoutWorkItem?.cancel()
        automaticLayoutWorkItem = nil
        if !automatic { automaticLayoutSuspended = false }
        isApplyingLayout = true
        layoutOperationMessage = language.text("store.layout.applying")
        if reportsOperation { onLayoutOperationStateChanged?(true) }
        layoutStartGeneration += 1
        let generation = layoutStartGeneration
        let previousHiddenIDs = assessmentHiddenItemIDs
        DiagnosticLog.shared.record("assessment.layout_begin", [
            "transaction": generation,
            "automatic": automatic ? 1 : 0,
            "bundles": plan.hiddenBundleIdentifiers.count,
            "items": plan.hiddenItemIDs.count
        ])

        assessmentModeManager.apply(configuration) { [weak self] result in
            guard let self, self.layoutStartGeneration == generation else { return }
            self.isApplyingLayout = false
            let succeeded: Bool
            switch result {
            case .applied(let changed):
                self.commitAssessmentPlan(plan, changed: changed)
                succeeded = plan.unresolvedSelectedItemIDs.isEmpty
            case .unavailable, .failed, .timedOut, .cancelled:
                self.assessmentHiddenItemIDs = previousHiddenIDs
                self.failedLayoutIDs.formUnion(
                    plan.hiddenItemIDs.subtracting(previousHiddenIDs)
                )
                self.failedLayoutIDs.formUnion(plan.unresolvedSelectedItemIDs)
                self.automaticLayoutSuspended = true
                self.layoutOperationMessage = self.language.text("store.layout.partial")
                self.refreshVisibilityFromWindows()
                self.objectWillChange.send()
                self.onLayoutStateChanged?()
                succeeded = false
            }
            if reportsOperation { self.onLayoutOperationStateChanged?(false) }
            DiagnosticLog.shared.record("assessment.layout_end", [
                "transaction": generation,
                "success": succeeded ? 1 : 0,
                "hidden": self.assessmentHiddenItemIDs.count
            ])
            completion?(succeeded)

            if self.shouldApplyLayoutAgain {
                self.shouldApplyLayoutAgain = false
                if !self.automaticLayoutSuspended {
                    DispatchQueue.main.async { [weak self] in self?.applyLayout() }
                }
            }
            if self.refreshAgain {
                self.refreshAgain = false
                self.scheduleRefresh(
                    after: 0.1,
                    reason: "assessment operation completed",
                    source: .observation
                )
            }
        }
    }

    private func commitAssessmentPlan(
        _ plan: MenuBarAssessmentPlan,
        changed: Bool
    ) {
        assessmentHiddenItemIDs = plan.hiddenItemIDs
        failedLayoutIDs = plan.unresolvedSelectedItemIDs
        automaticLayoutSuspended = !plan.unresolvedSelectedItemIDs.isEmpty
        isHiddenSectionActive = false
        for item in items {
            if assessmentHiddenItemIDs.contains(item.id),
               !temporarilyVisibleItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else if temporarilyVisibleItemIDs.contains(item.id) {
                item.visibility = .visible
            } else if let visibilityOverride {
                item.visibility = visibilityOverride(item)
            } else {
                item.updateVisibility(
                    displayBounds: displays.map(\.frame),
                    frameProvider: layoutManager.currentFrame(for:)
                )
            }
        }
        if !plan.unresolvedSelectedItemIDs.isEmpty {
            layoutOperationMessage = language.text("store.layout.partial")
        } else if assessmentHiddenItemIDs.isEmpty {
            layoutOperationMessage = language.text("store.restore.original")
        } else if changed {
            layoutOperationMessage = language.text(
                "store.layout.updated",
                assessmentHiddenItemIDs.count
            )
        } else {
            layoutOperationMessage = language.text("store.layout.correct")
        }
        objectWillChange.send()
        onLayoutStateChanged?()
    }

    private func restoreAssessmentModeLayout(
        reportsOperation: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard platformPolicy.movement == .assessmentMode else {
            completion?()
            return
        }
        let hadActiveState = assessmentModeManager.activeConfiguration != nil ||
            !assessmentHiddenItemIDs.isEmpty
        cancelLayoutWork()
        if reportsOperation && hadActiveState {
            isRestoringLayout = true
            layoutOperationMessage = language.text("store.restore.progress")
            onLayoutOperationStateChanged?(true)
        }
        assessmentModeManager.invalidate()
        assessmentHiddenItemIDs.removeAll()
        failedLayoutIDs.removeAll()
        temporarilyVisibleItemIDs.removeAll()
        automaticLayoutSuspended = false
        isHiddenSectionActive = false
        for item in items {
            if let visibilityOverride {
                item.visibility = visibilityOverride(item)
            } else {
                item.updateVisibility(
                    displayBounds: displays.map(\.frame),
                    frameProvider: layoutManager.currentFrame(for:)
                )
            }
        }
        if reportsOperation && hadActiveState {
            isRestoringLayout = false
            onLayoutOperationStateChanged?(false)
            layoutOperationMessage = language.text("store.restore.original")
        }
        DiagnosticLog.shared.record("assessment.restore", [
            "active": hadActiveState ? 1 : 0
        ])
        objectWillChange.send()
        onLayoutStateChanged?()
        completion?()
    }

    private func applyNativeOverflowLayout(automatic: Bool) {
        guard platformPolicy.movement == .nativeOverflow,
              layoutManagementEnabled else { return }
        guard !isTerminating, !isRestoringLayout, activatingItemID == nil else { return }
        if automatic && automaticLayoutSuspended { return }
        if automatic && !MenuBarInteractionPolicy.allowsAutomaticLayout(
            hasTemporarilyVisibleItems: !temporarilyVisibleItemIDs.isEmpty
        ) { return }

        let planned = selectedItems
        if planned.isEmpty {
            if isHiddenSectionActive { restoreLayout() }
            return
        }
        permissions.refresh(updateTimestamp: false)
        guard permissions.isReady else {
            layoutOperationMessage = language.text("store.permission.not_ready")
            return
        }
        guard isReadyForManagedLayout else {
            layoutOperationMessage = language.text("store.layout.waiting_icons")
            return
        }
        let plannedIDs = Set(planned.map(\.id))
        if isHiddenSectionActive,
           nativeOverflowItemIDs == plannedIDs,
           temporarilyVisibleItemIDs.isEmpty,
           nativeOverflowAppliedSpacerCount == nativeOverflowSpacerCount {
            failedLayoutIDs.subtract(plannedIDs)
            if !automatic { automaticLayoutSuspended = false }
            layoutOperationMessage = language.text("store.layout.correct")
            DiagnosticLog.shared.record("native.layout_noop_store", [
                "automatic": automatic ? 1 : 0,
                "selected": planned.count,
                "spacers": nativeOverflowSpacerCount
            ])
            return
        }
        if isApplyingLayout {
            if !automatic { shouldApplyLayoutAgain = true }
            return
        }

        let leftButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let rightButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .right)
        if MenuBarInteractionPolicy.shouldDeferLayout(
            isAutomatic: automatic,
            leftButtonPressed: leftButtonPressed,
            rightButtonPressed: rightButtonPressed
        ) {
            DiagnosticLog.shared.record("native.layout_deferred_input", [
                "left": leftButtonPressed ? 1 : 0,
                "right": rightButtonPressed ? 1 : 0
            ])
            return
        }

        automaticLayoutWorkItem?.cancel()
        automaticLayoutWorkItem = nil
        if !automatic { automaticLayoutSuspended = false }
        let retained = items.filter {
            !plannedIDs.contains($0.id) && !$0.isAlwaysVisibleSystemItem
        }
        let previousOverflowIDs = nativeOverflowItemIDs
        let previousActive = isHiddenSectionActive
        let previousSpacerCount = nativeOverflowAppliedSpacerCount
        isApplyingLayout = true
        layoutOperationMessage = language.text("store.layout.applying")
        onLayoutOperationStateChanged?(true)
        layoutStartGeneration += 1
        let startGeneration = layoutStartGeneration
        failedLayoutIDs.subtract(plannedIDs)
        DiagnosticLog.shared.record("native.layout_store_begin", [
            "transaction": startGeneration,
            "automatic": automatic ? 1 : 0,
            "managed": planned.count,
            "retained": retained.count,
            "spacers": nativeOverflowSpacerCount
        ])

        let start = DispatchWorkItem { [weak self] in
            guard let self,
                  self.layoutStartGeneration == startGeneration,
                  self.isApplyingLayout else { return }
            self.layoutStartWorkItem = nil
            self.executeNativeOverflowApply(
                managed: planned,
                retained: retained
            ) { [weak self] result in
                guard let self,
                      self.layoutStartGeneration == startGeneration else { return }
                if result.succeeded {
                    self.nativeOverflowItemIDs = plannedIDs
                    self.temporarilyVisibleItemIDs.subtract(plannedIDs)
                    self.isHiddenSectionActive = true
                    self.nativeOverflowAppliedSpacerCount = self.nativeOverflowSpacerCount
                    self.failedLayoutIDs.subtract(plannedIDs)
                    self.automaticLayoutSuspended = false
                } else {
                    self.nativeOverflowItemIDs = previousOverflowIDs
                    self.isHiddenSectionActive = previousActive
                    self.nativeOverflowAppliedSpacerCount = previousSpacerCount
                    self.failedLayoutIDs.formUnion(plannedIDs.subtracting(previousOverflowIDs))
                    self.automaticLayoutSuspended = true
                }
                self.onLayoutStateChanged?()
                self.onLayoutOperationStateChanged?(false)

                let settleDelay: TimeInterval = result.succeeded ? 0.9 : 0.25
                DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) { [weak self] in
                    guard let self,
                          self.layoutStartGeneration == startGeneration else { return }
                    self.isApplyingLayout = false
                    if result.succeeded {
                        for item in self.items {
                            if self.nativeOverflowItemIDs.contains(item.id),
                               !self.temporarilyVisibleItemIDs.contains(item.id) {
                                item.markMaskedHidden()
                            } else {
                                item.updateVisibility(displayBounds: self.displays.map(\.frame))
                            }
                        }
                        self.layoutOperationMessage = result.movedCount > 0
                            ? self.language.text("store.layout.updated", result.movedCount)
                            : self.language.text("store.layout.correct")
                    } else {
                        self.refreshVisibilityFromWindows()
                        self.layoutOperationMessage = self.language.text("store.layout.partial")
                    }
                    DiagnosticLog.shared.record("native.layout_store_end", [
                        "transaction": startGeneration,
                        "moved": result.movedCount,
                        "success": result.succeeded ? 1 : 0,
                        "rollback": result.rollbackSucceeded ? 1 : 0,
                        "hidden": self.nativeOverflowItemIDs.count
                    ])
                    self.objectWillChange.send()
                    if self.shouldApplyLayoutAgain {
                        self.shouldApplyLayoutAgain = false
                        if !self.automaticLayoutSuspended {
                            self.scheduleLayoutRetry(after: 0.4)
                        }
                    }
                    if self.refreshAgain { self.refreshAgain = false }
                    self.scheduleRefresh(
                        after: 0.25,
                        reason: "native overflow settled",
                        source: .observation
                    )
                }
            }
        }
        layoutStartWorkItem = start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: start)
    }

    private func executeNativeOverflowApply(
        managed: [MenuBarItem],
        retained: [MenuBarItem],
        completion: @escaping (NativeOverflowTransactionResult) -> Void
    ) {
        if let nativeOverflowApplyOverride {
            nativeOverflowApplyOverride(managed, retained, completion)
        } else {
            layoutManager.applyNativeOverflow(
                managed: managed,
                retained: retained,
                completion: completion
            )
        }
    }

    private func needsLayoutMovement(_ item: MenuBarItem) -> Bool {
        if platformPolicy.movement == .assessmentMode {
            return !assessmentHiddenItemIDs.contains(item.id) ||
                temporarilyVisibleItemIDs.contains(item.id)
        }
        if platformPolicy.movement == .maskOverlay {
            return !maskedItemIDs.contains(item.id)
        }
        if platformPolicy.movement == .nativeOverflow {
            return !nativeOverflowItemIDs.contains(item.id) ||
                temporarilyVisibleItemIDs.contains(item.id) ||
                nativeOverflowAppliedSpacerCount != nativeOverflowSpacerCount
        }
        let visibility = visibilityOverride?(item) ?? layoutManager.visibility(of: item)
        return visibility != .hidden
    }

    private func scheduleLayoutRetry(after delay: TimeInterval) {
        layoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.applyLayout() }
        layoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func retuckTemporarilyVisibleItems() {
        guard layoutManagementEnabled, !temporarilyVisibleItemIDs.isEmpty else { return }
        DiagnosticLog.shared.record("activation.retuck_requested", ["items": temporarilyVisibleItemIDs.count])
        layoutOperationMessage = language.text("store.activation.retuck_progress")
        if platformPolicy.movement == .assessmentMode {
            temporarilyVisibleItemIDs.removeAll()
        }
        applyLayout()
    }

    private func reconcileAppliedMaskOverlayAfterRefresh() {
        guard platformPolicy.movement == .maskOverlay else { return }
        let previouslyMasked = maskedItemIDs.union(maskingController.maskedItemIDs)
        guard !previouslyMasked.isEmpty else { return }
        let desired = items.filter {
            previouslyMasked.contains($0.id) && $0.isSelected
        }
        let desiredIDs = Set(desired.map(\.id))
        let result = maskingController.apply(items: desired)
        commitMaskOverlayResult(
            result,
            desiredItemIDs: desiredIDs,
            previouslyMaskedItemIDs: previouslyMasked
        )
        if result.changedWindowCount > 0 || !result.failedItemIDs.isEmpty {
            DiagnosticLog.shared.record("mask.refresh", [
                "windows": result.changedWindowCount,
                "masked": result.maskedItemIDs.count,
                "failed": result.failedItemIDs.count
            ])
        }
    }

    func reconcileLiveMaskGeometry() {
        guard platformPolicy.movement == .maskOverlay,
              layoutManagementEnabled,
              !isTerminating,
              !isApplyingLayout,
              !isRestoringLayout,
              activatingItemID == nil else { return }
        let selectedIDs = Set(selectedItems.map(\.id))
        failedLayoutIDs.formIntersection(selectedIDs)
        let previouslyMasked = maskedItemIDs.union(maskingController.maskedItemIDs)
        let trackedIDs = previouslyMasked.union(failedLayoutIDs)
        guard !trackedIDs.isEmpty else { return }
        let leftButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let rightButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .right)
        guard !leftButtonPressed, !rightButtonPressed else { return }

        let desired = items.filter { trackedIDs.contains($0.id) && $0.isSelected }
        let desiredIDs = Set(desired.map(\.id))
        let result = maskingController.apply(items: desired)
        let previousFailedIDs = failedLayoutIDs.intersection(trackedIDs)
        let nextFailedIDs = result.failedItemIDs.union(
            desiredIDs.subtracting(result.maskedItemIDs)
        )
        let stateChanged = result.maskedItemIDs != maskedItemIDs ||
            previousFailedIDs != nextFailedIDs
        if stateChanged {
            commitMaskOverlayResult(
                result,
                desiredItemIDs: desiredIDs,
                previouslyMaskedItemIDs: previouslyMasked
            )
            objectWillChange.send()
            onLayoutStateChanged?()
        }
        if result.changedWindowCount > 0 || !result.failedItemIDs.isEmpty {
            DiagnosticLog.shared.record("mask.geometry", [
                "windows": result.changedWindowCount,
                "masked": result.maskedItemIDs.count,
                "failed": result.failedItemIDs.count
            ])
        }
    }

    private func restoreMaskedItems(_ itemsToRestore: [MenuBarItem]) {
        let requestedIDs = Set(itemsToRestore.map(\.id))
        let previouslyMasked = maskedItemIDs.union(maskingController.maskedItemIDs)
        guard !previouslyMasked.intersection(requestedIDs).isEmpty else { return }

        let desiredIDs = previouslyMasked.subtracting(requestedIDs)
        let desired = items.filter { desiredIDs.contains($0.id) && $0.isSelected }
        let result = maskingController.apply(items: desired)
        commitMaskOverlayResult(
            result,
            desiredItemIDs: Set(desired.map(\.id)),
            previouslyMaskedItemIDs: previouslyMasked
        )
        let restoredCount = requestedIDs.subtracting(maskedItemIDs).count
        layoutOperationMessage = result.failedItemIDs.isEmpty
            ? language.text("store.restore.count", restoredCount)
            : language.text("store.restore.partial")
        DiagnosticLog.shared.record("mask.restore_items", [
            "requested": requestedIDs.count,
            "restored": restoredCount,
            "failed": result.failedItemIDs.count
        ])
        objectWillChange.send()
        onLayoutStateChanged?()
    }

    private func applyMaskOverlayLayout(
        automatic: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard platformPolicy.movement == .maskOverlay else {
            completion?(false)
            return
        }
        guard !isTerminating, !isRestoringLayout, activatingItemID == nil else {
            completion?(false)
            return
        }
        if automatic && automaticLayoutSuspended {
            completion?(false)
            return
        }
        if automatic && !MenuBarInteractionPolicy.allowsAutomaticLayout(
            hasTemporarilyVisibleItems: false
        ) {
            completion?(false)
            return
        }

        let desired = layoutManagementEnabled ? selectedItems : []
        let desiredIDs = Set(desired.map(\.id))
        if !desired.isEmpty {
            permissions.refresh(updateTimestamp: false)
            guard permissions.isReady else {
                layoutOperationMessage = language.text("store.permission.not_ready")
                completion?(false)
                return
            }
        }
        if isApplyingLayout {
            if !automatic { shouldApplyLayoutAgain = true }
            completion?(false)
            return
        }

        let leftButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let rightButtonPressed = CGEventSource.buttonState(.combinedSessionState, button: .right)
        if MenuBarInteractionPolicy.shouldDeferLayout(
            isAutomatic: automatic,
            leftButtonPressed: leftButtonPressed,
            rightButtonPressed: rightButtonPressed
        ) {
            DiagnosticLog.shared.record("mask.deferred_input", [
                "left": leftButtonPressed ? 1 : 0,
                "right": rightButtonPressed ? 1 : 0
            ])
            completion?(false)
            return
        }

        automaticLayoutWorkItem?.cancel()
        automaticLayoutWorkItem = nil
        if !automatic { automaticLayoutSuspended = false }
        isApplyingLayout = true
        temporarilyVisibleItemIDs.removeAll()
        layoutOperationMessage = desired.isEmpty
            ? language.text("store.restore.progress")
            : language.text("store.layout.applying")
        onLayoutOperationStateChanged?(true)
        let previouslyMasked = maskedItemIDs.union(maskingController.maskedItemIDs)
        DiagnosticLog.shared.record("mask.layout_begin", [
            "automatic": automatic ? 1 : 0,
            "desired": desiredIDs.count,
            "previous": previouslyMasked.count
        ])

        let result = maskingController.apply(items: desired)
        commitMaskOverlayResult(
            result,
            desiredItemIDs: desiredIDs,
            previouslyMaskedItemIDs: previouslyMasked
        )
        let failures = result.failedItemIDs.union(desiredIDs.subtracting(result.maskedItemIDs))
        automaticLayoutSuspended = !failures.isEmpty
        isApplyingLayout = false
        onLayoutOperationStateChanged?(false)

        if !failures.isEmpty {
            layoutOperationMessage = language.text("store.layout.partial")
        } else if desiredIDs.isEmpty {
            layoutOperationMessage = language.text("store.restore.original")
        } else if result.changedWindowCount > 0 || previouslyMasked != result.maskedItemIDs {
            layoutOperationMessage = language.text("store.layout.updated", result.maskedItemIDs.count)
        } else {
            layoutOperationMessage = language.text("store.layout.correct")
        }
        DiagnosticLog.shared.record("mask.layout_end", [
            "windows": result.changedWindowCount,
            "masked": result.maskedItemIDs.count,
            "failed": failures.count
        ])
        objectWillChange.send()
        onLayoutStateChanged?()
        completion?(failures.isEmpty)

        if shouldApplyLayoutAgain {
            shouldApplyLayoutAgain = false
            if !automaticLayoutSuspended {
                DispatchQueue.main.async { [weak self] in self?.applyLayout() }
            }
        }
        if refreshAgain {
            refreshAgain = false
            scheduleRefresh(after: 0.1, reason: "mask operation completed", source: .observation)
        }
    }

    private func commitMaskOverlayResult(
        _ result: MenuBarMaskApplicationResult,
        desiredItemIDs: Set<String>,
        previouslyMaskedItemIDs: Set<String>
    ) {
        let scopedIDs = desiredItemIDs.union(previouslyMaskedItemIDs)
        maskedItemIDs = result.maskedItemIDs
        failedLayoutIDs.subtract(scopedIDs)
        failedLayoutIDs.formUnion(result.failedItemIDs)
        failedLayoutIDs.formUnion(desiredItemIDs.subtracting(result.maskedItemIDs))
        isHiddenSectionActive = false

        for item in items {
            if maskedItemIDs.contains(item.id) {
                item.markMaskedHidden()
            } else if let visibilityOverride {
                item.visibility = visibilityOverride(item)
            } else {
                item.updateVisibility(
                    displayBounds: displays.map(\.frame),
                    frameProvider: layoutManager.currentFrame(for:)
                )
            }
        }
    }

    private func cancelLayoutWork() {
        layoutWorkItem?.cancel()
        layoutWorkItem = nil
        automaticLayoutWorkItem?.cancel()
        automaticLayoutWorkItem = nil
        layoutStartWorkItem?.cancel()
        layoutStartWorkItem = nil
        layoutStartGeneration += 1
        isApplyingLayout = false
        shouldApplyLayoutAgain = false
        layoutManager.cancelPendingOperations()
        DiagnosticLog.shared.record("layout.cancel", ["transaction": layoutStartGeneration])
    }

    private func executeHide(_ items: [MenuBarItem], frame: CGRect, completion: @escaping (Int) -> Void) {
        if let hideOverride { hideOverride(items, frame, completion) }
        else { layoutManager.hide(items, relativeTo: frame, completion: completion) }
    }

    func restoreLayout(completion: @escaping () -> Void = {}) {
        if isUIPreviewMode {
            layoutOperationMessage = language.text("store.preview.restored")
            for item in items { item.visibility = .visible }
            completion()
            return
        }
        if platformPolicy.movement == .assessmentMode {
            restoreAssessmentModeLayout(completion: completion)
            return
        }
        if platformPolicy.movement == .nativeOverflow {
            restoreNativeOverflowLayout(completion: completion)
            return
        }
        if platformPolicy.movement == .maskOverlay {
            cancelLayoutWork()
            temporarilyVisibleItemIDs.removeAll()
            isRestoringLayout = true
            onLayoutOperationStateChanged?(true)
            layoutOperationMessage = language.text("store.restore.progress")
            let previouslyMasked = maskedItemIDs.union(maskingController.maskedItemIDs)
            let removedWindows = maskingController.removeAll()
            failedLayoutIDs.removeAll()
            commitMaskOverlayResult(
                .init(maskedItemIDs: [], failedItemIDs: [], changedWindowCount: removedWindows),
                desiredItemIDs: [],
                previouslyMaskedItemIDs: previouslyMasked
            )
            isRestoringLayout = false
            onLayoutOperationStateChanged?(false)
            layoutOperationMessage = language.text("store.restore.original")
            DiagnosticLog.shared.record("mask.restore", [
                "items": previouslyMasked.count,
                "windows": removedWindows
            ])
            objectWillChange.send()
            onLayoutStateChanged?()
            completion()
            return
        }
        cancelLayoutWork()
        temporarilyVisibleItemIDs.removeAll()
        isRestoringLayout = true
        onLayoutStateChanged?()
        onLayoutOperationStateChanged?(true)
        guard let controlItemFrame else {
            isRestoringLayout = false
            isHiddenSectionActive = false
            onLayoutOperationStateChanged?(false)
            completion()
            return
        }
        layoutOperationMessage = language.text("store.restore.progress")
        let generation = layoutStartGeneration
        let planned = selectedItems
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.layoutStartGeneration == generation else { completion(); return }
            self.layoutManager.restore(planned, relativeTo: controlItemFrame) { [weak self] count in
                guard let self, self.layoutStartGeneration == generation else { completion(); return }
                self.isRestoringLayout = false
                self.isHiddenSectionActive = false
                self.onLayoutOperationStateChanged?(false)
                DiagnosticLog.shared.record("layout.restore", ["moved": count, "requested": planned.count])
                self.layoutOperationMessage = count == planned.count
                    ? self.language.text("store.restore.original")
                    : self.language.text("store.restore.original_partial")
                completion()
                if !self.isTerminating { self.scheduleRefresh(after: 0.3, reason: "restore settled", source: .observation) }
            }
        }
    }

    private func restoreNativeOverflowLayout(completion: @escaping () -> Void) {
        guard platformPolicy.movement == .nativeOverflow else {
            completion()
            return
        }
        if !isHiddenSectionActive && nativeOverflowItemIDs.isEmpty {
            failedLayoutIDs.removeAll()
            nativeOverflowAppliedSpacerCount = 0
            onLayoutStateChanged?()
            completion()
            return
        }

        cancelLayoutWork()
        temporarilyVisibleItemIDs.removeAll()
        isRestoringLayout = true
        layoutOperationMessage = language.text("store.restore.progress")
        onLayoutOperationStateChanged?(true)
        let generation = layoutStartGeneration
        let planned = items.filter { !$0.isAlwaysVisibleSystemItem }
        let previouslyOverflowed = nativeOverflowItemIDs
        DiagnosticLog.shared.record("native.restore_store_begin", [
            "transaction": generation,
            "items": planned.count,
            "hidden": previouslyOverflowed.count
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.layoutStartGeneration == generation else {
                completion()
                return
            }
            self.executeNativeOverflowRestore(items: planned) { [weak self] result in
                guard let self, self.layoutStartGeneration == generation else {
                    completion()
                    return
                }
                self.nativeOverflowItemIDs.removeAll()
                self.nativeOverflowAppliedSpacerCount = 0
                self.isHiddenSectionActive = false
                self.isRestoringLayout = false
                self.failedLayoutIDs.removeAll()
                self.onLayoutStateChanged?()
                self.onLayoutOperationStateChanged?(false)
                if result.succeeded {
                    for item in self.items where previouslyOverflowed.contains(item.id) {
                        item.visibility = .visible
                    }
                    self.layoutOperationMessage = self.language.text("store.restore.original")
                } else {
                    self.layoutOperationMessage = self.language.text("store.restore.original_partial")
                }
                DiagnosticLog.shared.record("native.restore_store_end", [
                    "transaction": generation,
                    "moved": result.movedCount,
                    "success": result.succeeded ? 1 : 0,
                    "rollback": result.rollbackSucceeded ? 1 : 0
                ])
                self.objectWillChange.send()
                completion()
                if !self.isTerminating {
                    self.scheduleRefresh(
                        after: 0.3,
                        reason: "native restore settled",
                        source: .observation
                    )
                }
            }
        }
    }

    private func executeNativeOverflowRestore(
        items: [MenuBarItem],
        completion: @escaping (NativeOverflowTransactionResult) -> Void
    ) {
        if let nativeOverflowRestoreOverride {
            nativeOverflowRestoreOverride(items, completion)
        } else {
            layoutManager.restoreNativeOverflow(items: items, completion: completion)
        }
    }

    func restoreAllAndDisable() {
        if isUIPreviewMode {
            layoutManagementEnabled = false
            temporarilyVisibleItemIDs.removeAll()
            layoutOperationMessage = language.text("store.preview.reset")
            for item in items where !item.isAlwaysVisibleSystemItem {
                item.rule = .automatic
                item.isSelected = false
                item.visibility = .visible
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
        isTerminating = true
        monitorTimer?.invalidate()
        maskGeometryTimer?.invalidate()
        refreshWorkItem?.cancel()
        maskAppearanceWorkItem?.cancel()
        captureGeneration += 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        restoreLayout(completion: completion)
    }

    func restoreProtectedSystemItems(completion: @escaping () -> Void = {}) {
        if platformPolicy.movement == .maskOverlay ||
            platformPolicy.movement == .nativeOverflow ||
            platformPolicy.movement == .assessmentMode {
            completion()
            return
        }
        layoutManager.restoreProtectedSystemItems { _ in completion() }
    }

    func prepareForUIPreview() {
        guard isUIPreviewMode else { return }
        displays = DisplaySnapshotProvider.snapshots()
        let displayFrame = displays.first(where: \.isMain)?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let startX = displayFrame.maxX - 520
        let y = displayFrame.minY

        let samples: [(id: String, title: String, owner: String, rule: MenuItemRule,
                       selected: Bool, system: Bool, symbol: String, appBundleID: String?)] = [
            ("preview-window", "Window Layout", "Shortcuts", .automatic, true, false, "macwindow", "com.apple.shortcuts"),
            ("preview-focus", "Focus Timer", "Clock", .alwaysVisible, false, false, "timer", "com.apple.clock"),
            ("preview-clipboard", "Clipboard", "Notes", .automatic, true, false, "doc.on.clipboard", "com.apple.Notes"),
            ("preview-vpn", "VPN", "Passwords", .alwaysHidden, true, false, "lock.shield", "com.apple.Passwords"),
            ("preview-wifi", "WiFi", "System Menu Bar", .automatic, false, true, "wifi", nil),
            ("preview-audio", "Sound", "System Menu Bar", .alwaysVisible, false, true, "speaker.wave.2", nil),
            ("preview-recording", "Screen Recording", "System Menu Bar", .alwaysVisible, false, true, "record.circle", nil)
        ]

        items = samples.enumerated().map { index, sample in
            MenuBarItem(
                id: sample.id,
                title: sample.title,
                ownerName: sample.owner,
                bundleIdentifier: sample.system ? "com.apple.controlcenter" : sample.appBundleID,
                frame: CGRect(x: startX + CGFloat(index * 42), y: y, width: 28, height: 24),
                axElement: nil,
                iconImage: NSImage(systemSymbolName: sample.symbol, accessibilityDescription: sample.title),
                applicationIcon: sample.appBundleID.flatMap(Self.previewApplicationIcon),
                isSelected: sample.selected,
                supportsPressAction: true,
                isProtectedSystemItem: sample.system,
                rule: sample.rule
            )
        }
        for item in items { item.visibility = item.isSelected ? .hidden : .visible }
        temporarilyVisibleItemIDs = ["preview-window"]
        items.first(where: { $0.id == "preview-window" })?.visibility = .visible
        layoutManagementEnabled = true
        automaticAvoidanceEnabled = true
        isReadyForManagedLayout = true
        iconCaptureMessage = language.text("store.preview.capture")
        layoutOperationMessage = nil
    }

    private static func previewApplicationIcon(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else { return nil }
        icon.isTemplate = false
        return icon
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
        guard !isApplyingLayout, !isRestoringLayout, !isTerminating else {
            lastActivationError = language.text("store.activation.busy")
            return
        }
        permissions.refresh(updateTimestamp: false)
        guard permissions.accessibilityGranted else {
            lastActivationError = language.text("store.activation.permission")
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
        activatingItemID = item.id
        lastActivationError = nil
        if platformPolicy.movement == .assessmentMode,
           assessmentHiddenItemIDs.contains(item.id) {
            activateAssessmentModeItem(
                item,
                mouseButton: mouseButton,
                restoreCursorLocation: layoutManager.currentPointerLocation(),
                retryCount: retryCount
            )
            return
        }
        if platformPolicy.movement == .maskOverlay,
           maskedItemIDs.contains(item.id) {
            activateMaskedItem(
                item,
                mouseButton: mouseButton,
                restoreCursorLocation: layoutManager.currentPointerLocation(),
                retryCount: retryCount
            )
            return
        }
        if mouseButton == .left, activator.activateDirectly(item) {
            DiagnosticLog.shared.record("activation.direct", ["route": 1])
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
                    self.retryActivation(item, mouseButton: .left, retryCount: retryCount,
                                         message: self.language.text("store.activation.failed", item.tooltip(for: self.language.selectedLanguage)))
                    return
                }
                DiagnosticLog.shared.record("activation.direct", ["route": 2])
                self.finishActivation()
            }
            return
        }
        // An AX element can go stale after a status-item rebuild. Refresh it
        // only when we already had an AX-backed item; window-backed items skip
        // this expensive full-tree walk and use the direct per-process path
        // after their short reveal.
        if mouseButton == .left, item.axElement != nil, activateUsingFreshAccessibility(item) {
            DiagnosticLog.shared.record("activation.direct", ["route": 3])
            finishActivation()
            return
        }
        if mouseButton == .left,
           item.windowID == nil,
           activator.activateViaAccessibilityHitTest(item) {
            DiagnosticLog.shared.record("activation.direct", ["route": 4])
            finishActivation()
            return
        }
        if mouseButton == .right, layoutManager.isVisible(item) {
            let pointer = layoutManager.currentPointerLocation()
            activator.activateRightClick(item) { [weak self] success in
                guard let self else { return }
                self.layoutManager.restorePointerLocation(pointer)
                guard success else {
                    self.retryActivation(item, mouseButton: mouseButton, retryCount: retryCount,
                                         message: self.language.text("store.activation.context_failed", item.tooltip(for: self.language.selectedLanguage)))
                    return
                }
                DiagnosticLog.shared.record("activation.direct", ["route": 5])
                self.finishActivation()
            }
            return
        }
        // Preserve the real pointer across the reveal and click. The item is
        // intentionally left visible until the user explicitly retucks it.
        activateByTemporarilyRevealing(item, mouseButton: mouseButton, restoreCursorLocation: layoutManager.currentPointerLocation(), retryCount: retryCount)
    }

    private func activateUsingFreshAccessibility(_ item: MenuBarItem) -> Bool {
        guard let fresh = scanner.refreshAccessibility(for: item), fresh.supportsPress else { return false }
        item.axElement = fresh.element
        item.supportsPressAction = true
        return activator.activateDirectly(item)
    }

    private func activateAssessmentModeItem(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        restoreCursorLocation: CGPoint?,
        retryCount: Int
    ) {
        let groupIDs = MenuBarAssessmentModePolicy.groupItemIDs(
            items: assessmentItems,
            itemID: item.id
        )
        temporarilyVisibleItemIDs.formUnion(groupIDs)
        layoutOperationMessage = language.text("store.activation.reveal_once")
        let plan = assessmentPlan()
        applyAssessmentPlan(
            plan,
            automatic: false,
            reportsOperation: false,
            allowsActiveActivation: true
        ) { [weak self] success in
            guard let self, self.activatingItemID == item.id else { return }
            guard success else {
                self.temporarilyVisibleItemIDs.subtract(groupIDs)
                self.lastActivationError = self.language.text(
                    "store.activation.reveal_failed",
                    item.tooltip(for: self.language.selectedLanguage)
                )
                self.finishActivation()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.performAssessmentModeActivation(
                    item,
                    mouseButton: mouseButton,
                    restoreCursorLocation: restoreCursorLocation,
                    retryCount: retryCount
                )
            }
        }
    }

    private func performAssessmentModeActivation(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        restoreCursorLocation: CGPoint?,
        retryCount: Int
    ) {
        guard activatingItemID == item.id, !isTerminating else { return }
        if mouseButton == .left {
            // Assessment Mode can rebuild the status item while revealing its
            // host application. A stale AX element may still return success
            // for AXPress without opening a menu, so never treat the element
            // captured before the reveal as proof of activation.
            if activateUsingFreshAccessibility(item) {
                DiagnosticLog.shared.record("assessment.activation_complete", [
                    "button": 1,
                    "route": 1
                ])
                finishActivation()
                return
            }
            guard item.windowID != nil else {
                retryActivation(
                    item,
                    mouseButton: mouseButton,
                    retryCount: retryCount,
                    message: language.text(
                        "store.activation.failed",
                        item.tooltip(for: language.selectedLanguage)
                    )
                )
                return
            }
            activator.activateMovedItem(item, mouseButton: .left) { [weak self] success in
                guard let self else { return }
                self.layoutManager.restorePointerLocation(restoreCursorLocation)
                guard success else {
                    self.retryActivation(
                        item,
                        mouseButton: mouseButton,
                        retryCount: retryCount,
                        message: self.language.text(
                            "store.activation.failed",
                            item.tooltip(for: self.language.selectedLanguage)
                        )
                    )
                    return
                }
                DiagnosticLog.shared.record("assessment.activation_complete", [
                    "button": 1,
                    "route": 2
                ])
                self.finishActivation()
            }
            return
        }

        activator.activateRightClick(item) { [weak self] success in
            guard let self else { return }
            self.layoutManager.restorePointerLocation(restoreCursorLocation)
            guard success else {
                self.retryActivation(
                    item,
                    mouseButton: mouseButton,
                    retryCount: retryCount,
                    message: self.language.text(
                        "store.activation.context_failed",
                        item.tooltip(for: self.language.selectedLanguage)
                    )
                )
                return
            }
            DiagnosticLog.shared.record("assessment.activation_complete", ["button": 2])
            self.finishActivation()
        }
    }

    private func activateByTemporarilyRevealing(_ item: MenuBarItem, mouseButton: CGMouseButton, restoreCursorLocation: CGPoint?, retryCount: Int) {
        revealTemporarily(
            item,
            mouseButton: mouseButton,
            restoreCursorLocation: restoreCursorLocation,
            retryCount: retryCount
        )
    }

    private func activateMaskedItem(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        restoreCursorLocation: CGPoint?,
        retryCount: Int
    ) {
        if mouseButton == .left {
            if activator.activateDirectly(item) {
                DiagnosticLog.shared.record("mask.activation_direct", ["route": 1])
                finishActivation()
                return
            }
            if activateUsingFreshAccessibility(item) {
                DiagnosticLog.shared.record("mask.activation_direct", ["route": 2])
                finishActivation()
                return
            }
        }

        layoutOperationMessage = language.text("store.activation.reveal_once")
        let requestedID = item.id
        maskingController.setRevealed(true, itemID: requestedID)
        DiagnosticLog.shared.record("mask.activation_reveal", [
            "button": mouseButton == .right ? 2 : 1
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self, self.activatingItemID == requestedID, !self.isTerminating else {
                self?.maskingController.setRevealed(false, itemID: requestedID)
                return
            }

            if mouseButton == .left {
                if self.activator.activateDirectly(item)
                    || self.activateUsingFreshAccessibility(item)
                    || (item.windowID == nil && self.activator.activateViaAccessibilityHitTest(item)) {
                    self.finishMaskedActivation(
                        item,
                        mouseButton: mouseButton,
                        restoreCursorLocation: restoreCursorLocation,
                        retryCount: retryCount,
                        success: true
                    )
                    return
                }
                guard item.windowID != nil else {
                    self.finishMaskedActivation(
                        item,
                        mouseButton: mouseButton,
                        restoreCursorLocation: restoreCursorLocation,
                        retryCount: retryCount,
                        success: false
                    )
                    return
                }
                self.activator.activateMovedItem(item, mouseButton: .left) { [weak self] success in
                    self?.finishMaskedActivation(
                        item,
                        mouseButton: mouseButton,
                        restoreCursorLocation: restoreCursorLocation,
                        retryCount: retryCount,
                        success: success
                    )
                }
                return
            }

            self.activator.activateRightClick(item) { [weak self] success in
                self?.finishMaskedActivation(
                    item,
                    mouseButton: mouseButton,
                    restoreCursorLocation: restoreCursorLocation,
                    retryCount: retryCount,
                    success: success
                )
            }
        }
    }

    private func finishMaskedActivation(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        restoreCursorLocation: CGPoint?,
        retryCount: Int,
        success: Bool
    ) {
        let requestedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.maskingController.setRevealed(false, itemID: requestedID)
            self.layoutManager.restorePointerLocation(restoreCursorLocation)
            guard self.activatingItemID == requestedID else { return }
            guard success else {
                let key = mouseButton == .right
                    ? "store.activation.context_failed"
                    : "store.activation.failed"
                self.retryActivation(
                    item,
                    mouseButton: mouseButton,
                    retryCount: retryCount,
                    message: self.language.text(
                        key,
                        item.tooltip(for: self.language.selectedLanguage)
                    )
                )
                return
            }
            DiagnosticLog.shared.record("mask.activation_complete", [
                "button": mouseButton == .right ? 2 : 1
            ])
            self.finishActivation()
        }
    }

    private func revealTemporarily(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        restoreCursorLocation: CGPoint?,
        retryCount: Int
    ) {
        layoutManager.reveal(item, restoreCursorLocation: restoreCursorLocation) { [weak self] moved in
            guard let self else { return }
            self.onLayoutOperationStateChanged?(false)
            self.finishTemporaryReveal(
                item,
                mouseButton: mouseButton,
                restoreCursorLocation: restoreCursorLocation,
                retryCount: retryCount,
                moved: moved
            )
        }
    }

    private func finishTemporaryReveal(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        restoreCursorLocation: CGPoint?,
        retryCount: Int,
        moved: Bool
    ) {
        guard moved else {
            retryActivation(item, mouseButton: mouseButton, retryCount: retryCount,
                            message: language.text("store.activation.reveal_failed", item.tooltip(for: language.selectedLanguage)))
            return
        }
        preserveRevealedItem(item)
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
                DiagnosticLog.shared.record("activation.temporary_activated", ["route": 1])
                self.finishActivation()
                return
            }
            self.activator.activateMovedItem(item, mouseButton: mouseButton) { [weak self] success in
                guard let self else { return }
                self.layoutManager.restorePointerLocation(restoreCursorLocation)
                guard success else {
                    DiagnosticLog.shared.record("activation.click_failed_visible", ["route": mouseButton == .right ? 2 : 1])
                    self.retryActivation(item, mouseButton: mouseButton, retryCount: retryCount,
                                         message: self.language.text("store.activation.failed", item.tooltip(for: self.language.selectedLanguage)))
                    return
                }
                DiagnosticLog.shared.record("activation.temporary_activated", ["route": mouseButton == .right ? 2 : 1])
                self.finishActivation()
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

    private func preserveRevealedItem(_ item: MenuBarItem) {
        let presentation = MenuBarInteractionPolicy.activationPresentation(
            didRevealItem: true,
            isManaged: item.isSelected,
            layoutEnabled: layoutManagementEnabled
        )
        guard presentation == .keepVisibleUntilRetucked else { return }
        if platformPolicy.movement == .assessmentMode {
            temporarilyVisibleItemIDs.formUnion(
                MenuBarAssessmentModePolicy.groupItemIDs(
                    items: assessmentItems,
                    itemID: item.id
                )
            )
        }
        if platformPolicy.movement == .nativeOverflow {
            nativeOverflowItemIDs.remove(item.id)
        }
        if platformPolicy.movement != .assessmentMode {
            temporarilyVisibleItemIDs.insert(item.id)
        }
        for revealedItem in items where temporarilyVisibleItemIDs.contains(revealedItem.id) {
            revealedItem.visibility = .visible
        }
        DiagnosticLog.shared.record("activation.reveal_once", ["temporary": temporarilyVisibleItemIDs.count])
        objectWillChange.send()
    }

    private func itemUsesAccessibility(_ item: MenuBarItem) -> Bool {
        item.windowID == nil
    }

}

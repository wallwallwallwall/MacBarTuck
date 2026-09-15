import AppKit

@MainActor
private final class RefreshMaskWindow: MenuBarMaskWindow {
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

private final class RefreshItemActivator: MenuBarItemActivating {
    var directResult = false
    private(set) var directActivationCount = 0
    private(set) var hitTestActivationCount = 0
    private(set) var movedActivationCount = 0
    private(set) var rightClickActivationCount = 0

    func activateDirectly(_ item: MenuBarItem) -> Bool {
        directActivationCount += 1
        return directResult
    }

    func activateViaAccessibilityHitTest(_ item: MenuBarItem) -> Bool {
        hitTestActivationCount += 1
        return false
    }

    func activateMovedItem(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        completion: @escaping (Bool) -> Void
    ) {
        movedActivationCount += 1
        completion(false)
    }

    func activateRightClick(_ item: MenuBarItem, completion: @escaping (Bool) -> Void) {
        rightClickActivationCount += 1
        completion(false)
    }
}

@main
@MainActor
enum RefreshIsolationTests {
    static func main() async throws {
        _ = NSApplication.shared
        try await maskOverlayStoreLifecycle()
        try await directMaskedActivationKeepsNativeSlotCovered()
        try await revokedScreenRecordingRemovesMasks()
        try await failedMaskDoesNotReturnAfterDisable()
        let domain = "RefreshIsolationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasCompletedOnboarding = true
        preferences.layoutManagementEnabled = true
        let language = AppLanguageController(defaults: defaults, preferredLanguages: ["zh-Hans"],
                                             arguments: [], rootBundle: .main)
        let permissions = PermissionManager(accessibilityStatus: { true }, accessibilityRequest: {},
            screenCaptureStatus: { true }, screenCaptureRequest: { true }, openSettings: { _ in }, history: nil,
            language: language)
        let windows: [[String: Any]] = [[kCGWindowLayer as String: 25,
            kCGWindowNumber as String: 4000000000, kCGWindowOwnerPID as String: -1,
            kCGWindowOwnerName as String: "Fixture", kCGWindowName as String: "utility",
            kCGWindowBounds as String: ["X": 1000, "Y": 0, "Width": 30, "Height": 30]]]
        let scanner = MenuBarScanner(readWindows: { windows },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1512, height: 982)] },
            ownBundleIdentifier: "test.host",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26))
        let noOpDomain = "RefreshIsolationNoOpTests.\(UUID().uuidString)"
        let noOpDefaults = UserDefaults(suiteName: noOpDomain)!
        defer { noOpDefaults.removePersistentDomain(forName: noOpDomain) }
        let noOpPreferences = PreferencesStore(defaults: noOpDefaults)
        noOpPreferences.hasCompletedOnboarding = true
        noOpPreferences.layoutManagementEnabled = true
        noOpPreferences.saveRule(.alwaysHidden, for: scanner.scan(selectedIDs: []).first!.id)
        var noOpHideCalls = 0
        var noOpOperationStates: [Bool] = []
        let noOpStore = MenuBarItemStore(permissions: permissions, preferences: noOpPreferences, language: language,
            scanner: scanner,
            captureOverride: { items in Dictionary(uniqueKeysWithValues: items.map {
                ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
            }) },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26),
            visibilityOverride: { _ in .hidden },
            hideOverride: { _, _, complete in
                noOpHideCalls += 1
                complete(0)
            })
        noOpStore.onLayoutOperationStateChanged = { noOpOperationStates.append($0) }
        noOpStore.refresh()
        try await Task.sleep(for: .milliseconds(500))
        guard noOpStore.selectedItems.count == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 13,
                userInfo: [NSLocalizedDescriptionKey: "The no-op fixture did not stage its hidden item."])
        }
        noOpStore.applyLayout()
        try await Task.sleep(for: .milliseconds(850))
        guard noOpOperationStates.isEmpty else {
            throw NSError(domain: "RefreshIsolation", code: 14,
                userInfo: [NSLocalizedDescriptionKey: "An already-correct layout resized the hidden section."])
        }
        guard noOpHideCalls == 0 else {
            throw NSError(domain: "RefreshIsolation", code: 15,
                userInfo: [NSLocalizedDescriptionKey: "An already-hidden item was moved again."])
        }
        guard noOpStore.layoutOperationMessage == language.text("store.layout.correct") else {
            throw NSError(domain: "RefreshIsolation", code: 16,
                userInfo: [NSLocalizedDescriptionKey: "The no-op layout did not report that it was already correct."])
        }

        let unknownDomain = "RefreshIsolationUnknownTests.\(UUID().uuidString)"
        let unknownDefaults = UserDefaults(suiteName: unknownDomain)!
        defer { unknownDefaults.removePersistentDomain(forName: unknownDomain) }
        let unknownPreferences = PreferencesStore(defaults: unknownDefaults)
        unknownPreferences.hasCompletedOnboarding = true
        unknownPreferences.layoutManagementEnabled = true
        unknownPreferences.saveRule(.alwaysHidden, for: scanner.scan(selectedIDs: []).first!.id)
        var unknownHideCalls = 0
        var unknownOperationStates: [Bool] = []
        let unknownStore = MenuBarItemStore(
            permissions: permissions,
            preferences: unknownPreferences,
            language: language,
            scanner: scanner,
            captureOverride: { items in Dictionary(uniqueKeysWithValues: items.map {
                ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
            }) },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26),
            visibilityOverride: { _ in .unknown },
            hideOverride: { _, _, complete in
                unknownHideCalls += 1
                complete(0)
            }
        )
        unknownStore.onLayoutOperationStateChanged = { unknownOperationStates.append($0) }
        unknownStore.refresh()
        try await Task.sleep(for: .milliseconds(500))
        unknownStore.applyLayout()
        guard await waitUntil({ unknownHideCalls == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 19,
                userInfo: [NSLocalizedDescriptionKey: "An unknown live position was incorrectly treated as already hidden."])
        }
        guard unknownOperationStates.first == true,
              unknownStore.layoutOperationMessage != language.text("store.layout.correct") else {
            throw NSError(domain: "RefreshIsolation", code: 20,
                userInfo: [NSLocalizedDescriptionKey: "An unverified layout reported success without attempting a move."])
        }

        let pendingRestoreDomain = "RefreshIsolationPendingRestoreTests.\(UUID().uuidString)"
        let pendingRestoreDefaults = UserDefaults(suiteName: pendingRestoreDomain)!
        defer { pendingRestoreDefaults.removePersistentDomain(forName: pendingRestoreDomain) }
        let pendingRestoreWindows: [[String: Any]] = [
            [kCGWindowLayer as String: 25,
             kCGWindowNumber as String: 3_900_000_001,
             kCGWindowOwnerPID as String: -1,
             kCGWindowOwnerName as String: "Fixture",
             kCGWindowName as String: "utility-one",
             kCGWindowBounds as String: ["X": 970, "Y": 0, "Width": 30, "Height": 30]],
            [kCGWindowLayer as String: 25,
             kCGWindowNumber as String: 3_900_000_002,
             kCGWindowOwnerPID as String: -1,
             kCGWindowOwnerName as String: "Fixture",
             kCGWindowName as String: "utility-two",
             kCGWindowBounds as String: ["X": 1_010, "Y": 0, "Width": 30, "Height": 30]]
        ]
        let pendingRestoreScanner = MenuBarScanner(
            readWindows: { pendingRestoreWindows },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1512, height: 982)] },
            ownBundleIdentifier: "test.host",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let pendingRestoreItems = pendingRestoreScanner.scan(selectedIDs: [])
        for item in pendingRestoreItems {
            pendingRestoreDefaults.set(
                MenuItemRule.alwaysHidden.rawValue,
                forKey: "unused-\(item.id)"
            )
        }
        let pendingRestorePreferences = PreferencesStore(defaults: pendingRestoreDefaults)
        pendingRestorePreferences.hasCompletedOnboarding = true
        pendingRestorePreferences.layoutManagementEnabled = true
        for item in pendingRestoreItems {
            pendingRestorePreferences.saveRule(.alwaysHidden, for: item.id)
        }
        let pendingRestoreStore = MenuBarItemStore(
            permissions: permissions,
            preferences: pendingRestorePreferences,
            language: language,
            scanner: pendingRestoreScanner,
            captureOverride: { items in Dictionary(uniqueKeysWithValues: items.map {
                ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
            }) },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26),
            visibilityOverride: { _ in .visible }
        )
        var pendingRestoreOperationStates = [Bool]()
        pendingRestoreStore.onLayoutOperationStateChanged = {
            pendingRestoreOperationStates.append($0)
        }
        pendingRestoreStore.refresh()
        try await Task.sleep(for: .milliseconds(500))
        guard pendingRestoreStore.selectedItems.count == 2 else {
            throw NSError(domain: "RefreshIsolation", code: 21,
                userInfo: [NSLocalizedDescriptionKey: "The pending-restore fixture did not stage both items."])
        }
        pendingRestoreStore.updateControlItemFrame(CGRect(x: 1_100, y: 950, width: 24, height: 24))
        pendingRestoreStore.setRule(.alwaysVisible, for: pendingRestoreStore.items[0])
        try await Task.sleep(for: .milliseconds(900))
        guard pendingRestoreStore.selectedItems.count == 1,
              !pendingRestoreStore.isHiddenSectionActive,
              !pendingRestoreOperationStates.contains(true) else {
            throw NSError(domain: "RefreshIsolation", code: 22,
                userInfo: [NSLocalizedDescriptionKey:
                    "Restoring an unapplied rule started a layout transaction or activated the hidden section."])
        }

        preferences.saveRule(.alwaysVisible, for: scanner.scan(selectedIDs: []).first!.id)
        var hideCompletions: [(Int) -> Void] = []
        let store = MenuBarItemStore(permissions: permissions, preferences: preferences, language: language, scanner: scanner,
            captureOverride: { items in Dictionary(uniqueKeysWithValues: items.map { ($0.id, NSImage(size: NSSize(width: 24, height: 24))) }) },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26),
            visibilityOverride: { _ in .visible }, hideOverride: { _, _, complete in hideCompletions.append(complete) })
        var operations = 0
        store.onLayoutOperationStateChanged = { if $0 { operations += 1 } }
        store.refresh()
        try await Task.sleep(for: .milliseconds(500))
        guard operations == 0 else { throw NSError(domain: "RefreshIsolation", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "A list refresh started a layout transaction."]) }
        guard store.items.count == 1, store.selectedItems.isEmpty else {
            throw NSError(domain: "RefreshIsolation", code: 2)
        }
        let originalItem = store.items[0]
        var repeatedLayoutNotifications = 0
        var repeatedImageNotifications = 0
        store.onLayoutStateChanged = { repeatedLayoutNotifications += 1 }
        store.onImagesReady = { repeatedImageNotifications += 1 }
        store.refresh()
        try await Task.sleep(for: .milliseconds(500))
        guard store.items[0] === originalItem else {
            throw NSError(domain: "RefreshIsolation", code: 17,
                userInfo: [NSLocalizedDescriptionKey: "An unchanged scan replaced the menu item object."])
        }
        guard repeatedLayoutNotifications == 0, repeatedImageNotifications == 0 else {
            throw NSError(domain: "RefreshIsolation", code: 18,
                userInfo: [NSLocalizedDescriptionKey: "An unchanged scan republished layout or image state."])
        }
        store.onLayoutStateChanged = nil
        store.onImagesReady = nil
        store.setRule(.alwaysHidden, for: store.items[0])
        store.refresh()
        try await Task.sleep(for: .milliseconds(600))
        guard store.selectedItems.count == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "A changed hide rule was not staged."])
        }
        guard operations == 0 && hideCompletions.isEmpty else {
            throw NSError(domain: "RefreshIsolation", code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Changing a hide rule started a layout before Apply was pressed."])
        }
        guard store.overflowItems.isEmpty else { throw NSError(domain: "RefreshIsolation", code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Visible items were advertised in the hidden tray before any move."]) }
        for _ in 0..<12 { store.refresh() }
        try await Task.sleep(for: .milliseconds(500))
        guard operations == 0 else { throw NSError(domain: "RefreshIsolation", code: 3) }
        store.applyLayout()
        guard await waitUntil({ operations == 1 && hideCompletions.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 4)
        }
        for _ in 0..<20 { store.refresh(source: .externalChange) }
        guard store.items.count == 1, operations == 1 else { throw NSError(domain: "RefreshIsolation", code: 5) }
        hideCompletions[0](0)
        try await Task.sleep(for: .milliseconds(1600))
        guard hideCompletions.count == 1, store.layoutOperationMessage?.contains("停止自动重试") == true else {
            throw NSError(domain: "RefreshIsolation", code: 6)
        }
        for _ in 0..<12 { store.refresh() }
        try await Task.sleep(for: .milliseconds(500))
        guard operations == 1, !store.isHiddenSectionActive else { throw NSError(domain: "RefreshIsolation", code: 7) }
        store.applyLayout()
        guard await waitUntil({ hideCompletions.count == 2 }) else {
            throw NSError(domain: "RefreshIsolation", code: 8)
        }
        store.setLayoutManagementEnabled(false)
        hideCompletions[1](1)
        try await Task.sleep(for: .milliseconds(1200))
        guard !store.layoutManagementEnabled, !store.isHiddenSectionActive else { throw NSError(domain: "RefreshIsolation", code: 9) }
        print("RefreshIsolationTests: refresh isolation and mask overlay lifecycle passed")
    }

    private static func directMaskedActivationKeepsNativeSlotCovered() async throws {
        let domain = "DirectMaskedActivationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasCompletedOnboarding = true
        preferences.layoutManagementEnabled = true
        let language = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["en"],
            arguments: [],
            rootBundle: .main
        )
        let permissions = PermissionManager(
            accessibilityStatus: { true },
            accessibilityRequest: {},
            screenCaptureStatus: { true },
            screenCaptureRequest: { true },
            openSettings: { _ in },
            history: nil,
            language: language
        )
        let utilityWindow: [String: Any] = [
            kCGWindowLayer as String: 25,
            kCGWindowNumber as String: 3_600_000_001,
            kCGWindowOwnerPID as String: -1,
            kCGWindowOwnerName as String: "Fixture",
            kCGWindowName as String: "com.example.direct",
            kCGWindowBounds as String: [
                "X": 1_000, "Y": 0, "Width": 30, "Height": 30
            ]
        ]
        let scanner = MenuBarScanner(
            readWindows: { [utilityWindow] },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1_512, height: 982)] },
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let seed = scanner.scan(selectedIDs: []).first!
        preferences.saveRule(.alwaysHidden, for: seed.id)
        let display = MenuBarMaskDisplay(
            id: 1,
            quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            menuBarHeight: 25
        )
        var maskWindows = [RefreshMaskWindow]()
        let maskingController = MenuBarMaskingController(
            displayProvider: { [display] },
            windowFactory: { placement in
                let window = RefreshMaskWindow(frame: placement.frame)
                maskWindows.append(window)
                return window
            }
        )
        let activator = RefreshItemActivator()
        activator.directResult = true
        let store = MenuBarItemStore(
            permissions: permissions,
            preferences: preferences,
            language: language,
            scanner: scanner,
            captureOverride: { items in
                Dictionary(uniqueKeysWithValues: items.map {
                    ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
                })
            },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 27),
            maskingController: maskingController,
            activator: activator
        )

        store.refresh()
        guard await waitUntil({ store.selectedItems.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 63,
                userInfo: [NSLocalizedDescriptionKey:
                    "The direct activation fixture did not discover its selected item."])
        }
        store.applyLayout()
        guard await waitUntil({ store.hasActiveMaskOverlay && maskWindows.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 64,
                userInfo: [NSLocalizedDescriptionKey:
                    "The direct activation fixture did not install its mask."])
        }

        store.activate(store.items[0])
        try await Task.sleep(for: .milliseconds(180))
        guard activator.directActivationCount == 1,
              activator.hitTestActivationCount == 0,
              activator.movedActivationCount == 0,
              maskWindows[0].isMaskVisible,
              maskWindows[0].hideCount == 0,
              maskWindows[0].showCount == 1,
              store.activatingItemID == nil else {
            throw NSError(domain: "RefreshIsolation", code: 65,
                userInfo: [NSLocalizedDescriptionKey:
                    "A successful direct AXPress briefly exposed the native menu-bar icon."])
        }
    }

    private static func revokedScreenRecordingRemovesMasks() async throws {
        let domain = "RevokedScreenRecordingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasCompletedOnboarding = true
        preferences.layoutManagementEnabled = true
        let language = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["en"],
            arguments: [],
            rootBundle: .main
        )
        var screenRecordingGranted = true
        let permissions = PermissionManager(
            accessibilityStatus: { true },
            accessibilityRequest: {},
            screenCaptureStatus: { screenRecordingGranted },
            screenCaptureRequest: { true },
            openSettings: { _ in },
            history: nil,
            language: language
        )
        let utilityWindow: [String: Any] = [
            kCGWindowLayer as String: 25,
            kCGWindowNumber as String: 3_500_000_001,
            kCGWindowOwnerPID as String: -1,
            kCGWindowOwnerName as String: "Fixture",
            kCGWindowName as String: "com.example.permission",
            kCGWindowBounds as String: [
                "X": 1_000, "Y": 0, "Width": 30, "Height": 30
            ]
        ]
        let scanner = MenuBarScanner(
            readWindows: { [utilityWindow] },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1_512, height: 982)] },
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let seed = scanner.scan(selectedIDs: []).first!
        preferences.saveRule(.alwaysHidden, for: seed.id)
        let display = MenuBarMaskDisplay(
            id: 1,
            quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            menuBarHeight: 25
        )
        var maskWindows = [RefreshMaskWindow]()
        let maskingController = MenuBarMaskingController(
            displayProvider: { [display] },
            windowFactory: { placement in
                let window = RefreshMaskWindow(frame: placement.frame)
                maskWindows.append(window)
                return window
            }
        )
        let store = MenuBarItemStore(
            permissions: permissions,
            preferences: preferences,
            language: language,
            scanner: scanner,
            captureOverride: { items in
                Dictionary(uniqueKeysWithValues: items.map {
                    ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
                })
            },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 27),
            maskingController: maskingController
        )

        store.refresh()
        guard await waitUntil({ store.selectedItems.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 66,
                userInfo: [NSLocalizedDescriptionKey:
                    "The permission fixture did not discover its selected item."])
        }
        store.applyLayout()
        guard await waitUntil({ store.hasActiveMaskOverlay && maskWindows.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 67,
                userInfo: [NSLocalizedDescriptionKey:
                    "The permission fixture did not install its mask."])
        }

        screenRecordingGranted = false
        store.refresh(source: .externalChange)
        guard store.requiresScreenRecording,
              store.items.isEmpty,
              !store.hasActiveMaskOverlay,
              store.maskedItemIDs.isEmpty,
              maskingController.maskedItemIDs.isEmpty,
              maskWindows[0].closeCount == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 68,
                userInfo: [NSLocalizedDescriptionKey:
                    "Revoking screen recording left a stale mask over the system menu bar."])
        }
    }

    private static func maskOverlayStoreLifecycle() async throws {
        let domain = "MaskOverlayStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasCompletedOnboarding = true
        preferences.layoutManagementEnabled = true
        let language = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["zh-Hans"],
            arguments: [],
            rootBundle: .main
        )
        let permissions = PermissionManager(
            accessibilityStatus: { true },
            accessibilityRequest: {},
            screenCaptureStatus: { true },
            screenCaptureRequest: { true },
            openSettings: { _ in },
            history: nil,
            language: language
        )
        func utilityWindow(x: Int) -> [String: Any] {
            [
                kCGWindowLayer as String: 25,
                kCGWindowNumber as String: 3_800_000_001,
                kCGWindowOwnerPID as String: -1,
                kCGWindowOwnerName as String: "Fixture",
                kCGWindowName as String: "com.example.utility",
                kCGWindowBounds as String: [
                    "X": x, "Y": 0, "Width": 30, "Height": 30
                ]
            ]
        }
        var windows = [utilityWindow(x: 1_000)]
        let scanner = MenuBarScanner(
            readWindows: { windows },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1_512, height: 982)] },
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let seed = scanner.scan(selectedIDs: []).first!
        preferences.saveRule(.alwaysHidden, for: seed.id)
        let display = MenuBarMaskDisplay(
            id: 1,
            quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            menuBarHeight: 25
        )
        var maskWindows = [RefreshMaskWindow]()
        var liveMaskFrame = CGRect(x: 1_000, y: 0, width: 30, height: 30)
        let maskingController = MenuBarMaskingController(
            displayProvider: { [display] },
            representationFrameProvider: { _ in liveMaskFrame },
            windowFactory: { placement in
                let window = RefreshMaskWindow(frame: placement.frame)
                maskWindows.append(window)
                return window
            }
        )
        let store = MenuBarItemStore(
            permissions: permissions,
            preferences: preferences,
            language: language,
            scanner: scanner,
            captureOverride: { items in
                Dictionary(uniqueKeysWithValues: items.map {
                    ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
                })
            },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 27),
            maskingController: maskingController
        )

        store.refresh()
        guard await waitUntil({ store.isReadyForManagedLayout && store.selectedItems.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 40,
                userInfo: [NSLocalizedDescriptionKey:
                    "The mask overlay fixture did not discover its selected item."])
        }
        guard store.maskedItemIDs.isEmpty,
              maskingController.maskedItemIDs.isEmpty,
              store.overflowItems.isEmpty else {
            throw NSError(domain: "RefreshIsolation", code: 41,
                userInfo: [NSLocalizedDescriptionKey:
                    "A saved hide rule was reported as applied before Apply was pressed."])
        }

        store.applyLayout()
        guard await waitUntil({
            store.hasActiveMaskOverlay && store.maskedItemIDs == [seed.id] &&
                maskingController.maskedItemIDs == [seed.id] &&
                store.items.first?.visibility == .hidden
        }) else {
            throw NSError(domain: "RefreshIsolation", code: 42,
                userInfo: [NSLocalizedDescriptionKey:
                    "A confirmed mask layout did not report the item as hidden."])
        }
        guard maskWindows.count == 1,
              maskWindows[0].isMaskVisible,
              maskWindows[0].showCount == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 43,
                userInfo: [NSLocalizedDescriptionKey:
                    "The store reported a hidden item before its mask window became visible."])
        }

        var geometryCallbacks = 0
        store.onLayoutStateChanged = { geometryCallbacks += 1 }
        liveMaskFrame = liveMaskFrame.offsetBy(dx: 18, dy: 0)
        store.reconcileLiveMaskGeometry()
        guard maskWindows.count == 1,
              maskWindows[0].setFrameCount == 1,
              geometryCallbacks == 0 else {
            throw NSError(domain: "RefreshIsolation", code: 55,
                userInfo: [NSLocalizedDescriptionKey:
                    "Live AX geometry did not update the existing mask without publishing the item list."])
        }

        store.activate(store.items[0])
        guard !maskWindows[0].isMaskVisible,
              maskWindows[0].hideCount == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 53,
                userInfo: [NSLocalizedDescriptionKey:
                    "Activating a tucked tray item did not reveal the native menu-bar slot first."])
        }
        guard await waitUntil({
            store.lastActivationError != nil && maskWindows[0].isMaskVisible
        }), maskWindows[0].hideCount == 2,
           maskWindows[0].showCount == 3,
           maskWindows.count == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 54,
                userInfo: [NSLocalizedDescriptionKey:
                    "A failed native tray click did not restore the same mask after its bounded retry."])
        }
        store.lastActivationError = nil

        let setFrameCountBeforeUnchangedRefresh = maskWindows[0].setFrameCount
        let showCountBeforeUnchangedRefresh = maskWindows[0].showCount

        store.refresh(source: .externalChange)
        try await Task.sleep(for: .milliseconds(500))
        guard maskWindows.count == 1,
              maskWindows[0].setFrameCount == setFrameCountBeforeUnchangedRefresh,
              maskWindows[0].showCount == showCountBeforeUnchangedRefresh else {
            throw NSError(domain: "RefreshIsolation", code: 44,
                userInfo: [NSLocalizedDescriptionKey:
                    "An unchanged refresh rebuilt or republished the active mask."])
        }

        liveMaskFrame = CGRect(x: 980, y: 0, width: 30, height: 30)
        windows = [utilityWindow(x: 980)]
        store.refresh(source: .externalChange)
        guard await waitUntil({ maskWindows[0].setFrameCount == 2 }) else {
            throw NSError(domain: "RefreshIsolation", code: 45,
                userInfo: [NSLocalizedDescriptionKey:
                    "A moved menu-bar item did not update its existing mask in place."])
        }

        let visibleRuleItem = store.items.first(where: { $0.id == seed.id })!
        store.setRule(.alwaysVisible, for: visibleRuleItem)
        guard await waitUntil({
            !store.hasActiveMaskOverlay && store.maskedItemIDs.isEmpty &&
                maskingController.maskedItemIDs.isEmpty && maskWindows[0].closeCount == 1
        }) else {
            throw NSError(domain: "RefreshIsolation", code: 46,
                userInfo: [NSLocalizedDescriptionKey:
                    "Making a masked item visible did not remove its mask."])
        }

        store.setRule(.alwaysHidden, for: visibleRuleItem)
        store.refresh()
        try await Task.sleep(for: .milliseconds(400))
        guard store.maskedItemIDs.isEmpty, maskingController.maskedItemIDs.isEmpty else {
            throw NSError(domain: "RefreshIsolation", code: 47,
                userInfo: [NSLocalizedDescriptionKey:
                    "Refreshing a pending hide rule applied it without user confirmation."])
        }
        store.applyLayout()
        guard await waitUntil({ store.hasActiveMaskOverlay && maskWindows.count == 2 }) else {
            throw NSError(domain: "RefreshIsolation", code: 48,
                userInfo: [NSLocalizedDescriptionKey:
                    "The second explicit mask transaction did not become active."])
        }

        windows = []
        store.refresh(source: .externalChange)
        guard await waitUntil({
            store.items.isEmpty && !store.hasActiveMaskOverlay &&
                maskWindows[1].closeCount == 1
        }) else {
            throw NSError(domain: "RefreshIsolation", code: 49,
                userInfo: [NSLocalizedDescriptionKey:
                    "A vanished menu-bar item retained a stale mask or tray entry."])
        }

        windows = [utilityWindow(x: 1_000)]
        store.refresh(source: .externalChange)
        guard await waitUntil({ store.selectedItems.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 50,
                userInfo: [NSLocalizedDescriptionKey:
                    "The mask fixture did not rediscover the returned item."])
        }
        store.applyLayout()
        guard await waitUntil({ store.hasActiveMaskOverlay && maskWindows.count == 3 }) else {
            throw NSError(domain: "RefreshIsolation", code: 51,
                userInfo: [NSLocalizedDescriptionKey:
                    "The returned item could not be masked again."])
        }

        await withCheckedContinuation { continuation in
            store.prepareForTermination { continuation.resume() }
        }
        guard !store.hasActiveMaskOverlay,
              store.maskedItemIDs.isEmpty,
              maskingController.maskedItemIDs.isEmpty,
              maskWindows[2].closeCount == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 52,
                userInfo: [NSLocalizedDescriptionKey:
                    "Termination did not synchronously remove the active mask."])
        }
    }

    private static func failedMaskDoesNotReturnAfterDisable() async throws {
        let domain = "DisabledMaskRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        preferences.hasCompletedOnboarding = true
        preferences.layoutManagementEnabled = true
        let language = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["en"],
            arguments: [],
            rootBundle: .main
        )
        let permissions = PermissionManager(
            accessibilityStatus: { true },
            accessibilityRequest: {},
            screenCaptureStatus: { true },
            screenCaptureRequest: { true },
            openSettings: { _ in },
            history: nil,
            language: language
        )
        let utilityWindow: [String: Any] = [
            kCGWindowLayer as String: 25,
            kCGWindowNumber as String: 3_700_000_001,
            kCGWindowOwnerPID as String: -1,
            kCGWindowOwnerName as String: "Fixture",
            kCGWindowName as String: "com.example.retry",
            kCGWindowBounds as String: [
                "X": 1_000, "Y": 0, "Width": 30, "Height": 30
            ]
        ]
        var windows = [utilityWindow]
        let scanner = MenuBarScanner(
            readWindows: { windows },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1_512, height: 982)] },
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let seed = scanner.scan(selectedIDs: []).first!
        preferences.saveRule(.alwaysHidden, for: seed.id)
        let display = MenuBarMaskDisplay(
            id: 1,
            quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            menuBarHeight: 25
        )
        var liveFrame = CGRect(x: 100, y: 200, width: 30, height: 30)
        var maskWindows = [RefreshMaskWindow]()
        let maskingController = MenuBarMaskingController(
            displayProvider: { [display] },
            representationFrameProvider: { _ in liveFrame },
            windowFactory: { placement in
                let window = RefreshMaskWindow(frame: placement.frame)
                maskWindows.append(window)
                return window
            }
        )
        let store = MenuBarItemStore(
            permissions: permissions,
            preferences: preferences,
            language: language,
            scanner: scanner,
            captureOverride: { items in
                Dictionary(uniqueKeysWithValues: items.map {
                    ($0.id, NSImage(size: NSSize(width: 24, height: 24)))
                })
            },
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 27),
            maskingController: maskingController
        )

        store.refresh()
        guard await waitUntil({ store.selectedItems.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 56,
                userInfo: [NSLocalizedDescriptionKey:
                    "The failed-mask fixture did not discover its selected item."])
        }
        store.applyLayout()
        guard store.maskedItemIDs.isEmpty,
              store.layoutOperationMessage == language.text("store.layout.partial") else {
            throw NSError(domain: "RefreshIsolation", code: 57,
                userInfo: [NSLocalizedDescriptionKey:
                    "An invalid menu-bar frame did not enter the bounded failed state."])
        }

        windows = []
        store.refresh(source: .externalChange)
        guard await waitUntil({ store.items.isEmpty }) else {
            throw NSError(domain: "RefreshIsolation", code: 59,
                userInfo: [NSLocalizedDescriptionKey:
                    "The failed menu-bar item did not disappear from the store."])
        }
        var staleFailureCallbacks = 0
        store.onLayoutStateChanged = { staleFailureCallbacks += 1 }
        store.reconcileLiveMaskGeometry()
        store.reconcileLiveMaskGeometry()
        guard staleFailureCallbacks == 0,
              maskingController.maskedItemIDs.isEmpty,
              maskWindows.isEmpty else {
            throw NSError(domain: "RefreshIsolation", code: 60,
                userInfo: [NSLocalizedDescriptionKey:
                    "A vanished failed item kept publishing redundant mask retries."])
        }

        store.onLayoutStateChanged = nil
        windows = [utilityWindow]
        store.refresh(source: .externalChange)
        guard await waitUntil({ store.selectedItems.count == 1 }) else {
            throw NSError(domain: "RefreshIsolation", code: 61,
                userInfo: [NSLocalizedDescriptionKey:
                    "The failed-mask fixture did not return for the disable check."])
        }
        store.applyLayout()
        guard store.maskedItemIDs.isEmpty,
              store.layoutOperationMessage == language.text("store.layout.partial") else {
            throw NSError(domain: "RefreshIsolation", code: 62,
                userInfo: [NSLocalizedDescriptionKey:
                    "The returned invalid item did not re-enter the failed state."])
        }

        store.setLayoutManagementEnabled(false)
        liveFrame = CGRect(x: 1_000, y: 0, width: 30, height: 30)
        store.reconcileLiveMaskGeometry()
        guard !store.layoutManagementEnabled,
              !store.hasActiveMaskOverlay,
              maskingController.maskedItemIDs.isEmpty,
              maskWindows.isEmpty,
              store.visibilityDescription(for: store.items[0]) !=
                language.text("items.visibility.failed") else {
            throw NSError(domain: "RefreshIsolation", code: 58,
                userInfo: [NSLocalizedDescriptionKey:
                    "A disabled layout retried its mask or retained a stale failure state."])
        }
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

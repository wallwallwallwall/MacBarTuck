import AppKit

@main
@MainActor
enum RefreshIsolationTests {
    static func main() async throws {
        _ = NSApplication.shared
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
            visibilityOverride: { _ in false },
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

        preferences.saveRule(.alwaysVisible, for: scanner.scan(selectedIDs: []).first!.id)
        var hideCompletions: [(Int) -> Void] = []
        let store = MenuBarItemStore(permissions: permissions, preferences: preferences, language: language, scanner: scanner,
            captureOverride: { items in Dictionary(uniqueKeysWithValues: items.map { ($0.id, NSImage(size: NSSize(width: 24, height: 24))) }) },
            visibilityOverride: { _ in true }, hideOverride: { _, _, complete in hideCompletions.append(complete) })
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
        print("RefreshIsolationTests: 18 passed")
    }

    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

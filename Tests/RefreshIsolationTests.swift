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
        let permissions = PermissionManager(accessibilityStatus: { true }, accessibilityRequest: {},
            screenCaptureStatus: { true }, screenCaptureRequest: { true }, openSettings: { _ in }, history: nil)
        let windows: [[String: Any]] = [[kCGWindowLayer as String: 25,
            kCGWindowNumber as String: 4000000000, kCGWindowOwnerPID as String: -1,
            kCGWindowOwnerName as String: "Fixture", kCGWindowName as String: "utility",
            kCGWindowBounds as String: ["X": 1000, "Y": 0, "Width": 30, "Height": 30]]]
        let scanner = MenuBarScanner(readWindows: { windows },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1512, height: 982)] }, ownBundleIdentifier: "test.host")
        preferences.saveRule(.alwaysHidden, for: scanner.scan(selectedIDs: []).first!.id)
        var hideCompletions: [(Int) -> Void] = []
        let store = MenuBarItemStore(permissions: permissions, preferences: preferences, scanner: scanner,
            captureOverride: { items in Dictionary(uniqueKeysWithValues: items.map { ($0.id, NSImage(size: NSSize(width: 24, height: 24))) }) },
            visibilityOverride: { _ in true }, hideOverride: { _, _, complete in hideCompletions.append(complete) })
        var operations = 0
        store.onLayoutOperationStateChanged = { if $0 { operations += 1 } }
        store.refresh()
        try await Task.sleep(for: .milliseconds(500))
        guard operations == 0 else { throw NSError(domain: "RefreshIsolation", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "A list refresh started a layout transaction."]) }
        guard store.items.count == 1, store.selectedItems.count == 1 else {
            throw NSError(domain: "RefreshIsolation", code: 2)
        }
        for _ in 0..<12 { store.refresh() }
        try await Task.sleep(for: .milliseconds(500))
        guard operations == 0 else { throw NSError(domain: "RefreshIsolation", code: 3) }
        store.applyLayout()
        try await Task.sleep(for: .milliseconds(800))
        guard operations == 1, hideCompletions.count == 1 else { throw NSError(domain: "RefreshIsolation", code: 4) }
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
        try await Task.sleep(for: .milliseconds(800))
        guard hideCompletions.count == 2 else { throw NSError(domain: "RefreshIsolation", code: 8) }
        store.setLayoutManagementEnabled(false)
        hideCompletions[1](1)
        try await Task.sleep(for: .milliseconds(1200))
        guard !store.layoutManagementEnabled, !store.isHiddenSectionActive else { throw NSError(domain: "RefreshIsolation", code: 9) }
        print("RefreshIsolationTests: 9 passed")
    }
}

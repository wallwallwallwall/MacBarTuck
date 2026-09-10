import AppKit

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
private enum AppAccessTests {
    private static var checks = 0

    static func main() throws {
        _ = NSApplication.shared
        let domain = "AppAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        var policies: [Bool] = []
        let visibility = DockVisibilityController(preferences: preferences, previewMode: false,
            applyPolicy: { policies.append($0); return true })
        try expect(visibility.showsDockIcon, "Dock access should be enabled by default.")
        visibility.applyInitialPolicy()
        try expect(policies == [true], "Startup must apply the saved activation policy.")
        visibility.setDockIconVisible(false)
        try expect(!visibility.showsDockIcon && !preferences.showDockIcon, "Hiding the Dock icon must persist.")
        let restarted = DockVisibilityController(preferences: preferences, previewMode: false, applyPolicy: { _ in true })
        try expect(!restarted.showsDockIcon, "The hidden preference must survive restart.")
        visibility.setDockIconVisible(true)
        try expect(preferences.showDockIcon && policies == [true, false, true], "The icon must be restorable without restarting.")

        let failing = DockVisibilityController(preferences: preferences, previewMode: false, applyPolicy: { _ in false })
        failing.setDockIconVisible(false)
        try expect(failing.showsDockIcon && preferences.showDockIcon, "An OS refusal must not persist a false success.")
        try expect(failing.errorMessage != nil, "An OS refusal must be visible.")
        var previewCalls = 0
        let preview = DockVisibilityController(preferences: preferences, previewMode: true,
            applyPolicy: { _ in previewCalls += 1; return true })
        preview.applyInitialPolicy()
        preview.setDockIconVisible(false)
        try expect(previewCalls == 0 && preferences.showDockIcon, "UI preview must not modify Dock policy or preferences.")

        var settings = 0
        var tray = 0
        var hidden = 0
        var quits = 0
        let menus = AppMenuController(dockVisibility: visibility, showSettings: { settings += 1 },
            showTray: { tray += 1 }, hideApplication: { hidden += 1 }, quitApplication: { quits += 1 })
        let status = menus.makeStatusMenu()
        try expect(status.item(withTitle: "退出 BarTuck") != nil, "The status menu must always offer Quit.")
        try expect(status.item(withTitle: "设置…")?.keyEquivalent == ",", "Settings must have the standard keyboard shortcut.")
        try expect(status.item(withTitle: "在程序坞中显示")?.state == .on, "Menu state must match the preference.")
        status.performActionForItem(at: status.indexOfItem(withTitle: "设置…"))
        status.performActionForItem(at: status.indexOfItem(withTitle: "打开托盘"))
        status.performActionForItem(at: status.indexOfItem(withTitle: "隐藏窗口"))
        status.performActionForItem(at: status.indexOfItem(withTitle: "退出 BarTuck"))
        try expect(settings == 1 && tray == 1 && hidden == 1 && quits == 1, "Status actions must reach their distinct handlers.")
        status.performActionForItem(at: status.indexOfItem(withTitle: "在程序坞中显示"))
        try expect(!visibility.showsDockIcon, "The status menu must toggle Dock visibility.")
        let hiddenMenu = menus.makeStatusMenu()
        try expect(hiddenMenu.item(withTitle: "在程序坞中显示")?.state == .off,
                   "Reopening the menu must reflect a change made elsewhere.")
        try expect(hiddenMenu.item(withTitle: "设置…") != nil && hiddenMenu.item(withTitle: "退出 BarTuck") != nil,
                   "Hiding the Dock icon must preserve Settings and Quit access.")

        visibility.setDockIconVisible(true)
        let dock = menus.makeDockMenu()
        try expect(dock.item(withTitle: "设置…") != nil, "The Dock menu must expose Settings.")
        try expect(dock.items.allSatisfy { $0.action != #selector(NSApplication.terminate(_:)) },
                   "Custom Dock items must not duplicate the system Quit item.")
        dock.performActionForItem(at: dock.indexOfItem(withTitle: "隐藏程序坞图标"))
        try expect(!visibility.showsDockIcon, "Dock hiding must use the shared visibility controller.")
        _ = NSApp.setActivationPolicy(.accessory)
        preferences.showDockIcon = false
        let alreadyHidden = DockVisibilityController(preferences: preferences, previewMode: false)
        alreadyHidden.applyInitialPolicy()
        try expect(alreadyHidden.errorMessage == nil, "Starting already hidden must not report a policy error.")
        print("AppAccessTests: \(checks) passed")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw TestFailure(description: message) }
    }
}

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
        let language = AppLanguageController(defaults: defaults, preferredLanguages: ["zh-Hans"],
                                             arguments: [], rootBundle: .main)
        var policies: [Bool] = []
        let visibility = DockVisibilityController(preferences: preferences, previewMode: false, language: language,
            applyPolicy: { policies.append($0); return true })
        try expect(visibility.showsDockIcon, "Dock access should be enabled by default.")
        visibility.applyInitialPolicy()
        try expect(policies == [true], "Startup must apply the saved activation policy.")
        visibility.setDockIconVisible(false)
        try expect(!visibility.showsDockIcon && !preferences.showDockIcon, "Hiding the Dock icon must persist.")
        let restarted = DockVisibilityController(preferences: preferences, previewMode: false, language: language,
                                                 applyPolicy: { _ in true })
        try expect(!restarted.showsDockIcon, "The hidden preference must survive restart.")
        visibility.setDockIconVisible(true)
        try expect(preferences.showDockIcon && policies == [true, false, true], "The icon must be restorable without restarting.")

        let failing = DockVisibilityController(preferences: preferences, previewMode: false, language: language,
                                               applyPolicy: { _ in false })
        failing.setDockIconVisible(false)
        try expect(failing.showsDockIcon && preferences.showDockIcon, "An OS refusal must not persist a false success.")
        try expect(failing.errorMessage != nil, "An OS refusal must be visible.")
        var previewCalls = 0
        let preview = DockVisibilityController(preferences: preferences, previewMode: true, language: language,
            applyPolicy: { _ in previewCalls += 1; return true })
        preview.applyInitialPolicy()
        preview.setDockIconVisible(false)
        try expect(previewCalls == 0 && preferences.showDockIcon, "UI preview must not modify Dock policy or preferences.")

        var settings = 0
        var tray = 0
        var hidden = 0
        var quits = 0
        let menus = AppMenuController(dockVisibility: visibility, showSettings: { settings += 1 },
            showTray: { tray += 1 }, hideApplication: { hidden += 1 }, quitApplication: { quits += 1 },
            language: language)
        let status = menus.makeStatusMenu()
        try expect(status.item(withTitle: "退出 MacBarTuck") != nil, "The status menu must always offer Quit.")
        try expect(status.item(withTitle: "设置…")?.keyEquivalent == ",", "Settings must have the standard keyboard shortcut.")
        try expect(status.item(withTitle: "在程序坞中显示")?.state == .on, "Menu state must match the preference.")
        status.performActionForItem(at: status.indexOfItem(withTitle: "设置…"))
        status.performActionForItem(at: status.indexOfItem(withTitle: "打开托盘"))
        status.performActionForItem(at: status.indexOfItem(withTitle: "隐藏窗口"))
        status.performActionForItem(at: status.indexOfItem(withTitle: "退出 MacBarTuck"))
        try expect(settings == 1 && tray == 1 && hidden == 1 && quits == 1, "Status actions must reach their distinct handlers.")
        status.performActionForItem(at: status.indexOfItem(withTitle: "在程序坞中显示"))
        try expect(!visibility.showsDockIcon, "The status menu must toggle Dock visibility.")
        let hiddenMenu = menus.makeStatusMenu()
        try expect(hiddenMenu.item(withTitle: "在程序坞中显示")?.state == .off,
                   "Reopening the menu must reflect a change made elsewhere.")
        try expect(hiddenMenu.item(withTitle: "设置…") != nil && hiddenMenu.item(withTitle: "退出 MacBarTuck") != nil,
                   "Hiding the Dock icon must preserve Settings and Quit access.")

        visibility.setDockIconVisible(true)
        language.setLanguage(.english)
        let englishStatus = menus.makeStatusMenu()
        try expect(englishStatus.item(withTitle: "Quit MacBarTuck") != nil,
                   "Switching languages must update the status menu immediately.")
        try expect(englishStatus.item(withTitle: "Settings…")?.keyEquivalent == ",",
                   "The English Settings item must retain the standard shortcut.")
        try expect(englishStatus.item(withTitle: "Show in Dock")?.state == .on,
                   "The English menu must preserve the current Dock state.")
        let dock = menus.makeDockMenu()
        try expect(dock.item(withTitle: "Settings…") != nil, "The Dock menu must expose localized Settings.")
        try expect(dock.item(withTitle: "Hide Dock Icon") != nil, "The Dock visibility command must be localized.")
        try expect(dock.items.allSatisfy { $0.action != #selector(NSApplication.terminate(_:)) },
                   "Custom Dock items must not duplicate the system Quit item.")
        dock.performActionForItem(at: dock.indexOfItem(withTitle: "Hide Dock Icon"))
        try expect(!visibility.showsDockIcon, "Dock hiding must use the shared visibility controller.")
        _ = NSApp.setActivationPolicy(.accessory)
        preferences.showDockIcon = false
        let alreadyHidden = DockVisibilityController(preferences: preferences, previewMode: false, language: language)
        alreadyHidden.applyInitialPolicy()
        try expect(alreadyHidden.errorMessage == nil, "Starting already hidden must not report a policy error.")

        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: 240, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .aqua)
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        MacBarTuckTrayAppearance.apply(to: panel)
        try expect(panel.appearance?.name == .darkAqua,
                   "The real tray must use the same deterministic dark appearance as UI previews.")
        try expect(panel.contentView?.appearance?.name == .darkAqua,
                   "The tray content must inherit the deterministic dark appearance.")
        try expect(!panel.isOpaque && panel.backgroundColor.alphaComponent == 0,
                   "The borderless tray must not receive an opaque system-gray window background.")
        try expect(MacBarTuckTrayLayout.preferredWidth(itemCount: 0, showsRetuck: false) >= 246,
                   "The empty tray must leave room for its status summary and localized empty message.")
        try expect(MacBarTuckTrayLayout.preferredWidth(itemCount: 5, showsRetuck: false) == 345,
                   "Five tucked items must fit without falling back to a scroller.")
        try expect(MacBarTuckTrayLayout.preferredWidth(itemCount: 5, showsRetuck: true) == 470,
                   "Showing the retuck action must reserve a stable operation area.")
        print("AppAccessTests: \(checks) passed")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw TestFailure(description: message) }
    }
}

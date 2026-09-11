import AppKit

@MainActor
final class AppMenuController: NSObject {
    private let dockVisibility: DockVisibilityController
    private let showSettings: () -> Void
    private let showTray: () -> Void
    private let hideApplication: () -> Void
    private let quitApplication: () -> Void
    private let permissionSummary: () -> String
    private let language: AppLanguageController

    init(dockVisibility: DockVisibilityController, showSettings: @escaping () -> Void,
         showTray: @escaping () -> Void, hideApplication: @escaping () -> Void,
         quitApplication: @escaping () -> Void, permissionSummary: @escaping () -> String = { "" },
         language: AppLanguageController = .shared) {
        self.dockVisibility = dockVisibility
        self.showSettings = showSettings
        self.showTray = showTray
        self.hideApplication = hideApplication
        self.quitApplication = quitApplication
        self.permissionSummary = permissionSummary
        self.language = language
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "MacBarTuck")
        menu.autoenablesItems = false
        let summary = permissionSummary()
        if !summary.isEmpty {
            let status = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.separator())
        }
        menu.addItem(item(language.text("menu.open_tray"), action: #selector(openTray), symbol: "rectangle.stack"))
        menu.addItem(item(language.text("menu.settings"), action: #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        let dock = item(language.text("menu.show_dock"), action: #selector(toggleDock))
        dock.state = dockVisibility.showsDockIcon ? .on : .off
        menu.addItem(dock)
        menu.addItem(item(language.text("menu.hide_windows"), action: #selector(hideWindows), key: "h"))
        menu.addItem(.separator())
        menu.addItem(item(language.text("menu.quit"), action: #selector(quit), key: "q"))
        return menu
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu(title: "MacBarTuck")
        menu.autoenablesItems = false
        menu.addItem(item(language.text("menu.settings"), action: #selector(openSettings), symbol: "gearshape"))
        menu.addItem(item(language.text("menu.hide_dock"), action: #selector(hideDock)))
        // The Dock supplies the standard Hide and Quit actions itself.
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    @objc private func openSettings() { showSettings() }
    @objc private func openTray() { showTray() }
    @objc private func hideWindows() { hideApplication() }
    @objc private func quit() { quitApplication() }
    @objc private func toggleDock() { dockVisibility.setDockIconVisible(!dockVisibility.showsDockIcon) }
    @objc private func hideDock() { dockVisibility.setDockIconVisible(false) }
}

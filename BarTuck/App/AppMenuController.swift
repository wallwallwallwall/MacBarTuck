import AppKit

@MainActor
final class AppMenuController: NSObject {
    private let dockVisibility: DockVisibilityController
    private let showSettings: () -> Void
    private let showTray: () -> Void
    private let hideApplication: () -> Void
    private let quitApplication: () -> Void

    init(dockVisibility: DockVisibilityController, showSettings: @escaping () -> Void,
         showTray: @escaping () -> Void, hideApplication: @escaping () -> Void,
         quitApplication: @escaping () -> Void) {
        self.dockVisibility = dockVisibility
        self.showSettings = showSettings
        self.showTray = showTray
        self.hideApplication = hideApplication
        self.quitApplication = quitApplication
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "BarTuck")
        menu.autoenablesItems = false
        menu.addItem(item("打开托盘", action: #selector(openTray), symbol: "rectangle.stack"))
        menu.addItem(item("设置…", action: #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        let dock = item("在程序坞中显示", action: #selector(toggleDock))
        dock.state = dockVisibility.showsDockIcon ? .on : .off
        menu.addItem(dock)
        menu.addItem(item("隐藏窗口", action: #selector(hideWindows), key: "h"))
        menu.addItem(.separator())
        menu.addItem(item("退出 BarTuck", action: #selector(quit), key: "q"))
        return menu
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu(title: "BarTuck")
        menu.autoenablesItems = false
        menu.addItem(item("设置…", action: #selector(openSettings), symbol: "gearshape"))
        menu.addItem(item("隐藏程序坞图标", action: #selector(hideDock)))
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

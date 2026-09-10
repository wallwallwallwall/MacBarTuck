import AppKit
import ApplicationServices
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MenuBarItemStore()
    let dockVisibility = DockVisibilityController()
    private var permissions: PermissionManager { store.permissions }
    private let preferences = PreferencesStore()
    private var statusBarController: StatusBarController?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var panelPreviewWindowController: NSWindowController?
    private var isFinishingTermination = false
    private var didReplyToTermination = false
    private var restartScheduled = false
    private lazy var menus = AppMenuController(
        dockVisibility: dockVisibility,
        showSettings: { [weak self] in self?.showSettings() },
        showTray: { [weak self] in self?.statusBarController?.showPanel() },
        hideApplication: { NSApp.hide(nil) },
        quitApplication: { NSApp.terminate(nil) },
        permissionSummary: { [weak self] in
            guard let self else { return "" }
            self.permissions.refresh()
            return self.permissions.statusDetail
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger(subsystem: "com.bartuck.app", category: "startup").info("Accessibility trusted: \(AXIsProcessTrusted(), privacy: .public)")
        let arguments = ProcessInfo.processInfo.arguments
        if !store.isUIPreviewMode {
            DiagnosticLog.shared.record("application.start", ["build": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0,
                "permissions": permissions.effectiveAccessKey])
        }
        if arguments.contains("--ui-preview") {
            NSApp.setActivationPolicy(.regular)
            store.prepareForUIPreview()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if arguments.contains("--ui-preview-onboarding") {
                    self.showOnboarding()
                } else if arguments.contains("--ui-preview-panel") {
                    self.showPanelPreview()
                } else {
                    self.showSettings()
                }
            }
            return
        }

        statusBarController = StatusBarController(store: store, menuProvider: { [weak self] in
            self?.menus.makeStatusMenu() ?? NSMenu()
        })
        dockVisibility.applyInitialPolicy()
        store.startMonitoring()
        // Startup must be observational only. Restoring offscreen system
        // items uses synthetic Command-drag events and can change WindowServer
        // pointer state before the user has interacted with BarTuck.
        if preferences.hasCompletedOnboarding {
            store.refresh(source: .startup)
        } else {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        } else if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
    }

    func showSettings() {
        NSApp.unhide(nil)
        if let settingsWindowController { settingsWindowController.showWindow(nil) }
        else {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 780, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = store.isUIPreviewMode ? "BarTuck · 界面预览" : "BarTuck"
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentMinSize = .init(width: 760, height: 560)
            window.contentView = NSHostingView(rootView: SettingsView(store: store, dockVisibility: dockVisibility,
                restartApplication: { [weak self] in self?.restartApplication() }, showOnboarding: { [weak self] in
                self?.showOnboarding()
            }))
            window.center()
            let controller = NSWindowController(window: window)
            settingsWindowController = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        if store.isUIPreviewMode { return false }
        showSettings()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { menus.makeDockMenu() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func restartApplication() {
        guard !store.isUIPreviewMode, !restartScheduled else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for normal termination (including layout restoration). Pass
        // the bundle path as an argument, never as shell source text.
        helper.arguments = ["-c", "for attempt in 1 2 3 4 5 6 7 8 9 10; do if ! /bin/kill -0 \"$2\" 2>/dev/null; then exec /usr/bin/open -n \"$1\" --args --show-settings; fi; /bin/sleep 1; done; exit 1",
                            "BarTuck-restart", Bundle.main.bundleURL.path, String(getpid())]
        do {
            try helper.run()
            restartScheduled = true
            NSApp.terminate(nil)
        } catch {
            store.lastActivationError = "无法重新启动 BarTuck：\(error.localizedDescription)"
        }
    }

    func showOnboarding() {
        if let onboardingWindowController {
            onboardingWindowController.showWindow(nil)
        } else {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = store.isUIPreviewMode ? "设置 BarTuck · 界面预览" : "设置 BarTuck"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentMinSize = .init(width: 680, height: 500)
            window.contentView = NSHostingView(rootView: OnboardingView(
                store: store,
                permissions: permissions,
                initialHideSelectedIcons: preferences.hasCompletedOnboarding ? store.layoutManagementEnabled : true,
                onComplete: { [weak self] hideSelectedIcons in
                    guard let self else { return }
                    if self.store.isUIPreviewMode {
                        self.onboardingWindowController?.close()
                        return
                    }
                    self.completeOnboarding(hideSelectedIcons: hideSelectedIcons)
                }
            ))
            window.center()
            let controller = NSWindowController(window: window)
            onboardingWindowController = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPanelPreview() {
        if let panelPreviewWindowController {
            panelPreviewWindowController.showWindow(nil)
        } else {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 720, height: 260),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "BarTuck 托盘预览"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: OverflowPanelPreviewView(store: store))
            window.center()
            let controller = NSWindowController(window: window)
            panelPreviewWindowController = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeOnboarding(hideSelectedIcons: Bool) {
        preferences.hasCompletedOnboarding = true
        store.refresh()
        store.setLayoutManagementEnabled(hideSelectedIcons)
        onboardingWindowController?.close()
        onboardingWindowController = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.layoutManagementEnabled, !store.selectedItems.isEmpty else { return .terminateNow }
        guard !isFinishingTermination else { return .terminateLater }
        isFinishingTermination = true
        didReplyToTermination = false
        statusBarController?.prepareForTermination()
        store.prepareForTermination { [weak self, weak sender] in
            guard let sender else { return }
            self?.replyToTermination(sender)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak sender] in
            guard let sender else { return }
            self?.replyToTermination(sender)
        }
        return .terminateLater
    }

    private func replyToTermination(_ sender: NSApplication) {
        guard !didReplyToTermination else { return }
        didReplyToTermination = true
        sender.reply(toApplicationShouldTerminate: true)
    }
}

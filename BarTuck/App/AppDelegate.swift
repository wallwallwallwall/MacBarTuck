import AppKit
import ApplicationServices
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = MenuBarItemStore()
    private let permissions = PermissionManager()
    private let preferences = PreferencesStore()
    private var statusBarController: StatusBarController?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var panelPreviewWindowController: NSWindowController?
    private var isFinishingTermination = false
    private var didReplyToTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger(subsystem: "com.bartuck.app", category: "startup").info("Accessibility trusted: \(AXIsProcessTrusted(), privacy: .public)")
        let arguments = ProcessInfo.processInfo.arguments
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

        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(store: store, showSettings: { [weak self] in self?.showSettings() })
        store.startMonitoring()
        // Startup must be observational only. Restoring offscreen system
        // items uses synthetic Command-drag events and can change WindowServer
        // pointer state before the user has interacted with BarTuck.
        if preferences.hasCompletedOnboarding {
            store.refresh()
        } else {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        } else if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
    }

    private func showSettings() {
        if let settingsWindowController { settingsWindowController.showWindow(nil) }
        else {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 780, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "BarTuck 设置"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentMinSize = .init(width: 760, height: 560)
            window.contentView = NSHostingView(rootView: SettingsView(store: store, showOnboarding: { [weak self] in
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
        showSettings()
        return true
    }

    func showOnboarding() {
        if let onboardingWindowController {
            onboardingWindowController.showWindow(nil)
        } else {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "欢迎使用 BarTuck"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
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

import AppKit
import Combine

@MainActor
final class DockVisibilityController: ObservableObject {
    @Published private(set) var showsDockIcon: Bool
    @Published private(set) var errorMessage: String?
    private let preferences: PreferencesStore
    private let previewMode: Bool
    private let applyPolicy: @MainActor (Bool) -> Bool

    init(preferences: PreferencesStore = PreferencesStore(),
         previewMode: Bool = ProcessInfo.processInfo.arguments.contains("--ui-preview"),
         applyPolicy: @escaping @MainActor (Bool) -> Bool = { visible in
             let desired: NSApplication.ActivationPolicy = visible ? .regular : .accessory
             // AppKit returns false when no change is needed.
             if NSApp.activationPolicy() == desired { return true }
             let wasActive = NSApp.isActive
             let applied = NSApp.setActivationPolicy(desired)
             if applied && wasActive { NSApp.activate(ignoringOtherApps: true) }
             return applied
         }) {
        self.preferences = preferences
        self.previewMode = previewMode
        self.applyPolicy = applyPolicy
        showsDockIcon = preferences.showDockIcon
    }

    func applyInitialPolicy() {
        guard !previewMode else { return }
        errorMessage = applyPolicy(showsDockIcon) ? nil : "无法更新程序坞显示，请重试。"
    }

    func setDockIconVisible(_ visible: Bool) {
        if previewMode { showsDockIcon = visible; return }
        guard applyPolicy(visible) else {
            errorMessage = "无法更新程序坞显示，请重试。"
            return
        }
        preferences.showDockIcon = visible
        showsDockIcon = visible
        errorMessage = nil
    }
}

import SwiftUI

@main
struct BarTuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store, dockVisibility: appDelegate.dockVisibility,
                         showOnboarding: { appDelegate.showOnboarding() })
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

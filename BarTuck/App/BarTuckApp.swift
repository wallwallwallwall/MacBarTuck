import SwiftUI

@main
struct BarTuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store, showOnboarding: { appDelegate.showOnboarding() })
        }
    }
}

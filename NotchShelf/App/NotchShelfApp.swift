import SwiftUI

@main
struct NotchShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store, showOnboarding: { appDelegate.showOnboarding() })
        }
    }
}

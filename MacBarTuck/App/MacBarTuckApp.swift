import SwiftUI

@main
struct MacBarTuckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppLocalizedRoot(language: appDelegate.language) {
                SettingsView(store: appDelegate.store, dockVisibility: appDelegate.dockVisibility,
                             restartApplication: { appDelegate.restartApplication() },
                             showOnboarding: { appDelegate.showOnboarding() })
            }
        }
        .commands {
            LocalizedAppCommands(language: appDelegate.language, showSettings: appDelegate.showSettings)
        }
    }
}

private struct LocalizedAppCommands: Commands {
    @ObservedObject var language: AppLanguageController
    let showSettings: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(language.text("menu.settings"), action: showSettings)
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}

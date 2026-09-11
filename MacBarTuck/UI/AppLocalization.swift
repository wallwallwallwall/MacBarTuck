import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var switchLabel: String {
        switch self {
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }
}

final class AppLanguageController: ObservableObject {
    static let preferenceKey = "appLanguage"
    static let shared = AppLanguageController()

    @Published private(set) var selectedLanguage: AppLanguage

    private let defaults: UserDefaults
    private let rootBundle: Bundle
    private let persistsSelection: Bool

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        rootBundle: Bundle = .main
    ) {
        self.defaults = defaults
        self.rootBundle = rootBundle

        let previewPrefix = "--ui-preview-language="
        if let argument = arguments.first(where: { $0.hasPrefix(previewPrefix) }),
           let previewLanguage = AppLanguage(rawValue: String(argument.dropFirst(previewPrefix.count))) {
            selectedLanguage = previewLanguage
            persistsSelection = false
        } else if let stored = defaults.string(forKey: Self.preferenceKey),
                  let savedLanguage = AppLanguage(rawValue: stored) {
            selectedLanguage = savedLanguage
            persistsSelection = true
        } else {
            let preferred = preferredLanguages.first?.lowercased() ?? ""
            selectedLanguage = preferred.hasPrefix("zh") ? .simplifiedChinese : .english
            persistsSelection = true
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard selectedLanguage != language else { return }
        selectedLanguage = language
        if persistsSelection { defaults.set(language.rawValue, forKey: Self.preferenceKey) }
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        text(key, arguments: arguments)
    }

    func text(_ key: String, arguments: [CVarArg]) -> String {
        Self.text(key, language: selectedLanguage, rootBundle: rootBundle, arguments: arguments)
    }

    static func text(
        _ key: String,
        language: AppLanguage,
        rootBundle: Bundle = .main,
        arguments: [CVarArg] = []
    ) -> String {
        let bundle = localizedBundle(for: language, rootBundle: rootBundle)
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func localizedBundle(for language: AppLanguage, rootBundle: Bundle) -> Bundle {
        guard let path = rootBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return rootBundle }
        return bundle
    }
}

struct AppLocalizedRoot<Content: View>: View {
    @ObservedObject var language: AppLanguageController
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environmentObject(language)
            .environment(\.locale, language.selectedLanguage.locale)
    }
}

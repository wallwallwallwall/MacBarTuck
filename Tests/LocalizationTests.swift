import Foundation

private struct LocalizationTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum LocalizationTests {
    private static var checks = 0

    static func main() throws {
        let domain = "LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }

        let chinese = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"],
            arguments: []
        )
        try expect(chinese.selectedLanguage == .simplifiedChinese,
                   "Chinese systems should start in Simplified Chinese.")

        chinese.setLanguage(.english)
        try expect(chinese.selectedLanguage == .english,
                   "The language switch must update the active language immediately.")

        let relaunched = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"],
            arguments: []
        )
        try expect(relaunched.selectedLanguage == .english,
                   "The selected language must survive relaunch.")

        let unsupportedSystem = AppLanguageController(
            defaults: UserDefaults(suiteName: "\(domain).fallback")!,
            preferredLanguages: ["fr-FR"],
            arguments: []
        )
        try expect(unsupportedSystem.selectedLanguage == .english,
                   "Unsupported system languages should fall back to English.")

        let preview = AppLanguageController(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"],
            arguments: ["MacBarTuck", "--ui-preview-language=zh-Hans"]
        )
        try expect(preview.selectedLanguage == .simplifiedChinese,
                   "UI previews need a non-persistent language override.")
        try expect(defaults.string(forKey: AppLanguageController.preferenceKey) == AppLanguage.english.rawValue,
                   "A UI preview override must not replace the saved user preference.")

        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MacBarTuck/Resources", isDirectory: true)
        let zh = try strings(at: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))
        let en = try strings(at: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let zhInfo = try strings(at: resources.appendingPathComponent("zh-Hans.lproj/InfoPlist.strings"))
        let enInfo = try strings(at: resources.appendingPathComponent("en.lproj/InfoPlist.strings"))

        try expect(!zh.isEmpty && !en.isEmpty, "Both localization tables must contain strings.")
        try expect(Set(zh.keys) == Set(en.keys), "Chinese and English localization keys must match exactly.")
        try expect(zh.values.allSatisfy { !$0.isEmpty } && en.values.allSatisfy { !$0.isEmpty },
                   "Localized values must never be empty.")

        for key in [
            "settings.tab.items",
            "settings.tab.general",
            "settings.tab.permissions",
            "preferences.language.section",
            "preferences.language.label",
            "menu.quit",
            "onboarding.welcome.title",
            "panel.empty",
            "items.footer.count",
            "items.visibility.temporary",
            "items.retuck_temporary",
            "panel.retuck",
            "panel.retuck.count",
            "panel.temporary.help",
            "preferences.hover.help",
            "store.activation.retuck_progress"
        ] {
            try expect(zh[key] != nil && en[key] != nil, "Missing required localization key: \(key)")
        }

        try expect(en["settings.tab.items"] == "Menu Items", "English settings labels must be translated.")
        try expect(zh["preferences.language.label"] == "界面语言", "Chinese language control must be clear.")
        try expect(Set(zhInfo.keys) == Set(enInfo.keys), "Chinese and English Info.plist localization keys must match.")
        try expect(zhInfo["NSScreenCaptureUsageDescription"]?.isEmpty == false,
                   "Chinese screen recording usage text must be present.")
        try expect(enInfo["NSScreenCaptureUsageDescription"]?.isEmpty == false,
                   "English screen recording usage text must be present.")

        guard let resourceBundle = Bundle(path: resources.path) else {
            throw LocalizationTestFailure(description: "Unable to load localization resource bundle.")
        }
        try expect(AppLanguageController.text("menu.quit", language: .simplifiedChinese,
                                              rootBundle: resourceBundle) == "退出 MacBarTuck",
                   "The runtime localizer must load Chinese resources.")
        try expect(AppLanguageController.text("menu.quit", language: .english,
                                              rootBundle: resourceBundle) == "Quit MacBarTuck",
                   "The runtime localizer must load English resources.")
        try expect(AppLanguageController.text("items.footer.count", language: .english,
                                              rootBundle: resourceBundle, arguments: [3]) == "3 Menu Items",
                   "The runtime localizer must format localized values.")
        try expect(AppLanguageController.text("panel.retuck.count", language: .simplifiedChinese,
                                              rootBundle: resourceBundle, arguments: [1]) == "重新收纳 1 项",
                   "The Chinese tray action must explain what the temporary-item count means.")
        try expect(AppLanguageController.text("panel.retuck.count", language: .english,
                                              rootBundle: resourceBundle, arguments: [1]) == "Retuck: 1",
                   "The English tray action must explain what the temporary-item count means.")

        let englishLanguage = AppLanguageController(
            defaults: UserDefaults(suiteName: "\(domain).display")!,
            preferredLanguages: ["en"],
            arguments: [],
            rootBundle: resourceBundle
        )
        let builtInDisplay = DisplaySnapshot(
            id: 1,
            name: "内建视网膜显示器",
            isBuiltIn: true,
            isMain: true,
            frame: .zero,
            pixelSize: CGSize(width: 1512, height: 982),
            hasNotch: true,
            availableMenuWidth: 520
        )
        try expect(builtInDisplay.displayName(for: englishLanguage) == "Built-in Display",
                   "Built-in display names must follow the selected app language, not the system language.")

        for key in zh.keys {
            try expect(formatTokens(in: zh[key]!) == formatTokens(in: en[key]!),
                       "Format placeholders must match for key: \(key)")
        }

        print("LocalizationTests: \(checks) passed")
    }

    private static func strings(at url: URL) throws -> [String: String] {
        guard let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            throw LocalizationTestFailure(description: "Unable to read localization table: \(url.path)")
        }
        return dictionary
    }

    private static func formatTokens(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:ld|d|@|\.\d+f)"#
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw LocalizationTestFailure(description: message) }
    }
}

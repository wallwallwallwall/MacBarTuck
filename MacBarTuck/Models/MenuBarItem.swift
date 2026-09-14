import AppKit
import ApplicationServices

enum MenuBarSystemItemClassifier {
    static func isInputSourceAgent(_ title: String, owner: String? = nil) -> Bool {
        let values = [normalize(title), normalize(owner ?? "")]
        return values.contains("com.apple.textinputmenuagent") ||
            values.contains(where: { $0.contains("textinputmenuagent") })
    }

    static func prefersCapturedMenuBarIcon(_ title: String, bundleIdentifier: String? = nil) -> Bool {
        isInputSourceAgent(title, owner: bundleIdentifier)
    }

    static func isGenericControlCenterItem(_ title: String, owner: String? = nil) -> Bool {
        let normalized = normalize(title)
        let normalizedOwner = normalize(owner ?? "")
        return normalizedOwner.contains("controlcenter") &&
            ["item-0", "item0", "statusmenu", "menubaritem"].contains(normalized)
    }

    static func isProtected(_ title: String, owner: String? = nil) -> Bool {
        let normalized = normalize(title)
        return normalized.contains("clock") ||
            normalized.contains("battery") ||
            normalized.contains("siri") ||
            normalized.contains("wifi") ||
            normalized.contains("bluetooth") ||
            normalized.contains("screenrecording") ||
            normalized.contains("bentobox") ||
            normalized.contains("audiovideomodule") ||
            normalized.contains("audioandvideocontrols")
    }

    static func canonicalName(_ title: String, owner: String? = nil) -> String {
        let normalized = normalize(title)
        if isInputSourceAgent(title, owner: owner) { return "Input Source" }
        if normalized.contains("wifi") { return "WiFi" }
        if normalized.contains("bluetooth") { return "Bluetooth" }
        if normalized.contains("battery") { return "Battery" }
        if normalized.contains("siri") { return "Siri" }
        if normalized.contains("screenrecording") { return "Screen Recording" }
        if normalized.contains("clock") { return "Clock" }
        if normalized.contains("controlcenter") { return "Control Center" }
        if normalized.contains("audioandvideocontrols") || normalized.contains("audiovideomodule") {
            return "Audio and Video Controls"
        }
        if normalized.contains("bentobox") { return "Control Center" }
        if isProtected(title, owner: owner) && normalize(owner ?? "").contains("controlcenter") {
            return "Control Center Item"
        }
        return title
    }

    private static func normalize(_ title: String) -> String {
        title
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}

/// Accessibility-backed description of one right-side menu bar control.
final class MenuBarItem: Identifiable {
    let id: String
    var title: String
    var ownerName: String
    var bundleIdentifier: String?
    var frame: CGRect
    private(set) var restorationFrame: CGRect
    var axElement: AXUIElement?
    var supportsPressAction: Bool
    var windowID: CGWindowID?
    var ownerPID: pid_t?
    var isProtectedSystemItem: Bool
    var iconImage: NSImage?
    var applicationIcon: NSImage?
    var isSelected: Bool
    var rule: MenuItemRule
    var mirrors: [MenuBarItem] = []
    var sourceDisplayBounds: CGRect?
    var legacyIDs: Set<String> = []
    var resolvedTitle: String?
    var resolvedApplicationIcon: NSImage?
    var visibility: MenuItemVisibility = .unknown

    func updateVisibility(displayBounds: [CGRect], currentFrames: [CGWindowID: CGRect]? = nil) {
        visibility = MenuItemVisibility.evaluate(windowRepresentations.map { representation -> Bool? in
            let frame: CGRect
            if let currentFrames, let id = representation.windowID {
                guard let current = currentFrames[id] else { return nil }
                frame = current
            } else { frame = representation.frame }
            guard frame.width > 4, frame.height > 4 else { return nil }
            return MenuBarGeometry.isVisibleMenuBarItem(frame,
                displayBounds: representation.sourceDisplayBounds.map { [$0] } ?? displayBounds)
        })
    }

    init(id: String, title: String, ownerName: String, bundleIdentifier: String?, frame: CGRect, axElement: AXUIElement?, iconImage: NSImage? = nil, applicationIcon: NSImage? = nil, isSelected: Bool, supportsPressAction: Bool, windowID: CGWindowID? = nil, ownerPID: pid_t? = nil, isProtectedSystemItem: Bool = false, rule: MenuItemRule = .automatic) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        restorationFrame = frame
        self.axElement = axElement
        self.iconImage = iconImage
        self.applicationIcon = applicationIcon
        self.isSelected = isSelected
        self.rule = rule
        self.supportsPressAction = supportsPressAction
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.isProtectedSystemItem = isProtectedSystemItem
    }

    var displayTitle: String { displayTitle(for: AppLanguageController.shared.selectedLanguage) }

    func displayTitle(for language: AppLanguage) -> String {
        let value = resolvedTitle ?? title
        let normalized = value.lowercased()
        if normalized.hasPrefix("unidentified item "),
           let index = Int(normalized.dropFirst("unidentified item ".count)) {
            return localized("item.unidentified", language: language, index)
        }
        return switch normalized {
        case "menu bar item": localized("item.menu_bar_item", language: language)
        case "screen recording": localized("item.screen_recording", language: language)
        case "audio and video controls": localized("item.audio_video", language: language)
        case "control center item": localized("item.control_center_item", language: language)
        case "control center": localized("item.control_center", language: language)
        case "battery": localized("item.battery", language: language)
        case "clock": localized("item.clock", language: language)
        case "bluetooth": localized("item.bluetooth", language: language)
        case "input source": localized("item.input_source", language: language)
        case "window layout": localized("preview.item.window", language: language)
        case "focus timer": localized("preview.item.focus", language: language)
        case "clipboard": localized("preview.item.clipboard", language: language)
        case "sound": localized("preview.item.audio", language: language)
        case "wifi": "Wi-Fi"
        default: value
        }
    }

    var displayOwnerName: String { displayOwnerName(for: AppLanguageController.shared.selectedLanguage) }

    func displayOwnerName(for language: AppLanguage) -> String {
        switch ownerName.lowercased() {
        case "system menu bar": localized("item.owner.system", language: language)
        case "control center": localized("item.control_center", language: language)
        default: ownerName
        }
    }

    var tooltip: String { tooltip(for: AppLanguageController.shared.selectedLanguage) }

    func tooltip(for language: AppLanguage) -> String {
        let title = displayTitle(for: language)
        let owner = displayOwnerName(for: language)
        return title.isEmpty ? owner : "\(owner) · \(title)"
    }
    /// The overflow tray favors an application's full-color icon when one can
    /// be resolved. Protected system controls keep their item-specific glyph.
    var displayImage: NSImage? {
        if isProtectedSystemItem { return menuBarImage }
        if MenuBarSystemItemClassifier.prefersCapturedMenuBarIcon(title, bundleIdentifier: bundleIdentifier) {
            return iconImage
        }
        return resolvedApplicationIcon ?? applicationIcon ?? iconImage
    }

    var usesApplicationIconForDisplay: Bool {
        !isProtectedSystemItem &&
            !MenuBarSystemItemClassifier.prefersCapturedMenuBarIcon(title, bundleIdentifier: bundleIdentifier) &&
            (resolvedApplicationIcon != nil || applicationIcon != nil)
    }

    var usesTemplateIcon: Bool {
        displayImage?.isTemplate == true
    }

    /// Settings describe the scanned menu-bar item, so they continue to show
    /// the captured glyph instead of substituting the tray presentation.
    var menuBarImage: NSImage? { iconImage ?? resolvedApplicationIcon ?? applicationIcon }
    var usesTemplateMenuBarIcon: Bool { menuBarImage?.isTemplate == true }

    var isAlwaysVisibleSystemItem: Bool {
        isProtectedSystemItem && MenuItemSafetyPolicy.mustRemainVisible(title: title)
    }

    var windowRepresentations: [MenuBarItem] { [self] + mirrors }

    func representation(on display: CGRect) -> MenuBarItem? {
        windowRepresentations.first { $0.sourceDisplayBounds == display }
            ?? windowRepresentations.first {
                $0.sourceDisplayBounds == nil && MenuBarGeometry.isVisibleMenuBarItem($0.frame, displayBounds: [display])
            }
    }

    func activationTarget(on display: CGRect?) -> MenuBarItem {
        guard let display, let source = representation(on: display), source !== self else { return self }
        let target = MenuBarItem(id: id, title: source.title, ownerName: source.ownerName,
                                 bundleIdentifier: source.bundleIdentifier, frame: source.frame,
                                 axElement: source.axElement, iconImage: iconImage,
                                 applicationIcon: applicationIcon, isSelected: isSelected,
                                 supportsPressAction: source.supportsPressAction, windowID: source.windowID,
                                 ownerPID: source.ownerPID, isProtectedSystemItem: isProtectedSystemItem, rule: rule)
        target.sourceDisplayBounds = source.sourceDisplayBounds
        target.resolvedTitle = resolvedTitle
        target.resolvedApplicationIcon = resolvedApplicationIcon
        return target
    }
    /// The activation path used by the item. WindowServer-backed items do not
    /// expose an Accessibility press action, but they can still be activated
    /// directly without moving the user's cursor or waiting for AX traversal.
    var activationStatusSymbolName: String {
        if supportsPressAction { return "hand.tap" }
        if windowID != nil { return "bolt.fill" }
        return "exclamationmark.triangle"
    }
    var activationStatusHelp: String {
        if supportsPressAction { return localized("item.activation.ax", language: AppLanguageController.shared.selectedLanguage) }
        if windowID != nil { return localized("item.activation.window_server", language: AppLanguageController.shared.selectedLanguage) }
        return localized("item.activation.unavailable", language: AppLanguageController.shared.selectedLanguage)
    }
    var hasUsableDisplayIcon: Bool {
        if windowID != nil { return iconImage != nil }
        return displayImage != nil || NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil) != nil
    }

    var fallbackSymbolName: String {
        let value = title.lowercased()
        if value.contains("audio") || value.contains("sound") { return "speaker.wave.2.fill" }
        if value.contains("battery") { return "battery.75percent" }
        if value.contains("wifi") { return "wifi" }
        if value.contains("screen recording") || value.contains("screenrecording") { return "record.circle" }
        if value.contains("vpn") { return "lock.shield.fill" }
        if value.contains("clock") { return "clock.fill" }
        if MenuBarSystemItemClassifier.isInputSourceAgent(title, owner: bundleIdentifier) { return "keyboard" }
        if value.contains("amphetamine") { return "bolt.fill" }
        return "circle.grid.2x2.fill"
    }

    func updateRuntimeState(from scanned: MenuBarItem, displayBounds: [CGRect]) {
        if MenuBarGeometry.isVisibleMenuBarItem(scanned.frame, displayBounds: displayBounds) {
            restorationFrame = scanned.frame
        }
        title = scanned.title
        ownerName = scanned.ownerName
        bundleIdentifier = scanned.bundleIdentifier
        frame = scanned.frame
        axElement = scanned.axElement
        supportsPressAction = scanned.supportsPressAction
        windowID = scanned.windowID
        ownerPID = scanned.ownerPID
        isProtectedSystemItem = scanned.isProtectedSystemItem
        applicationIcon = scanned.applicationIcon
        mirrors = scanned.mirrors
        sourceDisplayBounds = scanned.sourceDisplayBounds
        legacyIDs = scanned.legacyIDs
        resolvedTitle = scanned.resolvedTitle
        resolvedApplicationIcon = scanned.resolvedApplicationIcon
        if let captured = scanned.iconImage { iconImage = captured }
    }

    private func localized(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        AppLanguageController.text(key, language: language, arguments: arguments)
    }
}

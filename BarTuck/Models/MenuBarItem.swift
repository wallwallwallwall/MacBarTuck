import AppKit
import ApplicationServices

enum MenuBarSystemItemClassifier {
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
    let frame: CGRect
    var axElement: AXUIElement?
    var supportsPressAction: Bool
    let windowID: CGWindowID?
    let ownerPID: pid_t?
    var isProtectedSystemItem: Bool
    var iconImage: NSImage?
    let applicationIcon: NSImage?
    var isSelected: Bool
    var rule: MenuItemRule
    var mirrors: [MenuBarItem] = []
    var sourceDisplayBounds: CGRect?
    var legacyIDs: Set<String> = []
    var resolvedTitle: String?
    var resolvedApplicationIcon: NSImage?

    init(id: String, title: String, ownerName: String, bundleIdentifier: String?, frame: CGRect, axElement: AXUIElement?, iconImage: NSImage? = nil, applicationIcon: NSImage? = nil, isSelected: Bool, supportsPressAction: Bool, windowID: CGWindowID? = nil, ownerPID: pid_t? = nil, isProtectedSystemItem: Bool = false, rule: MenuItemRule = .automatic) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
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

    var displayTitle: String {
        if let resolvedTitle { return resolvedTitle }
        return switch title.lowercased() {
        case "menu bar item": "菜单栏项目"
        case "screen recording": "屏幕录制"
        case "audio and video controls": "音频与视频控制"
        case "control center item": "控制中心项目"
        case "control center": "控制中心"
        case "battery": "电池"
        case "clock": "时钟"
        case "bluetooth": "蓝牙"
        case "wifi": "Wi-Fi"
        default: title
        }
    }

    var displayOwnerName: String {
        switch ownerName.lowercased() {
        case "system menu bar": "系统菜单栏"
        case "control center": "控制中心"
        default: ownerName
        }
    }

    var tooltip: String {
        displayTitle.isEmpty ? displayOwnerName : "\(displayOwnerName) · \(displayTitle)"
    }
    /// Preserve colors in captured glyphs, including system privacy badges.
    var usesTemplateIcon: Bool {
        iconImage?.isTemplate == true
    }
    var isAlwaysVisibleSystemItem: Bool {
        isProtectedSystemItem && MenuItemSafetyPolicy.mustRemainVisible(title: title)
    }
    var displayImage: NSImage? { iconImage ?? resolvedApplicationIcon ?? applicationIcon }

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
        if supportsPressAction { return "通过辅助功能执行原菜单动作" }
        if windowID != nil { return "通过 WindowServer 快速激活" }
        return "当前无法通过辅助功能激活"
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
        if value.contains("amphetamine") { return "bolt.fill" }
        return "circle.grid.2x2.fill"
    }
}

import AppKit
import SwiftUI

enum MacBarTuckTheme {
    static let canvas = Color(red: 0.095, green: 0.102, blue: 0.106)
    static let chrome = Color(red: 0.122, green: 0.134, blue: 0.138)
    static let surface = Color(red: 0.137, green: 0.149, blue: 0.153)
    static let raisedSurface = Color.white.opacity(0.045)
    static let deepSurface = Color.black.opacity(0.14)
    static let traySurface = Color(red: 0.110, green: 0.122, blue: 0.126).opacity(0.98)
    static let trayStroke = Color.white.opacity(0.18)
    static let stroke = Color.white.opacity(0.09)
    static let strongStroke = Color.white.opacity(0.16)
    static let primaryText = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let secondaryText = Color(red: 0.65, green: 0.68, blue: 0.70)
    static let accent = Color(red: 0.10, green: 0.55, blue: 0.98)
    static let accentStrong = accent
    static let success = Color(red: 0.22, green: 0.85, blue: 0.48)
    static let collected = Color(red: 0.67, green: 0.53, blue: 0.96)
    static let retuckAction = Color(red: 0.98, green: 0.72, blue: 0.29)
    static let warning = Color(red: 1.00, green: 0.43, blue: 0.38)
}

struct MacBarTuckSettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 14) { content }
                .foregroundStyle(MacBarTuckTheme.primaryText)
            Divider().overlay(MacBarTuckTheme.stroke)
        }
    }
}

struct MacBarTuckPreferenceToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(MacBarTuckTheme.success)
                .accessibilityLabel(title)
        }
    }
}

@MainActor
enum MacBarTuckTrayAppearance {
    static func apply(to panel: NSPanel) {
        let appearance = NSAppearance(named: .darkAqua)
        panel.appearance = appearance
        panel.contentView?.appearance = appearance
        panel.isOpaque = false
        panel.backgroundColor = .clear
    }
}

enum MacBarTuckTrayLayout {
    static let preferredHeight: CGFloat = 50
    static let itemSlotWidth: CGFloat = 40
    static let itemSpacing: CGFloat = 2
    static let summaryWidth: CGFloat = 104
    static let retuckButtonWidth: CGFloat = 114

    private static let baseChromeWidth: CGFloat = summaryWidth + 31
    private static let retuckChromeWidth: CGFloat = retuckButtonWidth + 11
    private static let emptyMessageWidth: CGFloat = 109
    private static let layoutSafetyWidth: CGFloat = 2

    static func preferredWidth(itemCount: Int, showsRetuck: Bool) -> CGFloat {
        let count = max(0, itemCount)
        let contentWidth: CGFloat
        if count == 0 {
            contentWidth = emptyMessageWidth
        } else {
            contentWidth = CGFloat(count) * itemSlotWidth
                + CGFloat(max(0, count - 1)) * itemSpacing
        }
        return baseChromeWidth
            + contentWidth
            + (showsRetuck ? retuckChromeWidth : 0)
            + layoutSafetyWidth
    }
}

struct MacBarTuckSurface<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(MacBarTuckTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MacBarTuckTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MacBarTuckSectionTitle: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacBarTuckTheme.primaryText)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MacBarTuckTheme.secondaryText)
            }
            Spacer()
        }
    }
}

struct MacBarTuckStatusPill: View {
    let title: String
    let color: Color
    var systemImage: String?

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
    }
}

struct MenuItemIconView: View {
    let item: MenuBarItem
    var size: CGFloat = 22
    var prefersApplicationIcon = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let image = prefersApplicationIcon ? item.displayImage : item.menuBarImage
        let usesTemplate = prefersApplicationIcon ? item.usesTemplateIcon : item.usesTemplateMenuBarIcon
        Group {
            if let image {
                Image(nsImage: image)
                    .renderingMode(usesTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(usesTemplate && colorScheme == .dark ? MacBarTuckTheme.primaryText : Color.primary)
            } else {
                Image(systemName: item.fallbackSymbolName)
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(MacBarTuckTheme.primaryText)
            }
        }
        .frame(width: size, height: size)
    }
}

extension MenuItemRule {
    var localizedTitle: String {
        let language = AppLanguageController.shared
        return switch self {
        case .automatic: language.text("items.mode.automatic")
        case .alwaysVisible: language.text("items.mode.visible")
        case .alwaysHidden: language.text("items.mode.hidden")
        }
    }

    var symbolName: String {
        switch self {
        case .automatic: "wand.and.stars"
        case .alwaysVisible: "eye.fill"
        case .alwaysHidden: "tray.full.fill"
        }
    }

    var tint: Color {
        switch self {
        case .automatic: MacBarTuckTheme.accent
        case .alwaysVisible: MacBarTuckTheme.success
        case .alwaysHidden: MacBarTuckTheme.collected
        }
    }
}

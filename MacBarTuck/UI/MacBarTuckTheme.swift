import AppKit
import SwiftUI

enum MacBarTuckTheme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let chrome = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let raisedSurface = Color.white.opacity(0.045)
    static let deepSurface = Color.black.opacity(0.14)
    static let traySurface = Color(red: 0.075, green: 0.090, blue: 0.105).opacity(0.98)
    static let trayStroke = Color(red: 0.34, green: 0.68, blue: 0.73).opacity(0.34)
    static let stroke = Color.white.opacity(0.09)
    static let strongStroke = Color.white.opacity(0.16)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let accent = Color(red: 0.34, green: 0.68, blue: 0.73)
    static let accentStrong = accent
    static let success = Color(red: 0.35, green: 0.84, blue: 0.59)
    static let retuckAction = Color(red: 0.98, green: 0.68, blue: 0.22)
    static let warning = Color(red: 1.00, green: 0.43, blue: 0.38)
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = item.menuBarImage {
                Image(nsImage: image)
                    .renderingMode(item.usesTemplateMenuBarIcon ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(item.usesTemplateMenuBarIcon && colorScheme == .dark ? MacBarTuckTheme.primaryText : Color.primary)
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
        case .alwaysHidden: MacBarTuckTheme.warning
        }
    }
}

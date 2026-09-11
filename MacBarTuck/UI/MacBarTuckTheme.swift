import SwiftUI

enum MacBarTuckTheme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let chrome = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let raisedSurface = Color.white.opacity(0.045)
    static let deepSurface = Color.black.opacity(0.14)
    static let stroke = Color.white.opacity(0.09)
    static let strongStroke = Color.white.opacity(0.16)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let accent = Color(red: 0.34, green: 0.68, blue: 0.73)
    static let accentStrong = accent
    static let success = Color(red: 0.35, green: 0.84, blue: 0.59)
    static let warning = Color(red: 1.00, green: 0.43, blue: 0.38)
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
            if let image = item.displayImage {
                Image(nsImage: image)
                    .renderingMode(item.usesTemplateIcon ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(item.usesTemplateIcon && colorScheme == .dark ? MacBarTuckTheme.primaryText : Color.primary)
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
        switch self {
        case .automatic: "自动"
        case .alwaysVisible: "常显"
        case .alwaysHidden: "收纳"
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

import SwiftUI

enum BarTuckTheme {
    static let canvas = Color(red: 0.035, green: 0.042, blue: 0.047)
    static let chrome = Color(red: 0.052, green: 0.061, blue: 0.067)
    static let surface = Color(red: 0.070, green: 0.080, blue: 0.086)
    static let raisedSurface = Color(red: 0.086, green: 0.098, blue: 0.105)
    static let deepSurface = Color(red: 0.024, green: 0.030, blue: 0.034)
    static let stroke = Color.white.opacity(0.09)
    static let strongStroke = Color.white.opacity(0.16)
    static let primaryText = Color(red: 0.94, green: 0.96, blue: 0.97)
    static let secondaryText = Color(red: 0.61, green: 0.66, blue: 0.69)
    static let accent = Color(red: 0.18, green: 0.78, blue: 0.88)
    static let accentStrong = Color(red: 0.31, green: 0.91, blue: 0.98)
    static let success = Color(red: 0.35, green: 0.84, blue: 0.59)
    static let warning = Color(red: 1.00, green: 0.43, blue: 0.38)
}

struct BarTuckSurface<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(BarTuckTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BarTuckTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct BarTuckSectionTitle: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BarTuckTheme.primaryText)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(BarTuckTheme.secondaryText)
            }
            Spacer()
        }
    }
}

struct BarTuckStatusPill: View {
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
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().stroke(color.opacity(0.24), lineWidth: 1)
        }
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
                    .foregroundStyle(item.usesTemplateIcon && colorScheme == .dark ? BarTuckTheme.primaryText : Color.primary)
            } else {
                Image(systemName: item.fallbackSymbolName)
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(BarTuckTheme.primaryText)
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
        case .automatic: BarTuckTheme.accent
        case .alwaysVisible: BarTuckTheme.success
        case .alwaysHidden: BarTuckTheme.warning
        }
    }
}

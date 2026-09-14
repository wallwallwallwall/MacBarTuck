import SwiftUI

struct OverflowItemView: View {
    let item: MenuBarItem
    let isTemporarilyVisible: Bool
    let action: () -> Void
    let rightAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var language: AppLanguageController
    @State private var isHovering = false

    private var iconSize: CGFloat {
        item.usesApplicationIconForDisplay ? 26 : 20
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let image = item.displayImage {
                    Image(nsImage: image)
                        .renderingMode(item.usesTemplateIcon ? .template : .original)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(item.usesTemplateIcon && colorScheme == .dark ? Color.white : Color.primary)
                }
                else {
                    Image(systemName: item.fallbackSymbolName)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                        .opacity(0.78)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .frame(width: 32, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? MacBarTuckTheme.accent.opacity(0.18) : Color.clear)
            }
        }
        .buttonStyle(OverflowItemButtonStyle(reduceMotion: reduceMotion))
        .overlay(alignment: .bottomTrailing) {
            if isTemporarilyVisible {
                Circle()
                    .fill(MacBarTuckTheme.accentStrong)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(MacBarTuckTheme.deepSurface, lineWidth: 1))
                    .offset(x: -5, y: -5)
                    .allowsHitTesting(false)
            }
        }
        .overlay { RightClickCaptureView(action: rightAction) }
        .frame(width: OverflowPanelView.itemSlotWidth, height: 36)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .help(isTemporarilyVisible
              ? "\(item.tooltip(for: language.selectedLanguage)) · \(language.text("panel.temporary.help"))"
              : item.tooltip(for: language.selectedLanguage))
        .accessibilityLabel(item.tooltip(for: language.selectedLanguage))
    }
}

private struct RightClickCaptureView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.action = action
    }
}

private final class RightClickView: NSView {
    var action: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown || event.type == .rightMouseUp else { return nil }
        return self
    }

    override func rightMouseDown(with event: NSEvent) { action?() }
}

private struct OverflowItemButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}

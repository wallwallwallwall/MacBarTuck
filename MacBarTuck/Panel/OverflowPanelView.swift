import SwiftUI

@MainActor
final class OverflowPanelPresentationState: ObservableObject {
    @Published var isPresented: Bool

    init(isPresented: Bool = false) {
        self.isPresented = isPresented
    }
}

struct OverflowPanelView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var presentation: OverflowPanelPresentationState
    let onActivate: (MenuBarItem) -> Void
    let onRightActivate: (MenuBarItem) -> Void
    let onRetuck: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var language: AppLanguageController

    static let preferredHeight: CGFloat = 56

    static let itemSlotWidth: CGFloat = 44
    private static let itemSpacing: CGFloat = 2
    private static let baseChromeWidth: CGFloat = 65
    private static let retuckButtonWidth: CGFloat = 114
    private static let retuckChromeWidth: CGFloat = retuckButtonWidth + 11

    static func preferredWidth(itemCount: Int, showsRetuck: Bool) -> CGFloat {
        let count = max(0, itemCount)
        let itemWidth = CGFloat(count) * itemSlotWidth
        let spacingWidth = CGFloat(max(0, count - 1)) * itemSpacing
        return max(itemWidth + spacingWidth + baseChromeWidth + (showsRetuck ? retuckChromeWidth : 0), 154)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if presentation.isPresented {
                panelSurface
                    .transition(panelTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(panelAnimation, value: presentation.isPresented)
    }

    private var panelSurface: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacBarTuckTheme.accentStrong)
                .frame(width: 34, height: 34)
                .background(MacBarTuckTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help(language.text("panel.help"))

            Rectangle()
                .fill(MacBarTuckTheme.strongStroke)
                .frame(width: 1, height: 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.itemSpacing) {
                    if store.overflowItems.isEmpty {
                        Text(store.selectedItems.isEmpty ? language.text("panel.empty") : language.text("panel.not_hidden"))
                            .font(.system(size: 11))
                            .foregroundStyle(MacBarTuckTheme.secondaryText)
                            .padding(.horizontal, 10)
                    }
                    ForEach(store.overflowItems) { item in
                        OverflowItemView(
                            item: item,
                            isTemporarilyVisible: store.isTemporarilyVisible(item),
                            action: { onActivate(item) },
                            rightAction: { onRightActivate(item) }
                        )
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollBounceBehavior(.basedOnSize)

            if !store.temporarilyVisibleItems.isEmpty {
                Rectangle()
                    .fill(MacBarTuckTheme.strongStroke)
                    .frame(width: 1, height: 28)

                Button(action: onRetuck) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(language.text("panel.retuck.count", store.temporarilyVisibleItems.count))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(width: Self.retuckButtonWidth, height: 34)
                    .background(MacBarTuckTheme.retuckAction, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .help(language.text("panel.retuck"))
                .accessibilityLabel(language.text("panel.retuck.count", store.temporarilyVisibleItems.count))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: Self.preferredHeight - 6)
        .background(.ultraThinMaterial)
        .background(MacBarTuckTheme.deepSurface.opacity(0.90))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MacBarTuckTheme.accent.opacity(0.42), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(3)
    }

    private var panelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .offset(y: -2))
    }

    private var panelAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.08 : 0.12)
    }
}

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

    static let preferredHeight = MacBarTuckTrayLayout.preferredHeight

    static let itemSlotWidth = MacBarTuckTrayLayout.itemSlotWidth
    private static let itemSpacing = MacBarTuckTrayLayout.itemSpacing
    private static let summaryWidth = MacBarTuckTrayLayout.summaryWidth
    private static let retuckButtonWidth = MacBarTuckTrayLayout.retuckButtonWidth

    static func preferredWidth(itemCount: Int, showsRetuck: Bool) -> CGFloat {
        MacBarTuckTrayLayout.preferredWidth(itemCount: itemCount, showsRetuck: showsRetuck)
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
            Label(language.text("panel.tucked.count", tuckedItemCount), systemImage: "rectangle.stack.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacBarTuckTheme.accentStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: Self.summaryWidth, height: 32)
                .background(MacBarTuckTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help(language.text("panel.help"))
                .accessibilityLabel(language.text("panel.tucked.count", tuckedItemCount))

            Rectangle()
                .fill(MacBarTuckTheme.strongStroke)
                .frame(width: 1, height: 24)

            ViewThatFits(in: .horizontal) {
                itemRow
                    .fixedSize(horizontal: true, vertical: false)

                ScrollView(.horizontal, showsIndicators: false) {
                    itemRow
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .clipShape(Rectangle())
            }

            if !store.temporarilyVisibleItems.isEmpty {
                Rectangle()
                    .fill(MacBarTuckTheme.strongStroke)
                    .frame(width: 1, height: 24)

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
                    .frame(width: Self.retuckButtonWidth, height: 32)
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
        .background(MacBarTuckTheme.traySurface)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MacBarTuckTheme.trayStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(3)
    }

    private var tuckedItemCount: Int {
        store.overflowItems.filter { !store.isTemporarilyVisible($0) }.count
    }

    private var itemRow: some View {
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
        .padding(.vertical, 2)
    }

    private var panelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .offset(y: -2))
    }

    private var panelAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.08 : 0.12)
    }
}

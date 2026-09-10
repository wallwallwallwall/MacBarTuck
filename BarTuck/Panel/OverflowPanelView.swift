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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let preferredHeight: CGFloat = 50

    static let itemSlotWidth: CGFloat = 38

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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BarTuckTheme.accentStrong)
                .frame(width: 30, height: 30)
                .background(BarTuckTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help("BarTuck 托盘")

            Rectangle()
                .fill(BarTuckTheme.strongStroke)
                .frame(width: 1, height: 23)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    if store.overflowItems.isEmpty {
                        Text(store.selectedItems.isEmpty ? "没有已收起的项目" : "尚未成功收起")
                            .font(.system(size: 11))
                            .foregroundStyle(BarTuckTheme.secondaryText)
                            .padding(.horizontal, 10)
                    }
                    ForEach(store.overflowItems) { item in
                        OverflowItemView(item: item, action: { onActivate(item) }, rightAction: { onRightActivate(item) })
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 7)
        .frame(height: Self.preferredHeight - 6)
        .background(.ultraThinMaterial)
        .background(BarTuckTheme.deepSurface.opacity(0.90))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BarTuckTheme.accent.opacity(0.42), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(3)
    }

    private var panelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .top))
                .combined(with: .offset(y: -5)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .combined(with: .offset(y: -3))
        )
    }

    private var panelAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.3, dampingFraction: 0.82, blendDuration: 0.08)
    }
}

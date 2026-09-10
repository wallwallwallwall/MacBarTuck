import SwiftUI

struct OverflowPanelPreviewView: View {
    @ObservedObject var store: MenuBarItemStore
    @StateObject private var presentation = OverflowPanelPresentationState(isPresented: true)

    private var panelWidth: CGFloat {
        max(CGFloat(store.overflowItems.count) * OverflowPanelView.itemSlotWidth + 58, 154)
    }

    var body: some View {
        ZStack {
            BarTuckTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(BarTuckTheme.warning)
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(BarTuckTheme.success)
                        .frame(width: 7, height: 7)
                    Text("安全预览")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(BarTuckTheme.secondaryText)
                    Spacer()
                    Label("不创建菜单栏项目", systemImage: "shield.checkered")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BarTuckTheme.success)
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(BarTuckTheme.chrome)

                Spacer()

                VStack(spacing: 11) {
                    Text("托盘会在当前操作的屏幕、菜单栏下方展开")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BarTuckTheme.secondaryText)

                    OverflowPanelView(
                        store: store,
                        presentation: presentation,
                        onActivate: { _ in },
                        onRightActivate: { _ in }
                    )
                    .frame(width: panelWidth, height: OverflowPanelView.preferredHeight)
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

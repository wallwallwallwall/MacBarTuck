import SwiftUI

struct OverflowPanelPreviewView: View {
    @ObservedObject var store: MenuBarItemStore
    @StateObject private var presentation = OverflowPanelPresentationState(isPresented: true)
    @EnvironmentObject private var language: AppLanguageController

    private var panelWidth: CGFloat {
        OverflowPanelView.preferredWidth(
            itemCount: store.overflowItems.count,
            showsRetuck: !store.temporarilyVisibleItems.isEmpty
        )
    }

    var body: some View {
        ZStack {
            MacBarTuckTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(MacBarTuckTheme.warning)
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(MacBarTuckTheme.success)
                        .frame(width: 7, height: 7)
                    Text(language.text("preview.safe"))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MacBarTuckTheme.secondaryText)
                    Spacer()
                    Label(language.text("preview.no_status_item"), systemImage: "shield.checkered")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacBarTuckTheme.success)
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background(MacBarTuckTheme.chrome)

                Spacer()

                VStack(spacing: 11) {
                    Text(language.text("preview.panel_location"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacBarTuckTheme.secondaryText)

                    OverflowPanelView(
                        store: store,
                        presentation: presentation,
                        onActivate: { _ in },
                        onRightActivate: { _ in },
                        onRetuck: {}
                    )
                    .frame(width: panelWidth, height: OverflowPanelView.preferredHeight)
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

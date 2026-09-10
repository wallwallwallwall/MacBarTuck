import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    let showOnboarding: () -> Void

    @StateObject private var permissions = PermissionManager()
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @AppStorage("hoverRevealEnabled") private var hoverRevealEnabled = true
    @State private var selectedTab: SettingsTab

    init(store: MenuBarItemStore, showOnboarding: @escaping () -> Void = {}) {
        self.store = store
        self.showOnboarding = showOnboarding
        _selectedTab = State(initialValue: SettingsTab.previewSelection)
    }

    var body: some View {
        ZStack {
            BarTuckTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(BarTuckTheme.stroke)
                tabs
                Divider().overlay(BarTuckTheme.stroke)
                content
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .preferredColorScheme(.dark)
        .onAppear {
            permissions.refresh()
            launchAtLogin.refresh()
            store.refresh()
        }
        .alert(
            "BarTuck",
            isPresented: Binding(
                get: { store.lastActivationError != nil },
                set: { if !$0 { store.lastActivationError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { store.lastActivationError = nil }
        } message: {
            Text(store.lastActivationError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BarTuckTheme.accentStrong)
                .frame(width: 30, height: 30)
                .background(BarTuckTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(BarTuckTheme.accent.opacity(0.24), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text("BarTuck")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BarTuckTheme.primaryText)
                Text("菜单栏空间控制")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BarTuckTheme.secondaryText)
            }

            Spacer()

            BarTuckStatusPill(
                title: "\(store.displays.count) 块屏幕",
                color: BarTuckTheme.accent,
                systemImage: "display.2"
            )
            BarTuckStatusPill(
                title: store.layoutManagementEnabled ? "运行中" : "未启用布局",
                color: store.layoutManagementEnabled ? BarTuckTheme.success : BarTuckTheme.warning,
                systemImage: store.layoutManagementEnabled ? "bolt.circle.fill" : "pause.circle.fill"
            )
        }
        .padding(.leading, 78)
        .padding(.trailing, 18)
        .padding(.top, 10)
        .frame(height: 58)
        .background(BarTuckTheme.chrome)
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? BarTuckTheme.accentStrong : BarTuckTheme.secondaryText)
                        .frame(width: 104, height: 28)
                        .background(selectedTab == tab ? BarTuckTheme.accent.opacity(0.12) : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(selectedTab == tab ? BarTuckTheme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let message = store.iconCaptureMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(BarTuckTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 45)
        .background(BarTuckTheme.chrome)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .status:
            StatusSettingsView(store: store, permissions: permissions)
        case .items:
            ItemsSettingsView(store: store)
        case .preferences:
            PreferencesSettingsView(
                store: store,
                launchAtLogin: launchAtLogin,
                hoverRevealEnabled: $hoverRevealEnabled,
                showOnboarding: showOnboarding
            )
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case status
    case items
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "状态"
        case .items: "项目"
        case .preferences: "偏好"
        }
    }

    var symbolName: String {
        switch self {
        case .status: "waveform.path.ecg"
        case .items: "list.bullet.rectangle"
        case .preferences: "slider.horizontal.3"
        }
    }

    static var previewSelection: SettingsTab {
        let prefix = "--ui-preview-tab="
        guard let value = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count) else { return .status }
        return SettingsTab(rawValue: String(value)) ?? .status
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var dockVisibility: DockVisibilityController
    let showOnboarding: () -> Void

    @StateObject private var permissions = PermissionManager()
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @AppStorage("hoverRevealEnabled") private var hoverRevealEnabled = true
    @State private var previewHoverEnabled = true
    @State private var selectedTab: SettingsTab

    init(store: MenuBarItemStore, dockVisibility: DockVisibilityController, showOnboarding: @escaping () -> Void = {}) {
        self.store = store
        self.dockVisibility = dockVisibility
        self.showOnboarding = showOnboarding
        _selectedTab = State(initialValue: SettingsTab.previewSelection)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("页面", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
                Spacer()
                Toggle("启用收纳", isOn: Binding(
                    get: { store.layoutManagementEnabled },
                    set: { store.setLayoutManagementEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("收起所选的菜单栏项目")
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.system(size: 13))
        .tint(BarTuckTheme.accent)
        .background(BarTuckTheme.canvas)
        .frame(minWidth: 760, minHeight: 560)
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .alert("无法打开菜单项", isPresented: Binding(
            get: { store.lastActivationError != nil },
            set: { if !$0 { store.lastActivationError = nil } }
        )) {
            Button("好", role: .cancel) { store.lastActivationError = nil }
        } message: { Text(store.lastActivationError ?? "") }
    }

    private func refresh() {
        permissions.refresh()
        launchAtLogin.refresh()
        store.refresh()
    }

    @ViewBuilder private var content: some View {
        switch selectedTab {
        case .items:
            ItemsSettingsView(store: store, openPermissions: { selectedTab = .status })
        case .preferences:
            PreferencesSettingsView(store: store, launchAtLogin: launchAtLogin, dockVisibility: dockVisibility,
                hoverRevealEnabled: store.isUIPreviewMode ? $previewHoverEnabled : $hoverRevealEnabled,
                showOnboarding: showOnboarding)
        case .status:
            StatusSettingsView(store: store, permissions: permissions)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case items, preferences, status
    var id: String { rawValue }
    var title: String {
        switch self {
        case .items: "菜单项"
        case .preferences: "通用"
        case .status: "权限与显示器"
        }
    }
    static var previewSelection: SettingsTab {
        let prefix = "--ui-preview-tab="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return .items }
        return SettingsTab(rawValue: String(argument.dropFirst(prefix.count))) ?? .items
    }
}

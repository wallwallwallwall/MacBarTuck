import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var dockVisibility: DockVisibilityController
    let showOnboarding: () -> Void

    @EnvironmentObject private var language: AppLanguageController
    @ObservedObject private var permissions: PermissionManager
    private let restartApplication: () -> Void
    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @AppStorage("hoverRevealEnabled") private var hoverRevealEnabled = true
    @State private var previewHoverEnabled = true
    @State private var selectedTab: SettingsTab

    init(store: MenuBarItemStore, dockVisibility: DockVisibilityController,
         restartApplication: @escaping () -> Void = {}, showOnboarding: @escaping () -> Void = {}) {
        self.store = store
        self.dockVisibility = dockVisibility
        self.permissions = store.permissions
        self.restartApplication = restartApplication
        self.showOnboarding = showOnboarding
        _selectedTab = State(initialValue: SettingsTab.previewSelection)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(language.text("settings.page"), selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in Text(tab.title(language)).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
                Spacer()
                Button { selectedTab = .status } label: {
                    Label(store.isUIPreviewMode ? language.text("settings.permission.example") : permissions.statusTitle,
                          systemImage: permissions.isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(permissions.isReady ? Color.green : Color.orange)
                }
                .buttonStyle(.plain).font(.system(size: 11))
                .help(permissions.statusDetail)
                Toggle(language.text("settings.collection.enabled"), isOn: Binding(
                    get: { store.layoutManagementEnabled },
                    set: { value in
                        store.setLayoutManagementEnabled(value)
                        if value && !store.isUIPreviewMode && !permissions.isReady { selectedTab = .status }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(language.text("settings.collection.help"))
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.system(size: 13))
        .tint(MacBarTuckTheme.accent)
        .background(MacBarTuckTheme.canvas)
        .frame(minWidth: 760, minHeight: 560)
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: permissions.effectiveAccessKey) { _, _ in store.refresh() }
        .alert("MacBarTuck", isPresented: Binding(
            get: { store.lastActivationError != nil },
            set: { if !$0 { store.lastActivationError = nil } }
        )) {
            Button(language.text("common.ok"), role: .cancel) { store.lastActivationError = nil }
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
            StatusSettingsView(store: store, permissions: permissions, restartApplication: restartApplication)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case items, preferences, status
    var id: String { rawValue }
    func title(_ language: AppLanguageController) -> String {
        switch self {
        case .items: language.text("settings.tab.items")
        case .preferences: language.text("settings.tab.general")
        case .status: language.text("settings.tab.permissions")
        }
    }
    static var previewSelection: SettingsTab {
        let prefix = "--ui-preview-tab="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return .items }
        return SettingsTab(rawValue: String(argument.dropFirst(prefix.count))) ?? .items
    }
}

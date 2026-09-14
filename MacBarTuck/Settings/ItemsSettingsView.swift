import SwiftUI

struct ItemsSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    var openPermissions: () -> Void = {}
    @State private var query = ""
    @EnvironmentObject private var language: AppLanguageController

    private var filteredItems: [MenuBarItem] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return store.items }
        return store.items.filter {
            $0.title.localizedCaseInsensitiveContains(value) ||
            $0.ownerName.localizedCaseInsensitiveContains(value) ||
            $0.displayTitle(for: language.selectedLanguage).localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(language.text("items.search"), text: $query).textFieldStyle(.plain)
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .opacity(query.isEmpty ? 0 : 1).disabled(query.isEmpty)
                        .help(language.text("items.search.clear")).accessibilityLabel(language.text("items.search.clear"))
                }
                .padding(.horizontal, 8).frame(width: 260, height: 28)
                .background(MacBarTuckTheme.deepSurface, in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Button {
                    store.applyLayout()
                } label: {
                    Label(language.text("items.apply"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.layoutManagementEnabled || store.selectedItems.isEmpty || store.isInteractionBusy)
                .help(language.text("items.apply.help"))
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).frame(width: 28, height: 28)
                    .help(language.text("items.rescan")).accessibilityLabel(language.text("items.rescan"))
                Menu {
                    Button(language.text("items.retuck_temporary", store.temporarilyVisibleItems.count)) {
                        store.retuckTemporarilyVisibleItems()
                    }
                    .disabled(store.temporarilyVisibleItems.isEmpty)
                    Button(language.text("items.all_automatic")) { store.resetRulesToAutomatic() }
                        .disabled(store.items.isEmpty)
                    Button(language.text("items.show_all")) { store.setLayoutManagementEnabled(false) }
                        .disabled(!store.layoutManagementEnabled)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .help(language.text("items.more")).accessibilityLabel(language.text("items.more"))
            }
            .padding(.horizontal, 20).frame(height: 52)

            if store.requiresScreenRecording {
                emptyState(language.text("items.recording_required"), symbol: "lock.shield") {
                    Button(language.text("items.view_permissions"), action: openPermissions)
                }
            } else if filteredItems.isEmpty {
                emptyState(query.isEmpty ? language.text("items.empty") : language.text("items.no_matches"), symbol: "menubar.rectangle") {
                    if !query.isEmpty { Button(language.text("items.search.clear")) { query = "" } }
                }
            } else {
                Table(filteredItems) {
                    TableColumn(language.text("items.column.item")) { item in
                        HStack(spacing: 10) {
                            MenuItemIconView(item: item, size: 20).frame(width: 28)
                            Text(item.displayTitle(for: language.selectedLanguage)).lineLimit(1)
                            if item.windowID != nil && item.iconImage == nil {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                                    .help(language.text("items.icon.pending"))
                            }
                        }
                        .frame(height: 34)
                        .help(item.tooltip(for: language.selectedLanguage))
                    }
                    TableColumn(language.text("items.column.mode")) { item in
                        if item.isAlwaysVisibleSystemItem {
                            Label(language.text("items.system_reserved"), systemImage: "lock")
                                .foregroundStyle(.secondary).help(language.text("items.system_reserved.help"))
                        } else {
                            Picker(language.text("items.mode.label", item.displayTitle(for: language.selectedLanguage)), selection: Binding(
                                get: { item.rule }, set: { store.setRule($0, for: item) }
                            )) {
                                Text(language.text("items.mode.automatic")).tag(MenuItemRule.automatic)
                                Text(language.text("items.mode.visible")).tag(MenuItemRule.alwaysVisible)
                                Text(language.text("items.mode.hidden")).tag(MenuItemRule.alwaysHidden)
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 128)
                        }
                    }.width(150)
                    TableColumn(language.text("items.column.status")) { item in
                        Text(store.visibilityDescription(for: item))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.width(104)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            HStack {
                Text(store.isUIPreviewMode
                     ? language.text("items.footer.preview", filteredItems.count)
                     : (store.requiresScreenRecording
                        ? language.text("items.footer.waiting")
                        : language.text("items.footer.count", filteredItems.count)))
                Spacer()
                if let message = store.layoutOperationMessage {
                    Text(message).lineLimit(1).help(message)
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).frame(height: 30)
        }
    }

    private func emptyState<Actions: View>(_ title: String, symbol: String,
                                           @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 15))
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

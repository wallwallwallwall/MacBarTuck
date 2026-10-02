import SwiftUI

struct ItemsSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    var openPermissions: () -> Void = {}
    @State private var query = ""
    @State private var filter: MenuBarItemFilter = .all
    @FocusState private var searchIsFocused: Bool
    @EnvironmentObject private var language: AppLanguageController

    private var hasFilters: Bool {
        filter != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let groups = store.matchingItemGroups(query: query)
        let filteredItems = groups[filter, default: []]
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Button { searchIsFocused = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut("f", modifiers: .command)
                    .help(language.text("items.search"))
                    .accessibilityLabel(language.text("items.search"))
                    TextField(language.text("items.search"), text: $query).textFieldStyle(.plain)
                        .focused($searchIsFocused)
                        .onExitCommand {
                            if query.isEmpty { searchIsFocused = false } else { query = "" }
                        }
                        .accessibilityLabel(language.text("items.search"))
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .opacity(query.isEmpty ? 0 : 1).disabled(query.isEmpty)
                        .help(language.text("items.search.clear")).accessibilityLabel(language.text("items.search.clear"))
                }
                .padding(.horizontal, 10).frame(width: 260, height: 32)
                .background(MacBarTuckTheme.deepSurface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(MacBarTuckTheme.stroke))
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
            .padding(.horizontal, 20).frame(height: 58)

            Picker(language.text("items.filter.label"), selection: $filter) {
                ForEach(MenuBarItemFilter.allCases) { option in
                    Text(language.text(option.localizationKey,
                        groups[option, default: []].count))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("item-status-filter")
            .padding(.horizontal, 20).padding(.bottom, 12)

            if store.requiresScreenRecording {
                emptyState(language.text("items.recording_required"), symbol: "lock.shield") {
                    Button(language.text("items.view_permissions"), action: openPermissions)
                }
            } else if filteredItems.isEmpty {
                emptyState(hasFilters ? language.text("items.no_matches") : language.text("items.empty"), symbol: "menubar.rectangle") {
                    if hasFilters {
                        Button(language.text("items.filter.reset")) { query = ""; filter = .all }
                    }
                }
            } else {
                Table(filteredItems) {
                    TableColumn(language.text("items.favorite.column")) { item in
                        Button { store.toggleFavorite(item) } label: {
                            Image(systemName: store.isFavorite(item) ? "star.fill" : "star")
                                .foregroundStyle(store.isFavorite(item) ? MacBarTuckTheme.retuckAction : MacBarTuckTheme.secondaryText)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help(language.text(store.isFavorite(item) ? "items.favorite.remove" : "items.favorite.add"))
                        .accessibilityLabel(language.text(store.isFavorite(item) ? "items.favorite.remove_item" : "items.favorite.add_item",
                            item.displayTitle(for: language.selectedLanguage)))
                        .accessibilityIdentifier("favorite-\(item.id)")
                    }.width(42)
                    TableColumn(language.text("items.column.item")) { item in
                        HStack(spacing: 10) {
                            MenuItemIconView(item: item, size: 28, prefersApplicationIcon: true).frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayTitle(for: language.selectedLanguage)).lineLimit(1)
                                if !item.showsNotificationCountInTitle &&
                                    item.displayOwnerName(for: language.selectedLanguage) != item.displayTitle(for: language.selectedLanguage) {
                                    Text(item.displayOwnerName(for: language.selectedLanguage))
                                        .font(.system(size: 11)).foregroundStyle(MacBarTuckTheme.secondaryText).lineLimit(1)
                                }
                            }
                            if item.windowID != nil && item.iconImage == nil {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                                    .help(language.text("items.icon.pending"))
                            }
                        }
                        .frame(height: 48)
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
                        Label(store.visibilityDescription(for: item), systemImage: statusSymbol(for: item))
                            .font(.system(size: 11)).foregroundStyle(statusColor(for: item))
                            .lineLimit(2)
                    }.width(168)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
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
            .padding(.horizontal, 20).frame(height: 34)
            .background(MacBarTuckTheme.chrome)
        }
    }

    private func statusColor(for item: MenuBarItem) -> Color {
        if store.isTemporarilyVisible(item) { return MacBarTuckTheme.retuckAction }
        if item.visibility == .hidden { return MacBarTuckTheme.collected }
        if item.visibility == .visible && !item.isSelected { return MacBarTuckTheme.success }
        return MacBarTuckTheme.secondaryText
    }

    private func statusSymbol(for item: MenuBarItem) -> String {
        if store.isTemporarilyVisible(item) { return "clock" }
        if item.visibility == .hidden { return "tray.fill" }
        if item.visibility == .visible && !item.isSelected { return "eye" }
        return "ellipsis.circle"
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

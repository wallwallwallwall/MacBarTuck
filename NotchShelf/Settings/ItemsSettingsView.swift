import SwiftUI

struct ItemsSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @State private var query = ""

    private var filteredItems: [MenuBarItem] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return store.items }
        return store.items.filter {
            $0.title.localizedCaseInsensitiveContains(value) ||
                $0.ownerName.localizedCaseInsensitiveContains(value) ||
                $0.displayTitle.localizedCaseInsensitiveContains(value) ||
                $0.displayOwnerName.localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            itemList
            legend
        }
        .padding(18)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                TextField("搜索应用或菜单项", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(NotchShelfTheme.deepSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(NotchShelfTheme.stroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            NotchShelfStatusPill(
                title: "\(filteredItems.count) 项",
                color: NotchShelfTheme.accent,
                systemImage: "menubar.rectangle"
            )

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("重新扫描菜单栏")

            Button("全部自动") {
                store.resetRulesToAutomatic()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.items.isEmpty)
        }
    }

    private var itemList: some View {
        NotchShelfSurface(padding: 0) {
            Group {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "未发现菜单栏项目" : "没有匹配项目",
                        systemImage: "menubar.rectangle",
                        description: Text(query.isEmpty ? "授权辅助功能后重新扫描。" : "换一个关键词试试。")
                    )
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                itemRow(item)
                                if index < filteredItems.count - 1 {
                                    Divider().overlay(NotchShelfTheme.stroke).padding(.leading, 58)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func itemRow(_ item: MenuBarItem) -> some View {
        HStack(spacing: 12) {
            MenuItemIconView(item: item, size: 24)
                .frame(width: 34, height: 34)
                .background(NotchShelfTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.displayTitle.isEmpty ? item.displayOwnerName : item.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchShelfTheme.primaryText)
                        .lineLimit(1)
                    if item.isProtectedSystemItem {
                        NotchShelfStatusPill(
                            title: item.isAlwaysVisibleSystemItem ? "安全状态" : "系统控件",
                            color: item.isAlwaysVisibleSystemItem ? NotchShelfTheme.warning : NotchShelfTheme.accent
                        )
                    }
                }
                Text(item.displayOwnerName)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: item.activationStatusSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(item.windowID != nil || item.supportsPressAction ? NotchShelfTheme.success : NotchShelfTheme.warning)
                .frame(width: 22)
                .help(item.activationStatusHelp)

            if item.isAlwaysVisibleSystemItem {
                NotchShelfStatusPill(
                    title: "强制常显",
                    color: NotchShelfTheme.warning,
                    systemImage: "lock.fill"
                )
                .frame(width: 218, alignment: .trailing)
            } else {
                RuleSegmentedControl(selection: item.rule) { rule in
                    store.setRule(rule, for: item)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("自动：按刘海安全宽度收纳", systemImage: "wand.and.stars")
            Label("常显：始终留在菜单栏", systemImage: "eye.fill")
            Label("收纳：始终放入托盘", systemImage: "tray.full.fill")
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(NotchShelfTheme.secondaryText)
    }
}

private struct RuleSegmentedControl: View {
    let selection: MenuItemRule
    let onSelect: (MenuItemRule) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MenuItemRule.allCases, id: \.self) { rule in
                Button {
                    onSelect(rule)
                } label: {
                    Label(rule.localizedTitle, systemImage: rule.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 25)
                        .foregroundStyle(selection == rule ? rule.tint : NotchShelfTheme.secondaryText)
                        .background(selection == rule ? rule.tint.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(rule.localizedTitle)
            }
        }
        .padding(2)
        .frame(width: 218, height: 31)
        .background(NotchShelfTheme.deepSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(NotchShelfTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

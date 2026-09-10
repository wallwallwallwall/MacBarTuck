import SwiftUI

struct ItemsSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    var openPermissions: () -> Void = {}
    @State private var query = ""

    private var filteredItems: [MenuBarItem] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return store.items }
        return store.items.filter {
            $0.title.localizedCaseInsensitiveContains(value) ||
            $0.ownerName.localizedCaseInsensitiveContains(value) ||
            $0.displayTitle.localizedCaseInsensitiveContains(value)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索菜单项", text: $query).textFieldStyle(.plain)
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .opacity(query.isEmpty ? 0 : 1).disabled(query.isEmpty)
                        .help("清除搜索").accessibilityLabel("清除搜索")
                }
                .padding(.horizontal, 8).frame(width: 260, height: 28)
                .background(BarTuckTheme.deepSurface, in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).frame(width: 28, height: 28)
                    .help("重新扫描").accessibilityLabel("重新扫描")
                Menu {
                    Button("全部设为自动") { store.resetRulesToAutomatic() }
                        .disabled(store.items.isEmpty)
                    Button("全部显示") { store.setLayoutManagementEnabled(false) }
                        .disabled(!store.layoutManagementEnabled)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28).help("更多操作").accessibilityLabel("更多操作")
            }
            .padding(.horizontal, 20).frame(height: 52)

            if store.requiresScreenRecording {
                emptyState("需要屏幕录制权限", symbol: "lock.shield") {
                    Button("查看权限", action: openPermissions)
                }
            } else if filteredItems.isEmpty {
                emptyState(query.isEmpty ? "暂无菜单项" : "没有匹配的菜单项", symbol: "menubar.rectangle") {
                    if !query.isEmpty { Button("清除搜索") { query = "" } }
                }
            } else {
                Table(filteredItems) {
                    TableColumn("菜单项") { item in
                        HStack(spacing: 10) {
                            MenuItemIconView(item: item, size: 20).frame(width: 28)
                            Text(item.displayTitle).lineLimit(1)
                            if item.windowID != nil && item.iconImage == nil {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                                    .help("图标尚未读取")
                            }
                        }
                        .frame(height: 34)
                        .help(item.tooltip)
                    }
                    TableColumn("显示方式") { item in
                        if item.isAlwaysVisibleSystemItem {
                            Label("系统保留", systemImage: "lock")
                                .foregroundStyle(.secondary).help("此项目保持显示")
                        } else {
                            Picker("\(item.displayTitle)的显示方式", selection: Binding(
                                get: { item.rule }, set: { store.setRule($0, for: item) }
                            )) {
                                Text("自动").tag(MenuItemRule.automatic)
                                Text("始终显示").tag(MenuItemRule.alwaysVisible)
                                Text("收起").tag(MenuItemRule.alwaysHidden)
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 128)
                        }
                    }.width(150)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            Divider()
            HStack {
                Text(store.isUIPreviewMode ? "界面预览 · \(filteredItems.count) 个示例" : (store.requiresScreenRecording ? "等待授权" : "\(filteredItems.count) 个菜单项"))
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

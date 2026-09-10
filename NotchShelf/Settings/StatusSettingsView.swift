import SwiftUI

struct StatusSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overview
                displays
                permissionsSection
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 12) {
            NotchShelfSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("实时托盘")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NotchShelfTheme.primaryText)
                            Text("点击菜单栏的层叠图标即可展开")
                                .font(.system(size: 11))
                                .foregroundStyle(NotchShelfTheme.secondaryText)
                        }
                        Spacer()
                        NotchShelfStatusPill(
                            title: store.layoutManagementEnabled ? "管理中" : "待启用",
                            color: store.layoutManagementEnabled ? NotchShelfTheme.success : NotchShelfTheme.warning,
                            systemImage: store.layoutManagementEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                        )
                    }

                    shelfPreview

                    HStack(spacing: 14) {
                        Label("主屏与扩展屏通用", systemImage: "display.2")
                        Label(store.automaticAvoidanceEnabled ? "自动避让已开启" : "手动规则模式", systemImage: "wand.and.stars")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                }
            }

            NotchShelfSurface(padding: 0) {
                VStack(spacing: 0) {
                    metricRow(symbol: "menubar.rectangle", title: "已发现", value: "\(store.items.count)")
                    Divider().overlay(NotchShelfTheme.stroke)
                    metricRow(symbol: "tray.full.fill", title: "已收纳", value: "\(store.selectedItems.count)")
                    Divider().overlay(NotchShelfTheme.stroke)
                    metricRow(
                        symbol: "ruler",
                        title: "安全宽度",
                        value: store.automaticConstraintWidth.map { "\(Int($0.rounded())) pt" } ?? "无限制"
                    )
                }
            }
            .frame(width: 206)
        }
    }

    private var shelfPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchShelfTheme.accentStrong)
                .frame(width: 28, height: 28)
                .background(NotchShelfTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Rectangle()
                .fill(NotchShelfTheme.strongStroke)
                .frame(width: 1, height: 22)

            if store.overflowItems.isEmpty {
                Text("暂无收纳项目")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(store.overflowItems.prefix(8))) { item in
                    MenuItemIconView(item: item, size: 22)
                        .frame(width: 30, height: 28)
                        .background(NotchShelfTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .help(item.tooltip)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(NotchShelfTheme.deepSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NotchShelfTheme.accent.opacity(0.34), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metricRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchShelfTheme.accent)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(NotchShelfTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(NotchShelfTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 43)
    }

    private var displays: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchShelfSectionTitle("显示器", detail: "自动规则以刘海安全宽度最小的屏幕为准")
            NotchShelfSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(store.displays.enumerated()), id: \.element.id) { index, display in
                        displayRow(display)
                        if index < store.displays.count - 1 {
                            Divider().overlay(NotchShelfTheme.stroke).padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }

    private func displayRow(_ display: DisplaySnapshot) -> some View {
        HStack(spacing: 11) {
            Image(systemName: display.isMain ? "macbook" : "display")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(display.hasNotch ? NotchShelfTheme.accentStrong : NotchShelfTheme.success)
                .frame(width: 30, height: 30)
                .background(NotchShelfTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(display.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchShelfTheme.primaryText)
                    NotchShelfStatusPill(
                        title: display.isMain ? "主屏" : "扩展屏",
                        color: display.isMain ? NotchShelfTheme.accent : NotchShelfTheme.secondaryText
                    )
                }
                Text(display.resolutionLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(display.hasNotch ? "刘海安全区" : "完整菜单栏")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchShelfTheme.secondaryText)
                Text(display.availableMenuWidth.map { "\(Int($0.rounded())) pt" } ?? "不限制")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(display.hasNotch ? NotchShelfTheme.accentStrong : NotchShelfTheme.success)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotchShelfSectionTitle("权限", detail: "仅用于扫描、显示和点击本机菜单栏项目")
            HStack(spacing: 10) {
                permissionCard(
                    symbol: "accessibility",
                    title: "辅助功能",
                    detail: "识别并激活原菜单项",
                    granted: permissions.accessibilityGranted,
                    action: permissions.requestAccessibility
                )
                permissionCard(
                    symbol: "rectangle.inset.filled.and.person.filled",
                    title: "屏幕录制",
                    detail: "只截取菜单栏图标区域",
                    granted: permissions.screenRecordingGranted,
                    action: permissions.openScreenRecordingSettings
                )
            }
        }
    }

    private func permissionCard(
        symbol: String,
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        NotchShelfSurface {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(granted ? NotchShelfTheme.success : NotchShelfTheme.warning)
                    .frame(width: 30, height: 30)
                    .background((granted ? NotchShelfTheme.success : NotchShelfTheme.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotchShelfTheme.primaryText)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchShelfTheme.secondaryText)
                }
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NotchShelfTheme.success)
                } else {
                    Button("去授权", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(NotchShelfTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

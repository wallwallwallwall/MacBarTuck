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
            BarTuckSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("实时托盘")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BarTuckTheme.primaryText)
                            Text("点击菜单栏的层叠图标即可展开")
                                .font(.system(size: 11))
                                .foregroundStyle(BarTuckTheme.secondaryText)
                        }
                        Spacer()
                        BarTuckStatusPill(
                            title: store.layoutManagementEnabled ? "管理中" : "待启用",
                            color: store.layoutManagementEnabled ? BarTuckTheme.success : BarTuckTheme.warning,
                            systemImage: store.layoutManagementEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                        )
                    }

                    shelfPreview

                    HStack(spacing: 14) {
                        Label("主屏与扩展屏通用", systemImage: "display.2")
                        Label(store.automaticAvoidanceEnabled ? "自动避让已开启" : "手动规则模式", systemImage: "wand.and.stars")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BarTuckTheme.secondaryText)
                }
            }

            BarTuckSurface(padding: 0) {
                VStack(spacing: 0) {
                    metricRow(symbol: "menubar.rectangle", title: "已发现", value: "\(store.items.count)")
                    Divider().overlay(BarTuckTheme.stroke)
                    metricRow(symbol: "tray.full.fill", title: "已收纳", value: "\(store.selectedItems.count)")
                    Divider().overlay(BarTuckTheme.stroke)
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
                .foregroundStyle(BarTuckTheme.accentStrong)
                .frame(width: 28, height: 28)
                .background(BarTuckTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Rectangle()
                .fill(BarTuckTheme.strongStroke)
                .frame(width: 1, height: 22)

            if store.overflowItems.isEmpty {
                Text("暂无收纳项目")
                    .font(.system(size: 11))
                    .foregroundStyle(BarTuckTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(store.overflowItems.prefix(8))) { item in
                    MenuItemIconView(item: item, size: 22)
                        .frame(width: 30, height: 28)
                        .background(BarTuckTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .help(item.tooltip)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(BarTuckTheme.deepSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BarTuckTheme.accent.opacity(0.34), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metricRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BarTuckTheme.accent)
                .frame(width: 26)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(BarTuckTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BarTuckTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 43)
    }

    private var displays: some View {
        VStack(alignment: .leading, spacing: 8) {
            BarTuckSectionTitle("显示器", detail: "自动规则以刘海安全宽度最小的屏幕为准")
            BarTuckSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(store.displays.enumerated()), id: \.element.id) { index, display in
                        displayRow(display)
                        if index < store.displays.count - 1 {
                            Divider().overlay(BarTuckTheme.stroke).padding(.leading, 48)
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
                .foregroundStyle(display.hasNotch ? BarTuckTheme.accentStrong : BarTuckTheme.success)
                .frame(width: 30, height: 30)
                .background(BarTuckTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(display.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BarTuckTheme.primaryText)
                    BarTuckStatusPill(
                        title: display.isMain ? "主屏" : "扩展屏",
                        color: display.isMain ? BarTuckTheme.accent : BarTuckTheme.secondaryText
                    )
                }
                Text(display.resolutionLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BarTuckTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(display.hasNotch ? "刘海安全区" : "完整菜单栏")
                    .font(.system(size: 10))
                    .foregroundStyle(BarTuckTheme.secondaryText)
                Text(display.availableMenuWidth.map { "\(Int($0.rounded())) pt" } ?? "不限制")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(display.hasNotch ? BarTuckTheme.accentStrong : BarTuckTheme.success)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BarTuckSectionTitle("权限", detail: "仅用于扫描、显示和点击本机菜单栏项目")
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
        BarTuckSurface {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(granted ? BarTuckTheme.success : BarTuckTheme.warning)
                    .frame(width: 30, height: 30)
                    .background((granted ? BarTuckTheme.success : BarTuckTheme.warning).opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BarTuckTheme.primaryText)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(BarTuckTheme.secondaryText)
                }
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BarTuckTheme.success)
                } else {
                    Button("去授权", action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(BarTuckTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

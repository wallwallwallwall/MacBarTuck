import SwiftUI

struct PreferencesSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @Binding var hoverRevealEnabled: Bool
    let showOnboarding: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                behaviorSection
                operationSection
                aboutSection
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BarTuckSectionTitle("行为", detail: "修改后立即生效")
            BarTuckSurface(padding: 0) {
                VStack(spacing: 0) {
                    preferenceToggle(
                        symbol: "wand.and.stars",
                        title: "自动避让刘海",
                        detail: "根据最受限屏幕自动决定收纳项目",
                        isOn: Binding(
                            get: { store.automaticAvoidanceEnabled },
                            set: { store.setAutomaticAvoidanceEnabled($0) }
                        )
                    )
                    separator
                    preferenceToggle(
                        symbol: "rectangle.compress.vertical",
                        title: "隐藏已收纳的原图标",
                        detail: "关闭后只保留规则，不移动系统菜单栏",
                        isOn: Binding(
                            get: { store.layoutManagementEnabled },
                            set: { store.setLayoutManagementEnabled($0) }
                        )
                    )
                    separator
                    preferenceToggle(
                        symbol: "cursorarrow.motionlines",
                        title: "指针到达菜单栏时展开",
                        detail: "无需点击即可快速查看托盘",
                        isOn: $hoverRevealEnabled
                    )
                    separator
                    preferenceToggle(
                        symbol: "power",
                        title: "登录时启动",
                        detail: "登录 macOS 后自动运行 BarTuck",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                }
            }
            if let error = launchAtLogin.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(BarTuckTheme.warning)
            }
        }
    }

    private var operationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BarTuckSectionTitle("菜单栏操作", detail: "恢复操作不会删除你的规则")
            BarTuckSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button {
                            store.applyLayout()
                        } label: {
                            Label("应用当前布局", systemImage: "arrow.right.to.line.compact")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BarTuckTheme.accent)
                        .disabled(!store.layoutManagementEnabled || store.selectedItems.isEmpty)

                        Button {
                            store.restoreLayout()
                        } label: {
                            Label("恢复全部图标", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.selectedItems.isEmpty)

                        Button(action: showOnboarding) {
                            Label("重新引导", systemImage: "sparkles.rectangle.stack")
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    if let message = store.layoutOperationMessage {
                        Label(message, systemImage: "info.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(BarTuckTheme.secondaryText)
                    } else {
                        Text("项目规则会同时应用到主屏和扩展屏；托盘始终在当前操作的屏幕展开。")
                            .font(.system(size: 10))
                            .foregroundStyle(BarTuckTheme.secondaryText)
                    }

                    Divider().overlay(BarTuckTheme.stroke)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("安全重置")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BarTuckTheme.primaryText)
                            Text("恢复所有图标并清除布局状态，权限和登录设置不受影响。")
                                .font(.system(size: 10))
                                .foregroundStyle(BarTuckTheme.secondaryText)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.restoreAllAndDisable()
                        } label: {
                            Label("安全重置", systemImage: "shield.lefthalf.filled")
                        }
                        .buttonStyle(.bordered)
                        .tint(BarTuckTheme.warning)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BarTuckTheme.accentStrong)
            VStack(alignment: .leading, spacing: 2) {
                Text("BarTuck 0.1.1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BarTuckTheme.primaryText)
                Text("Apple Silicon · macOS 15+ · 本地运行 · 无遥测")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BarTuckTheme.secondaryText)
            }
            Spacer()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(BarTuckTheme.warning)
        }
        .padding(.horizontal, 4)
    }

    private var separator: some View {
        Divider().overlay(BarTuckTheme.stroke).padding(.leading, 52)
    }

    private func preferenceToggle(
        symbol: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? BarTuckTheme.accentStrong : BarTuckTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(BarTuckTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BarTuckTheme.primaryText)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(BarTuckTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(BarTuckTheme.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}

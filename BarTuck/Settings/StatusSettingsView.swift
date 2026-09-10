import SwiftUI

struct StatusSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager
    var restartApplication: () -> Void = {}

    var body: some View {
        Form {
            Section("系统权限") {
                permissionRow("辅助功能", symbol: "accessibility",
                              granted: store.isUIPreviewMode || permissions.accessibilityGranted,
                              previouslyEffective: permissions.accessibilityWasPreviouslyEffective,
                              action: permissions.requestAccessibility)
                permissionRow("屏幕录制", symbol: "rectangle.inset.filled.and.person.filled",
                              granted: store.isUIPreviewMode || permissions.screenRecordingGranted,
                              previouslyEffective: permissions.screenWasPreviouslyEffective,
                              action: permissions.requestScreenRecording)
                HStack {
                    Button("重新检查", systemImage: "arrow.clockwise") {
                        permissions.refresh()
                        store.refresh()
                    }
                    Spacer()
                    if let checked = permissions.lastChecked {
                        Text("检查于 \(checked.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !permissions.isReady && !store.isUIPreviewMode {
                Section("开关已打开，但仍未生效") {
                    Text(permissions.screenRestartSuggested
                        ? "系统已接受录屏请求，当前进程尚未生效，请重新启动。"
                        : "先重新启动 BarTuck，再检查两项状态是否变为“已生效”。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("重新启动 BarTuck", action: restartApplication)
                        Button("定位当前应用") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                    if permissions.isAdHocSigned {
                        Text("此版本使用临时签名。更新后，系统可能仍保留旧版本的授权开关。若重启后仍未生效，请在系统设置中移除旧的 BarTuck 条目，再添加当前应用并允许访问。")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("辅助功能设置", action: permissions.openAccessibilitySettings)
                        Button("屏幕录制设置", action: permissions.openScreenRecordingSettings)
                    }
                }
            }
            Section("显示器") {
                ForEach(store.displays) { display in
                    HStack(spacing: 12) {
                        Image(systemName: display.hasNotch ? "macbook" : "display")
                            .font(.system(size: 19)).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(display.name == "Built-in Retina Display" ? "内置显示屏" : display.name)
                            Text(display.resolutionLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(display.isMain ? "主显示器" : "扩展显示器").foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }

    private func permissionRow(_ title: String, symbol: String, granted: Bool, previouslyEffective: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 28)
            Text(title)
            Spacer()
            Label(granted ? (store.isUIPreviewMode ? "示例：已生效" : "已生效") : (previouslyEffective ? "曾允许 · 当前未生效" : "未生效"),
                  systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
            if granted {
                EmptyView()
            } else {
                Button("授权…", action: action).accessibilityLabel("授权\(title)")
            }
        }.padding(.vertical, 5)
    }
}

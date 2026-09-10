import SwiftUI

struct StatusSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager

    var body: some View {
        Form {
            Section("系统权限") {
                permissionRow("辅助功能", symbol: "accessibility",
                              granted: store.isUIPreviewMode || permissions.accessibilityGranted,
                              action: permissions.requestAccessibility)
                permissionRow("屏幕录制", symbol: "rectangle.inset.filled.and.person.filled",
                              granted: store.isUIPreviewMode || permissions.screenRecordingGranted,
                              action: permissions.requestScreenRecording)
                Button("重新检查", systemImage: "arrow.clockwise") {
                    permissions.refresh()
                    store.refresh()
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

    private func permissionRow(_ title: String, symbol: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 28)
            Text(title)
            Spacer()
            if granted {
                Label("已允许", systemImage: "checkmark").foregroundStyle(.secondary)
            } else {
                Button("打开设置", action: action).accessibilityLabel("\(title)设置")
            }
        }.padding(.vertical, 5)
    }
}

import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager
    let onComplete: (Bool) -> Void

    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var hideSelectedIcons: Bool
    @State private var previewLoginEnabled = false

    init(store: MenuBarItemStore, permissions: PermissionManager,
         initialHideSelectedIcons: Bool, onComplete: @escaping (Bool) -> Void) {
        self.store = store
        self.permissions = permissions
        self.onComplete = onComplete
        _step = State(initialValue: Step.previewSelection)
        _hideSelectedIcons = State(initialValue: initialHideSelectedIcons)
    }

    private enum Step: Int, CaseIterable {
        case welcome, permissions, customize, ready
        var title: String {
            switch self {
            case .welcome: "欢迎"
            case .permissions: "系统权限"
            case .customize: "偏好设置"
            case .ready: "完成"
            }
        }
        static var previewSelection: Step {
            let prefix = "--ui-preview-onboarding-step="
            let value = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }?
                .dropFirst(prefix.count)
            switch value {
            case "permissions": return .permissions
            case "customize": return .customize
            case "ready": return .ready
            default: return .welcome
            }
        }
    }

    private var accessibilityGranted: Bool { store.isUIPreviewMode || permissions.accessibilityGranted }
    private var recordingGranted: Bool { store.isUIPreviewMode || permissions.screenRecordingGranted }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(step.title).fontWeight(.medium)
                Spacer()
                ProgressView(value: Double(step.rawValue + 1), total: 4).frame(width: 110)
                Text("\(step.rawValue + 1) / 4").foregroundStyle(.secondary).font(.caption)
            }
            .padding(.horizontal, 24).frame(height: 48)
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
                .id(step)
                .transition(.opacity)
            Divider()
            HStack {
                if step != .welcome {
                    Button("上一步") { move(-1) }
                }
                Spacer()
                Button(step == .ready ? "完成" : "继续") {
                    if step == .ready { onComplete(hideSelectedIcons) }
                    else { move(1) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).frame(height: 56)
        }
        .font(.system(size: 13))
        .tint(BarTuckTheme.accent)
        .background(BarTuckTheme.canvas)
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: step)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: step) { _, value in
            if value == .customize { store.refresh() }
        }
        .onChange(of: permissions.screenRecordingGranted) { _, granted in
            if granted { store.refresh() }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 80, height: 80)
                Text("欢迎使用 BarTuck").font(.system(size: 22, weight: .medium))
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 24) {
                Text("系统权限").font(.system(size: 20, weight: .medium))
                VStack(spacing: 18) {
                    permissionRow("辅助功能", symbol: "accessibility", granted: accessibilityGranted,
                                  action: permissions.requestAccessibility)
                    Divider()
                    permissionRow("屏幕录制", symbol: "rectangle.inset.filled.and.person.filled", granted: recordingGranted,
                                  action: permissions.requestScreenRecording)
                }
            }.frame(maxWidth: 470)
        case .customize:
            VStack(alignment: .leading, spacing: 26) {
                Text("偏好设置").font(.system(size: 20, weight: .medium))
                Toggle("登录时打开 BarTuck", isOn: Binding(
                    get: { store.isUIPreviewMode ? previewLoginEnabled : launchAtLogin.isEnabled },
                    set: { value in
                        if store.isUIPreviewMode { previewLoginEnabled = value }
                        else { launchAtLogin.setEnabled(value) }
                    }
                ))
                Toggle("启用菜单项收纳", isOn: $hideSelectedIcons)
                if let error = launchAtLogin.errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .toggleStyle(.checkbox).frame(maxWidth: 470)
        case .ready:
            VStack(spacing: 24) {
                Image(systemName: accessibilityGranted && recordingGranted ? "checkmark.circle" : "clock")
                    .font(.system(size: 36)).foregroundStyle(.secondary)
                Text(accessibilityGranted && recordingGranted ? "设置完成" : "设置已保存")
                    .font(.system(size: 22, weight: .medium))
                VStack(spacing: 14) {
                    LabeledContent("辅助功能", value: accessibilityGranted ? "已允许" : "未允许")
                    LabeledContent("屏幕录制", value: recordingGranted ? "已允许" : "未允许")
                }.foregroundStyle(.secondary).frame(width: 280)
            }
        }
    }

    private func permissionRow(_ title: String, symbol: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            if granted {
                Label("已允许", systemImage: "checkmark").foregroundStyle(.secondary)
            } else {
                Button("打开设置", action: action).accessibilityLabel("\(title)设置")
            }
        }
    }

    private func move(_ offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
    }
}

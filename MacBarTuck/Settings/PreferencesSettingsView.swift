import SwiftUI
import UniformTypeIdentifiers

struct PreferencesSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var dockVisibility: DockVisibilityController
    @Binding var hoverRevealEnabled: Bool
    let showOnboarding: () -> Void
    @State private var confirmReset = false
    @State private var previewLoginEnabled = false
    @State private var logError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("菜单栏") {
                    Toggle("自动避让刘海", isOn: Binding(
                        get: { store.automaticAvoidanceEnabled }, set: { store.setAutomaticAvoidanceEnabled($0) }
                    ))
                    Toggle("悬停时展开", isOn: $hoverRevealEnabled)
                }
                Section("应用") {
                    Toggle("在程序坞中显示 MacBarTuck", isOn: Binding(
                        get: { dockVisibility.showsDockIcon },
                        set: { dockVisibility.setDockIconVisible($0) }
                    ))
                    if let error = dockVisibility.errorMessage {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                    Toggle("登录时打开 MacBarTuck", isOn: Binding(
                        get: { store.isUIPreviewMode ? previewLoginEnabled : launchAtLogin.isEnabled },
                        set: { value in
                            if store.isUIPreviewMode { previewLoginEnabled = value }
                            else { launchAtLogin.setEnabled(value) }
                        }
                    ))
                    if let error = launchAtLogin.errorMessage {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
                Section("菜单项") {
                    HStack {
                        Button("应用显示方式", systemImage: "checkmark") { store.applyLayout() }
                            .disabled(!store.layoutManagementEnabled || store.selectedItems.isEmpty)
                        Button("全部显示", systemImage: "arrow.uturn.backward") { store.setLayoutManagementEnabled(false) }
                            .disabled(!store.layoutManagementEnabled)
                    }
                    if let message = store.layoutOperationMessage {
                        Text(message).foregroundStyle(.secondary).font(.caption)
                    }
                }
                Section("诊断") {
                    HStack {
                        Button("查看日志", systemImage: "doc.text.magnifyingglass") {
                            DiagnosticLog.shared.record("diagnostics.open")
                            DiagnosticLog.shared.flush()
                            NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.shared.fileURL])
                        }
                        Button("导出日志…", systemImage: "square.and.arrow.up") { exportDiagnostics() }
                    }
                    if let logError { Text(logError).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    HStack {
                        Button("重新设置…", action: showOnboarding)
                        Spacer()
                        Button("重置菜单栏设置…", role: .destructive) { confirmReset = true }
                    }
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .controlSize(.small)
            .confirmationDialog("重置菜单栏设置？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置", role: .destructive) { store.restoreAllAndDisable() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("所有菜单项将恢复显示，已有规则会被清除。登录启动和系统权限不变。")
            }
            Divider()
            HStack {
                Text("MacBarTuck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关于 MacBarTuck") { NSApp.orderFrontStandardAboutPanel(nil) }
                    .buttonStyle(.link)
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.link)
            }
            .font(.system(size: 11)).padding(.horizontal, 20).frame(height: 36)
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacBarTuck-diagnostics.jsonl"
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let log = DiagnosticLog.shared
                log.record("diagnostics.export")
                log.flush()
                let previous = log.directory.appendingPathComponent("diagnostic.previous.jsonl")
                guard url.standardizedFileURL != log.fileURL.standardizedFileURL && url.standardizedFileURL != previous.standardizedFileURL else { return }
                var data = (try? Data(contentsOf: previous)) ?? Data()
                data.append(try Data(contentsOf: log.fileURL))
                try data.write(to: url, options: .atomic)
                logError = nil
            } catch { logError = "导出失败：\(error.localizedDescription)" }
        }
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct PreferencesSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var dockVisibility: DockVisibilityController
    @Binding var hoverRevealEnabled: Bool
    let showOnboarding: () -> Void
    @EnvironmentObject private var language: AppLanguageController
    @State private var confirmReset = false
    @State private var previewLoginEnabled = false
    @State private var logError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(language.text("preferences.menubar.section")) {
                    Toggle(language.text("preferences.notch"), isOn: Binding(
                        get: { store.automaticAvoidanceEnabled }, set: { store.setAutomaticAvoidanceEnabled($0) }
                    ))
                    Toggle(language.text("preferences.hover"), isOn: $hoverRevealEnabled)
                        .help(language.text("preferences.hover.help"))
                }
                Section(language.text("preferences.application.section")) {
                    Toggle(language.text("preferences.dock"), isOn: Binding(
                        get: { dockVisibility.showsDockIcon },
                        set: { dockVisibility.setDockIconVisible($0) }
                    ))
                    if let error = dockVisibility.errorMessage {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                    Toggle(language.text("preferences.login"), isOn: Binding(
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
                Section(language.text("preferences.language.section")) {
                    HStack {
                        Text(language.text("preferences.language.label"))
                        Spacer()
                        Picker(language.text("preferences.language.label"), selection: Binding(
                            get: { language.selectedLanguage },
                            set: { language.setLanguage($0) }
                        )) {
                            ForEach(AppLanguage.allCases) { option in
                                Text(option.switchLabel).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 178)
                    }
                    Text(language.text("preferences.language.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(language.text("preferences.items.section")) {
                    HStack {
                        Button(language.text("preferences.apply"), systemImage: "checkmark") { store.applyLayout() }
                            .disabled(!store.layoutManagementEnabled || store.selectedItems.isEmpty)
                        if !store.temporarilyVisibleItems.isEmpty {
                            Button(language.text("panel.retuck.count", store.temporarilyVisibleItems.count),
                                   systemImage: "arrow.uturn.backward.circle.fill") {
                                store.retuckTemporarilyVisibleItems()
                            }
                            .tint(MacBarTuckTheme.retuckAction)
                        }
                        Button(language.text("preferences.show_all"), systemImage: "arrow.uturn.backward") { store.setLayoutManagementEnabled(false) }
                            .disabled(!store.layoutManagementEnabled)
                    }
                    if let message = store.layoutOperationMessage {
                        Text(message).foregroundStyle(.secondary).font(.caption)
                    }
                }
                Section(language.text("preferences.diagnostics.section")) {
                    HStack {
                        Button(language.text("preferences.logs.open"), systemImage: "doc.text.magnifyingglass") {
                            DiagnosticLog.shared.record("diagnostics.open")
                            DiagnosticLog.shared.flush()
                            NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.shared.fileURL])
                        }
                        Button(language.text("preferences.logs.export"), systemImage: "square.and.arrow.up") { exportDiagnostics() }
                    }
                    if let logError { Text(logError).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    HStack {
                        Button(language.text("preferences.setup_again"), action: showOnboarding)
                        Spacer()
                        Button(language.text("preferences.reset_settings"), role: .destructive) { confirmReset = true }
                    }
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .controlSize(.small)
            .confirmationDialog(language.text("preferences.reset.title"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(language.text("common.reset"), role: .destructive) { store.restoreAllAndDisable() }
                Button(language.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(language.text("preferences.reset.message"))
            }
            Divider()
            HStack {
                Text("MacBarTuck \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(language.text("preferences.about")) { NSApp.orderFrontStandardAboutPanel(nil) }
                    .buttonStyle(.link)
                Button(language.text("common.quit")) { NSApp.terminate(nil) }.buttonStyle(.link)
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
            } catch { logError = language.text("preferences.export.failed", error.localizedDescription) }
        }
    }
}

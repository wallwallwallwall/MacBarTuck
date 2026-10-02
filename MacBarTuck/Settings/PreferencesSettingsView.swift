import SwiftUI
import UniformTypeIdentifiers

struct PreferencesSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var dockVisibility: DockVisibilityController
    @ObservedObject var trayShortcut: TrayShortcutController
    @Binding var hoverRevealEnabled: Bool
    @Binding var hoverRevealDelaySeconds: Double
    let showOnboarding: () -> Void
    @EnvironmentObject private var language: AppLanguageController
    @State private var confirmReset = false
    @State private var previewLoginEnabled = false
    @State private var logError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MacBarTuckSettingsSection(
                        title: language.text("preferences.menubar.section"),
                        symbol: "menubar.rectangle", tint: MacBarTuckTheme.collected
                    ) {
                        HStack {
                            Text(language.text("preferences.shortcut"))
                            Spacer()
                            Picker(language.text("preferences.shortcut"), selection: Binding(
                                get: { trayShortcut.selection },
                                set: { trayShortcut.setShortcut($0) }
                            )) {
                                ForEach(TrayShortcut.allCases) { option in
                                    Text(language.text(option.localizationKey)).tag(option)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).frame(width: 178)
                            .accessibilityIdentifier("tray-shortcut")
                        }
                        if trayShortcut.registrationFailed {
                            Text(language.text("preferences.shortcut.failed"))
                                .foregroundStyle(.red).font(.caption)
                        }
                        MacBarTuckPreferenceToggle(
                            title: language.text("preferences.notch"),
                            isOn: Binding(
                                get: { store.automaticAvoidanceEnabled },
                                set: { store.setAutomaticAvoidanceEnabled($0) }
                            ))
                        MacBarTuckPreferenceToggle(
                            title: language.text("preferences.hover"), isOn: $hoverRevealEnabled
                        )
                        .help(language.text("preferences.hover.help"))
                        HStack(spacing: 12) {
                            Text(language.text("preferences.hover.delay"))
                            Spacer()
                            Slider(
                                value: normalizedHoverRevealDelay,
                                in: HoverRevealDelayController
                                    .minimumDelay...HoverRevealDelayController.maximumDelay,
                                step: 0.5
                            )
                            .tint(MacBarTuckTheme.collected)
                            .accessibilityLabel(language.text("preferences.hover.delay"))
                            .frame(width: 180)
                            Text(language.text("preferences.hover.delay.value", normalizedDelayValue))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .trailing)
                        }
                        .disabled(!hoverRevealEnabled)
                        .help(language.text("preferences.hover.delay.help"))
                    }
                    MacBarTuckSettingsSection(
                        title: language.text("preferences.application.section"),
                        symbol: "app.badge", tint: MacBarTuckTheme.accent
                    ) {
                        MacBarTuckPreferenceToggle(
                            title: language.text("preferences.dock"),
                            isOn: Binding(
                                get: { dockVisibility.showsDockIcon },
                                set: { dockVisibility.setDockIconVisible($0) }
                            ))
                        if let error = dockVisibility.errorMessage {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                        MacBarTuckPreferenceToggle(
                            title: language.text("preferences.login"),
                            isOn: Binding(
                                get: { store.isUIPreviewMode ? previewLoginEnabled : launchAtLogin.isEnabled },
                                set: { value in
                                    if store.isUIPreviewMode {
                                        previewLoginEnabled = value
                                    } else {
                                        launchAtLogin.setEnabled(value)
                                    }
                                }
                            ))
                        if let error = launchAtLogin.errorMessage {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                    }
                    MacBarTuckSettingsSection(
                        title: language.text("preferences.language.section"),
                        symbol: "globe", tint: MacBarTuckTheme.success
                    ) {
                        HStack {
                            Text(language.text("preferences.language.label"))
                            Spacer()
                            Picker(
                                language.text("preferences.language.label"),
                                selection: Binding(
                                    get: { language.selectedLanguage },
                                    set: { language.setLanguage($0) }
                                )
                            ) {
                                ForEach(AppLanguage.allCases) { option in
                                    Text(option.switchLabel).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 178)
                        }
                        .help(language.text("preferences.language.help"))
                    }
                    MacBarTuckSettingsSection(
                        title: language.text("preferences.diagnostics.section"),
                        symbol: "waveform.path", tint: MacBarTuckTheme.retuckAction
                    ) {
                        HStack {
                            Button(
                                language.text("preferences.logs.open"), systemImage: "doc.text.magnifyingglass"
                            ) {
                                DiagnosticLog.shared.record("diagnostics.open")
                                DiagnosticLog.shared.flush()
                                NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.shared.fileURL])
                            }
                            Button(language.text("preferences.logs.export"), systemImage: "square.and.arrow.up") {
                                exportDiagnostics()
                            }
                        }
                        if let logError { Text(logError).font(.caption).foregroundStyle(.red) }
                    }
                    HStack {
                        Button(language.text("preferences.setup_again"), action: showOnboarding)
                        Spacer()
                        Button(language.text("preferences.reset_settings"), role: .destructive) {
                            confirmReset = true
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .toggleStyle(.switch)
            .tint(MacBarTuckTheme.accent)
            .controlSize(.small)
            .confirmationDialog(
                language.text("preferences.reset.title"), isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button(language.text("common.reset"), role: .destructive) { store.restoreAllAndDisable() }
                Button(language.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(language.text("preferences.reset.message"))
            }
            Divider()
            HStack {
                Button {
                    NSApp.orderFrontStandardAboutPanel(nil)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help(language.text("preferences.about"))
                .accessibilityLabel(language.text("preferences.about"))
                Spacer()
                Button(language.text("common.quit"), systemImage: "power") { NSApp.terminate(nil) }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 11)).padding(.horizontal, 20).frame(height: 36)
            .background(MacBarTuckTheme.chrome)
        }
    }

    private var normalizedDelayValue: Double {
        HoverRevealDelayController.normalizedDelay(hoverRevealDelaySeconds)
    }

    private var normalizedHoverRevealDelay: Binding<Double> {
        Binding(
            get: { normalizedDelayValue },
            set: { hoverRevealDelaySeconds = HoverRevealDelayController.normalizedDelay($0) }
        )
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
                guard
                    url.standardizedFileURL != log.fileURL.standardizedFileURL
                        && url.standardizedFileURL != previous.standardizedFileURL
                else { return }
                var data = (try? Data(contentsOf: previous)) ?? Data()
                data.append(try Data(contentsOf: log.fileURL))
                try data.write(to: url, options: .atomic)
                logError = nil
            } catch { logError = language.text("preferences.export.failed", error.localizedDescription) }
        }
    }
}

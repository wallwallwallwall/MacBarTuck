import SwiftUI

struct StatusSettingsView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager
    var restartApplication: () -> Void = {}
    @EnvironmentObject private var language: AppLanguageController

    var body: some View {
        Form {
            Section(language.text("permissions.section")) {
                permissionRow(language.text("permissions.accessibility"), symbol: "accessibility",
                              granted: store.isUIPreviewMode || permissions.accessibilityGranted,
                              previouslyEffective: permissions.accessibilityWasPreviouslyEffective,
                              action: permissions.requestAccessibility)
                permissionRow(language.text("permissions.screen_recording"), symbol: "rectangle.inset.filled.and.person.filled",
                              granted: store.isUIPreviewMode || permissions.screenRecordingGranted,
                              previouslyEffective: permissions.screenWasPreviouslyEffective,
                              action: permissions.requestScreenRecording)
                HStack {
                    Button(language.text("permissions.recheck"), systemImage: "arrow.clockwise") {
                        permissions.refresh()
                        store.refresh()
                    }
                    Spacer()
                    if let checked = permissions.lastChecked {
                        Text(language.text("permissions.checked_at", checked.formatted(
                            .dateTime.hour().minute().second().locale(language.selectedLanguage.locale)
                        )))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !permissions.isReady && !store.isUIPreviewMode {
                Section(language.text("permissions.not_effective.section")) {
                    Text(permissions.screenRestartSuggested
                        ? language.text("permissions.restart.screen")
                        : language.text("permissions.restart.general"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button(language.text("permissions.restart.button"), action: restartApplication)
                        Button(language.text("permissions.locate_app")) {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                    if permissions.isAdHocSigned {
                        Text(language.text("permissions.adhoc_note"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(language.text("permissions.accessibility.settings"), action: permissions.openAccessibilitySettings)
                        Button(language.text("permissions.screen_recording.settings"), action: permissions.openScreenRecordingSettings)
                    }
                }
            }
            Section(language.text("permissions.displays.section")) {
                ForEach(store.displays) { display in
                    HStack(spacing: 12) {
                        Image(systemName: display.hasNotch ? "macbook" : "display")
                            .font(.system(size: 19)).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(display.displayName(for: language))
                            Text(display.resolutionLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(display.isMain ? language.text("permissions.display.main") : language.text("permissions.display.extended"))
                            .foregroundStyle(.secondary)
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
            Label(granted
                  ? (store.isUIPreviewMode ? language.text("permissions.status.preview_effective") : language.text("permissions.status.effective"))
                  : (previouslyEffective ? language.text("permissions.status.previous") : language.text("permissions.status.not_effective")),
                  systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
            if granted {
                EmptyView()
            } else {
                Button(language.text("permissions.authorize"), action: action)
                    .accessibilityLabel(language.text("permissions.authorize.label", title))
            }
        }.padding(.vertical, 5)
    }
}

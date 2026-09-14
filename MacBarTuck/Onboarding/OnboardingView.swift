import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: MenuBarItemStore
    @ObservedObject var permissions: PermissionManager
    let onComplete: (Bool) -> Void

    @StateObject private var launchAtLogin = LaunchAtLoginManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var language: AppLanguageController
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
        func title(_ language: AppLanguageController) -> String {
            switch self {
            case .welcome: language.text("onboarding.step.welcome")
            case .permissions: language.text("onboarding.step.permissions")
            case .customize: language.text("onboarding.step.preferences")
            case .ready: language.text("onboarding.step.ready")
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
                Text(step.title(language)).fontWeight(.medium)
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
                .frame(width: 150)
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
                    Button(language.text("onboarding.previous")) { move(-1) }
                }
                Spacer()
                Button(step == .ready ? language.text("onboarding.finish") : language.text("onboarding.continue")) {
                    if step == .ready { onComplete(hideSelectedIcons) }
                    else { move(1) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).frame(height: 56)
        }
        .font(.system(size: 13))
        .tint(MacBarTuckTheme.accent)
        .background(MacBarTuckTheme.canvas)
        .frame(minWidth: 680, minHeight: 500)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: step)
        .task {
            while !Task.isCancelled {
                permissions.refresh(updateTimestamp: false)
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
                Text(language.text("onboarding.welcome.title")).font(.system(size: 22, weight: .medium))
            }
        case .permissions:
            VStack(alignment: .leading, spacing: 24) {
                Text(language.text("permissions.section")).font(.system(size: 20, weight: .medium))
                VStack(spacing: 18) {
                    permissionRow(language.text("permissions.accessibility"), symbol: "accessibility", granted: accessibilityGranted,
                                  action: permissions.requestAccessibility)
                    Divider()
                    permissionRow(language.text("permissions.screen_recording"), symbol: "rectangle.inset.filled.and.person.filled", granted: recordingGranted,
                                  action: permissions.requestScreenRecording)
                }
            }.frame(maxWidth: 470)
        case .customize:
            VStack(alignment: .leading, spacing: 26) {
                Text(language.text("onboarding.step.preferences")).font(.system(size: 20, weight: .medium))
                Toggle(language.text("preferences.login"), isOn: Binding(
                    get: { store.isUIPreviewMode ? previewLoginEnabled : launchAtLogin.isEnabled },
                    set: { value in
                        if store.isUIPreviewMode { previewLoginEnabled = value }
                        else { launchAtLogin.setEnabled(value) }
                    }
                ))
                Toggle(language.text("onboarding.enable_collection"), isOn: $hideSelectedIcons)
                if let error = launchAtLogin.errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .toggleStyle(.checkbox).frame(maxWidth: 470)
        case .ready:
            VStack(spacing: 24) {
                Image(systemName: accessibilityGranted && recordingGranted ? "checkmark.circle" : "clock")
                    .font(.system(size: 36)).foregroundStyle(.secondary)
                Text(accessibilityGranted && recordingGranted
                     ? language.text("onboarding.setup_complete")
                     : language.text("onboarding.setup_saved"))
                    .font(.system(size: 22, weight: .medium))
                VStack(spacing: 14) {
                    LabeledContent(language.text("permissions.accessibility"),
                                   value: accessibilityGranted ? language.text("onboarding.allowed") : language.text("onboarding.not_allowed"))
                    LabeledContent(language.text("permissions.screen_recording"),
                                   value: recordingGranted ? language.text("onboarding.allowed") : language.text("onboarding.not_allowed"))
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
                Label(language.text("onboarding.allowed"), systemImage: "checkmark").foregroundStyle(.secondary)
            } else {
                Button(language.text("onboarding.open_settings"), action: action)
                    .accessibilityLabel(language.text("onboarding.open_settings.label", title))
            }
        }
    }

    private func move(_ offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
    }
}

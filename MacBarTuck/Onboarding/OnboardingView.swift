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
                Text("MacBarTuck").font(.system(size: 14, weight: .semibold))
                Text(step.title(language)).foregroundStyle(MacBarTuckTheme.secondaryText)
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
            }
            .padding(.horizontal, 24).frame(height: 56)
            .background(MacBarTuckTheme.chrome)
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
                .id(step)
                .transition(.opacity)
            Divider()
            HStack {
                if step != .welcome {
                    Button(language.text("onboarding.previous"), systemImage: "chevron.left") { move(-1) }
                        .buttonStyle(.plain)
                }
                Spacer()
                Button(step == .ready ? language.text("onboarding.finish") : language.text("onboarding.continue")) {
                    if step == .ready { onComplete(hideSelectedIcons) }
                    else { move(1) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .overlay { stepProgress }
            .padding(.horizontal, 24).frame(height: 68)
            .background(MacBarTuckTheme.chrome)
        }
        .font(.system(size: 13))
        .foregroundStyle(MacBarTuckTheme.primaryText)
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
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit().frame(width: 148, height: 148)
                Text("MacBarTuck").font(.system(size: 26, weight: .semibold))
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
                MacBarTuckPreferenceToggle(title: language.text("preferences.login"), isOn: Binding(
                    get: { store.isUIPreviewMode ? previewLoginEnabled : launchAtLogin.isEnabled },
                    set: { value in
                        if store.isUIPreviewMode { previewLoginEnabled = value }
                        else { launchAtLogin.setEnabled(value) }
                    }
                ))
                MacBarTuckPreferenceToggle(title: language.text("onboarding.enable_collection"), isOn: $hideSelectedIcons)
                if let error = launchAtLogin.errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .frame(maxWidth: 470)
        case .ready:
            VStack(spacing: 24) {
                Image(systemName: accessibilityGranted && recordingGranted ? "checkmark.circle" : "clock")
                    .font(.system(size: 52))
                    .foregroundStyle(accessibilityGranted && recordingGranted
                                     ? MacBarTuckTheme.success : MacBarTuckTheme.retuckAction)
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

    private var stepProgress: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { value in
                Circle()
                    .fill(value == step ? MacBarTuckTheme.accent : MacBarTuckTheme.strongStroke)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title(language))
        .accessibilityValue("\(step.rawValue + 1) / 4")
        .allowsHitTesting(false)
    }

    private func permissionRow(_ title: String, symbol: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 30)
                .foregroundStyle(granted ? MacBarTuckTheme.success : MacBarTuckTheme.retuckAction)
            Text(title)
            Spacer()
            if granted {
                Label(language.text("onboarding.allowed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(MacBarTuckTheme.success)
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

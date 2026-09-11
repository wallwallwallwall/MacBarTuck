import AppKit
import ApplicationServices
import CoreGraphics
import Security

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var accessibilityWasPreviouslyEffective = false
    @Published private(set) var screenWasPreviouslyEffective = false
    @Published private(set) var screenRestartSuggested = false
    @Published private(set) var lastChecked: Date?
    private static var didRequestScreenRecording = false
    private static var didRequestAccessibility = false
    private let accessibilityStatus: () -> Bool
    private let accessibilityRequest: () -> Void
    private let screenCaptureStatus: () -> Bool
    private let screenCaptureRequest: () -> Bool
    private let openSettings: (String) -> Void
    private let history: UserDefaults?
    private let language: AppLanguageController
    let isAdHocSigned = PermissionManager.hasAdHocSignature()

    var effectiveCount: Int { (accessibilityGranted ? 1 : 0) + (screenRecordingGranted ? 1 : 0) }
    var effectiveAccessKey: Int { (accessibilityGranted ? 1 : 0) + (screenRecordingGranted ? 2 : 0) }
    var isReady: Bool { accessibilityGranted && screenRecordingGranted }
    var statusTitle: String {
        isReady ? language.text("permissions.ready") : language.text("permissions.count", effectiveCount)
    }
    var statusDetail: String {
        language.text(
            "permissions.summary",
            accessibilityGranted ? language.text("permissions.status.effective") : language.text("permissions.status.not_effective"),
            screenRecordingGranted ? language.text("permissions.status.effective") : language.text("permissions.status.not_effective")
        )
    }

    init(
        accessibilityStatus: @escaping () -> Bool = AXIsProcessTrusted,
        accessibilityRequest: @escaping () -> Void = {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        },
        screenCaptureStatus: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        screenCaptureRequest: @escaping () -> Bool = CGRequestScreenCaptureAccess,
        openSettings: @escaping (String) -> Void = { value in
            guard let url = URL(string: value) else { return }
            NSWorkspace.shared.open(url)
        },
        history: UserDefaults? = ProcessInfo.processInfo.arguments.contains("--ui-preview") ? nil : .standard,
        language: AppLanguageController = .shared
    ) {
        self.accessibilityStatus = accessibilityStatus
        self.accessibilityRequest = accessibilityRequest
        self.history = history
        self.screenCaptureStatus = screenCaptureStatus
        self.screenCaptureRequest = screenCaptureRequest
        self.openSettings = openSettings
        self.language = language
        refresh()
    }

    func refresh() {
        accessibilityGranted = accessibilityStatus()
        screenRecordingGranted = screenCaptureStatus()
        if accessibilityGranted { history?.set(true, forKey: "permissionAccessibilityWasEffective") }
        if screenRecordingGranted {
            history?.set(true, forKey: "permissionScreenWasEffective")
            screenRestartSuggested = false
        }
        accessibilityWasPreviouslyEffective = history?.bool(forKey: "permissionAccessibilityWasEffective") ?? accessibilityGranted
        screenWasPreviouslyEffective = history?.bool(forKey: "permissionScreenWasEffective") ?? screenRecordingGranted
        lastChecked = Date()
    }

    func requestAccessibility() {
        refresh()
        guard !accessibilityGranted else { return }
        if Self.didRequestAccessibility { openAccessibilitySettings(); return }
        Self.didRequestAccessibility = true
        accessibilityRequest()
        refresh()
    }

    func requestScreenRecording() {
        refresh()
        guard !screenRecordingGranted else { return }
        // Register the app through the system request on an explicit click.
        // Share the guard across settings/onboarding to avoid repeated sheets
        // when a replaced ad-hoc build has a stale authorization identity.
        if Self.didRequestScreenRecording {
            openScreenRecordingSettings()
        } else {
            Self.didRequestScreenRecording = true
            let accepted = screenCaptureRequest()
            refresh()
            screenRestartSuggested = accepted && !screenRecordingGranted
        }
    }

    func openAccessibilitySettings() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
    func openScreenRecordingSettings() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }

    private func open(_ url: String) { openSettings(url) }

    private static func hasAdHocSignature() -> Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let flags = dictionary[kSecCodeInfoFlags as String] as? NSNumber else { return false }
        return flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue != 0
    }
}

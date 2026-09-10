import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    private static var didRequestScreenRecording = false
    private let screenCaptureStatus: () -> Bool
    private let screenCaptureRequest: () -> Bool
    private let openSettings: (String) -> Void

    init(
        screenCaptureStatus: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        screenCaptureRequest: @escaping () -> Bool = CGRequestScreenCaptureAccess,
        openSettings: @escaping (String) -> Void = { value in
            guard let url = URL(string: value) else { return }
            NSWorkspace.shared.open(url)
        }
    ) {
        self.screenCaptureStatus = screenCaptureStatus
        self.screenCaptureRequest = screenCaptureRequest
        self.openSettings = openSettings
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = screenCaptureStatus()
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
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
            _ = screenCaptureRequest()
            refresh()
        }
    }

    func openAccessibilitySettings() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
    func openScreenRecordingSettings() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }

    private func open(_ url: String) { openSettings(url) }
}

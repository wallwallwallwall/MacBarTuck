import AppKit

private struct Failure: Error, CustomStringConvertible { let description: String }

@main
@MainActor
enum PermissionStateTests {
    static func main() throws {
        var accessibility = false
        var screen = false
        var requests = 0
        let domain = "PermissionStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let permissions = PermissionManager(
            accessibilityStatus: { accessibility },
            accessibilityRequest: { requests += 1 },
            screenCaptureStatus: { screen }, screenCaptureRequest: { requests += 1; return false },
            openSettings: { _ in }, history: defaults
        )
        try require(permissions.effectiveCount == 0, "A new process without access must show 0/2.")
        try require(!permissions.isReady, "No access must block layout.")
        accessibility = true
        permissions.refresh()
        try require(permissions.effectiveCount == 1 && !permissions.isReady, "Partial access must show 1/2.")
        permissions.requestAccessibility()
        try require(requests == 0, "An already-granted accessibility permission must never request again.")
        screen = true
        permissions.refresh()
        try require(permissions.isReady && permissions.effectiveCount == 2, "Both APIs must agree before readiness.")
        permissions.requestScreenRecording()
        try require(requests == 0, "Already-granted screen access must never request again.")
        screen = false
        permissions.refresh()
        try require(!permissions.isReady, "Revocation must invalidate readiness.")
        try require(permissions.screenWasPreviouslyEffective, "Historical success must be retained separately.")
        let relaunched = PermissionManager(accessibilityStatus: { false }, accessibilityRequest: {},
            screenCaptureStatus: { false }, screenCaptureRequest: { false }, openSettings: { _ in }, history: defaults)
        try require(relaunched.effectiveCount == 0, "History must never grant a new process access.")
        try require(relaunched.accessibilityWasPreviouslyEffective && relaunched.screenWasPreviouslyEffective,
                    "Previously-effective markers must survive a relaunch.")
        permissions.refresh()
        try require(requests == 0, "Background checks must remain read-only.")
        var acceptedScreenEffective = false
        var acceptedRequests = 0
        let accepted = PermissionManager(accessibilityStatus: { true }, accessibilityRequest: {},
            screenCaptureStatus: { acceptedScreenEffective }, screenCaptureRequest: { acceptedRequests += 1; return true },
            openSettings: { _ in }, history: nil)
        accepted.requestScreenRecording()
        try require(acceptedRequests == 1 && accepted.screenRestartSuggested, "An accepted request that is not effective yet needs a restart hint.")
        try require(!accepted.isReady && accepted.effectiveCount == 1, "The request response must never override the effective preflight check.")
        acceptedScreenEffective = true
        accepted.refresh()
        try require(accepted.isReady && !accepted.screenRestartSuggested, "The restart hint must clear when access becomes effective.")
        print("PermissionStateTests: 14 passed")
    }

    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(description: message) }
    }
}

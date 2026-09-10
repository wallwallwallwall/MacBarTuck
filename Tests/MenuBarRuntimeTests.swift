import AppKit
import CoreGraphics

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
private enum MenuBarRuntimeTests {
    static func main() throws {
        let windows: [[String: Any]] = [
            window(10, title: "BarTuckControlItem", width: 25),
            window(11, title: "BarTuckHiddenSection", width: 2003),
            window(12, title: "com.bartuck.app", width: 25),
            window(13, title: "com.bartuck.app", width: 2003),
            window(14, title: "com.example.utility", width: 30),
            window(15, title: "WiFi", width: 38)
        ]
        let scanner = MenuBarScanner(
            readWindows: { windows },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1512, height: 982)] },
            ownBundleIdentifier: "com.bartuck.app"
        )
        try expect(scanner.scan(selectedIDs: []).count == 2,
                   "Scanning must exclude both app-owned hosts and their display mirrors.")
        try expect(scanner.windowSignature().count == 2,
                   "The change fingerprint must exclude the same owned display mirrors.")
        scanner.setOwnedStatusWindowIDs([14])
        try expect(scanner.scan(selectedIDs: []).map(\.title) == ["WiFi"],
                   "Published owned window IDs must still be excluded.")
        try expect(scanner.windowSignature().count == 1,
                   "Published owned IDs must not trigger rescans.")
        try separatorStates()
        try permissionRequests()
        print("MenuBarRuntimeTests: 17 passed")
    }

    private static func separatorStates() throws {
        func length(enabled: Bool = true, ready: Bool = true, selected: Bool = true,
                    applying: Bool = false, widths: [CGFloat] = [1512, 1920]) -> CGFloat {
            StatusItemLayoutPolicy.separatorLength(enabled: enabled, ready: ready,
                                                  hasSelection: selected, isApplying: applying,
                                                  screenWidths: widths)
        }
        try expect(length(enabled: false) == 0, "Disabled layout must not leave a large separator.")
        try expect(length(ready: false) == 0, "Icons must be ready before the lane expands.")
        try expect(length(selected: false) == 0, "An empty selection must not hide unrelated icons.")
        try expect(length(applying: true) == 20, "Moves require a compact on-screen destination.")
        try expect(length() == 3840, "Collapse must cover the widest attached screen.")
        try expect(length(widths: [8000]) == 10000, "Collapse must respect the status-item size limit.")
        try expect(length(widths: [.nan, .infinity, -10]) == 3456, "Invalid display widths must be ignored.")
    }

    private static func permissionRequests() throws {
        var granted = false
        var requests = 0
        var openedSettings = 0
        func manager() -> PermissionManager {
            PermissionManager(screenCaptureStatus: { granted }, screenCaptureRequest: {
                requests += 1
                return granted
            }, openSettings: { _ in openedSettings += 1 }, history: nil)
        }
        let first = manager()
        first.refresh()
        try expect(requests == 0 && openedSettings == 0, "Startup and refresh must not request permissions.")
        first.requestScreenRecording()
        try expect(requests == 1 && openedSettings == 0, "The first explicit click must register the system request.")
        first.requestScreenRecording()
        try expect(requests == 1 && openedSettings == 1, "Repeated clicks must open settings, not another sheet.")
        let second = manager()
        second.requestScreenRecording()
        try expect(requests == 1 && openedSettings == 2, "Settings and onboarding must share the request guard.")
        granted = true
        second.requestScreenRecording()
        try expect(second.screenRecordingGranted && requests == 1 && openedSettings == 2,
                   "Already-granted access must not prompt or open settings.")
        granted = false
        first.refresh()
        try expect(!first.screenRecordingGranted && requests == 1,
                   "Revocation must be visible without prompting in the background.")
    }

    private static func window(_ id: Int, title: String, width: Double) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: -1,
            kCGWindowOwnerName as String: "Control Center",
            kCGWindowName as String: title,
            kCGWindowLayer as String: 25,
            kCGWindowBounds as String: ["X": 1000.0, "Y": 0.0, "Width": width, "Height": 30.0]
        ]
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(description: message) }
    }
}

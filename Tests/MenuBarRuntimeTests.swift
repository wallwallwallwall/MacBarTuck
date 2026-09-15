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
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
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
        try interactionPolicy()
        try platformPolicies()
        try accessibilityDiscoveryValues()
        try permissionRequests()
        print("MenuBarRuntimeTests: 47 passed")
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

    private static func interactionPolicy() throws {
        try expect(
            MenuBarInteractionPolicy.activationPresentation(
                didRevealItem: false,
                isManaged: true,
                layoutEnabled: true
            ) == .leaveLayoutUnchanged,
            "Direct activation must never start a menu bar layout transaction."
        )
        try expect(
            MenuBarInteractionPolicy.activationPresentation(
                didRevealItem: true,
                isManaged: true,
                layoutEnabled: true
            ) == .keepVisibleUntilRetucked,
            "A revealed managed item must remain visible until an explicit retuck."
        )
        try expect(
            MenuBarInteractionPolicy.activationPresentation(
                didRevealItem: true,
                isManaged: false,
                layoutEnabled: true
            ) == .leaveLayoutUnchanged,
            "Unmanaged items must not be tracked as temporarily revealed."
        )
        try expect(
            MenuBarInteractionPolicy.allowsHoverReveal(
                enabled: true,
                isApplyingLayout: false,
                isShowingContextMenu: false,
                isSuppressed: false
            ),
            "Hover reveal should remain available when explicitly enabled and idle."
        )
        try expect(
            !MenuBarInteractionPolicy.allowsHoverReveal(
                enabled: true,
                isApplyingLayout: true,
                isShowingContextMenu: false,
                isSuppressed: false
            ),
            "Hover reveal must be blocked while the real menu bar is moving."
        )
        try expect(
            !MenuBarInteractionPolicy.allowsHoverReveal(
                enabled: true,
                isApplyingLayout: false,
                isShowingContextMenu: true,
                isSuppressed: false
            ),
            "Hover reveal must not cover a context menu."
        )
        try expect(
            !MenuBarInteractionPolicy.allowsHoverReveal(
                enabled: false,
                isApplyingLayout: false,
                isShowingContextMenu: false,
                isSuppressed: false
            ),
            "Hover reveal must stay off by default."
        )
        try expect(
            !MenuBarInteractionPolicy.allowsAutomaticLayout(hasTemporarilyVisibleItems: true),
            "Background discovery must not retuck an item the user is still using."
        )
        try expect(
            !MenuBarInteractionPolicy.shouldDeferLayout(
                isAutomatic: false,
                leftButtonPressed: false,
                rightButtonPressed: true
            ),
            "An explicit Apply action must not be blocked forever by stale global button state."
        )
        try expect(
            MenuBarInteractionPolicy.shouldDeferLayout(
                isAutomatic: true,
                leftButtonPressed: true,
                rightButtonPressed: false
            ),
            "A background layout must wait while the user is actively pressing a mouse button."
        )
        try expect(
            !MenuBarInteractionPolicy.shouldDeferLayout(
                isAutomatic: true,
                leftButtonPressed: false,
                rightButtonPressed: false
            ),
            "An idle background layout must remain eligible to run."
        )
    }

    private static func platformPolicies() throws {
        let macOS15 = MenuBarPlatformPolicy(majorVersion: 15)
        let macOS26 = MenuBarPlatformPolicy(majorVersion: 26)
        let macOS27 = MenuBarPlatformPolicy(majorVersion: 27)
        let future = MenuBarPlatformPolicy(majorVersion: 28)

        try expect(macOS15 == .init(discovery: .windowServerWithAccessibility,
                                   movement: .hybrid, usesHiddenSection: true),
                   "macOS 15 must retain the bounded AX enrichment compatibility path.")
        try expect(macOS26 == .init(discovery: .windowServerOnly,
                                   movement: .windowServer, usesHiddenSection: true),
                   "macOS 26 must retain the verified Control Center-hosted WindowServer path.")
        try expect(macOS27 == .init(discovery: .accessibilityPreferred,
                                   movement: .accessibility, usesHiddenSection: false),
                   "macOS 27 must avoid moving its composite menu-bar host as a window.")
        try expect(macOS27.accessibilityMenuBarAttributeNames == ["AXExtrasMenuBar", "AXMenuBar"],
                   "macOS 27 must read status items from AXExtrasMenuBar before the application menu bar.")
        try expect(macOS15.usesWindowServerAccessibilitySeeds,
                   "The hybrid compatibility path may enrich discrete WindowServer items with AX metadata.")
        try expect(!macOS27.usesWindowServerAccessibilitySeeds,
                   "macOS 27 must build stable identities from AX items instead of dynamic WindowServer seeds.")
        try expect(future == macOS27,
                   "Later releases must default to the safer macOS 27 accessibility strategy.")
    }

    private static func accessibilityDiscoveryValues() throws {
        try expect(
            MenuBarScanner.accessibilityItemTitle(
                rawTitle: "", rawDescription: "ChatGPT",
                applicationName: "ChatGPT", bundleIdentifier: "com.openai.codex"
            ) == "ChatGPT",
            "An empty AXTitle must fall through to AXDescription."
        )
        try expect(
            MenuBarScanner.accessibilityItemTitle(
                rawTitle: "  ", rawDescription: "",
                applicationName: "Tailscale", bundleIdentifier: "io.tailscale.ipn.macsys"
            ) == "Tailscale",
            "A status item without AX text must use its application name."
        )
        try expect(
            MenuBarScanner.accessibilityItemTitle(
                rawTitle: "CPU 12%", rawDescription: "Ignored",
                applicationName: "iStat Menus", bundleIdentifier: "com.bjango.istatmenus.status"
            ) == "CPU 12%",
            "A meaningful AXTitle must remain the preferred label."
        )
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        try expect(
            MenuBarScanner.isRightSideAccessibilityItem(
                frame: CGRect(x: 1088, y: 5, width: 18, height: 18),
                displayBounds: [display]
            ),
            "A vertically inset status icon must remain inside the menu bar discovery band."
        )
        try expect(
            !MenuBarScanner.isRightSideAccessibilityItem(
                frame: CGRect(x: 300, y: 5, width: 18, height: 18),
                displayBounds: [display]
            ),
            "Application menus on the left side must not be treated as status items."
        )
        try expect(
            !MenuBarScanner.isRightSideAccessibilityItem(
                frame: CGRect(x: 1088, y: 200, width: 18, height: 18),
                displayBounds: [display]
            ),
            "An application control below the menu bar must not be discovered."
        )
        try expect(
            MenuBarScanner.isOpaqueAccessibilityHost(
                rawTitle: "", rawDescription: "", role: "AXGroup",
                subrole: "AXHostingView", bundleIdentifier: "com.apple.MenuBarAgent"
            ),
            "Unnamed MenuBarAgent hosting groups must not become duplicate settings rows."
        )
        try expect(
            !MenuBarScanner.isOpaqueAccessibilityHost(
                rawTitle: "", rawDescription: "", role: "AXMenuBarItem",
                subrole: "AXMenuExtra", bundleIdentifier: "io.tailscale.ipn.macsys"
            ),
            "An unnamed third-party menu extra must remain discoverable through its application identity."
        )
        try expect(
            !MenuBarScanner.isLikelyApplicationMenu(
                attributeName: "AXExtrasMenuBar", title: "Download 149 KB/s, Upload 1 MB/s",
                frame: CGRect(x: 1000, y: 2, width: 57, height: 24)
            ),
            "Long dynamic titles in AXExtrasMenuBar are real status items."
        )
        try expect(
            MenuBarScanner.isLikelyApplicationMenu(
                attributeName: "AXMenuBar", title: "A deliberately long application menu title",
                frame: CGRect(x: 1000, y: 2, width: 180, height: 24)
            ),
            "The AXMenuBar fallback must continue rejecting application menu text."
        )
        let firstDynamicID = MenuBarScanner.accessibilityItemIdentifier(
            bundleIdentifier: "com.bjango.istatmenus.status", title: "CPU 12%",
            occurrence: 1, isProtected: false
        )
        let nextDynamicID = MenuBarScanner.accessibilityItemIdentifier(
            bundleIdentifier: "com.bjango.istatmenus.status", title: "CPU 18%",
            occurrence: 1, isProtected: false
        )
        try expect(
            firstDynamicID == "ax|com.bjango.istatmenus.status|1" && nextDynamicID == firstDynamicID,
            "AX item IDs must stay unique and stable when a live status title changes."
        )
        let migrationIDs = MenuBarScanner.accessibilityLegacyIdentifiers(
            sourceBundleIdentifier: "com.tencent.LemonMonitor",
            resolvedBundleIdentifier: "com.tencent.Lemon",
            title: "Tencent Lemon"
        )
        try expect(
            migrationIDs.contains("window|Control Center|com.tencent.LemonMonitor|0") &&
                migrationIDs.contains("window|控制中心|com.tencent.LemonMonitor|0"),
            "macOS 27 AX items must retain the prior Control Center-hosted rule IDs."
        )
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

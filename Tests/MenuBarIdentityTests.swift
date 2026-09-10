import AppKit
import CoreGraphics

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
@MainActor
private enum MenuBarIdentityTests {
    private static var checks = 0
    static func main() throws {
        let scanner = MenuBarScanner(readWindows: { mirroredWindows() },
                                     readDisplayBounds: { displays },
                                     ownBundleIdentifier: "com.bartuck.app")
        let items = scanner.scan(selectedIDs: [])
        try expect(items.count == 2, "Two mirrored menu items must produce two rows, not four.")
        try expect(Set(items.map(\.id)).count == 2, "Logical menu item IDs must be unique.")
        let removed = MenuBarItem(id: "removed", title: "Menu Bar Item", ownerName: "Control Center",
                                  bundleIdentifier: "com.apple.controlcenter", frame: CGRect(x: 1262, y: 0, width: 34, height: 33),
                                  axElement: nil, isSelected: false, supportsPressAction: false, windowID: 9999, ownerPID: -1)
        let activator = MenuBarItemActivator(readWindows: { mirroredWindows() })
        try expect(activator.visiblePoint(for: removed) == nil, "A disappeared item must never click a neighboring Control Center window.")
        try mirrorBoundaries()
        try rulePersistence()
        try panelPositioning()
        try captureIdentity()
        try stableMirrorIdentity()
        print("MenuBarIdentityTests: \(checks) passed")
    }

    private static func stableMirrorIdentity() throws {
        var windows = mirroredWindows()
        let scanner = MenuBarScanner(readWindows: { windows }, readDisplayBounds: { displays }, ownBundleIdentifier: "com.bartuck.app")
        let original = scanner.scan(selectedIDs: [])
        windows[4] = window(5, "Item-0", x: 900, width: 34, height: 33)
        let moving = scanner.scan(selectedIDs: [])
        try expect(moving.count == 2, "Known mirror pairs must remain unified while one host is moving.")
        try expect(Set(original.map(\.id)) == Set(moving.map(\.id)), "Moving a host must not change the logical row identity.")
        windows[4][kCGWindowName as String] = "org.other.application"
        try expect(scanner.scan(selectedIDs: []).count == 3, "A contradictory application identity must invalidate a cached pair.")
    }

    private static func scan(_ windows: [[String: Any]]) -> [MenuBarItem] {
        MenuBarScanner(readWindows: { windows }, readDisplayBounds: { displays },
                       ownBundleIdentifier: "com.bartuck.app").scan(selectedIDs: [])
    }

    private static func mirrorBoundaries() throws {
        let source = mirroredWindows()
        let items = scan(source)
        let utility = items.first { $0.title == "io.example.utility" }!
        try expect(Set(utility.windowRepresentations.compactMap(\.windowID)) == [5, 6], "Grouping must retain both windows.")
        try expect(utility.activationTarget(on: displays[0]).windowID == 5, "Primary-screen clicks must use the primary copy.")
        try expect(utility.activationTarget(on: displays[1]).windowID == 6, "External-screen clicks must use the external copy.")
        try expect(utility.activationTarget(on: displays[0]).id == utility.id, "Activation must retain the logical rule identity.")
        try expect(scan(source.reversed()).map(\.id) == items.map(\.id), "Enumeration order must not alter logical IDs.")
        try expect(scan(Array(source.dropFirst(4))).count == 4, "Missing anchors must disable mirror inference.")

        var changed = source
        changed[4][kCGWindowName as String] = "org.other.application"
        try expect(scan(changed).count == 3, "Conflicting named applications must remain separate.")
        changed = source
        changed[5] = window(6, "io.example.utility", x: -252, width: 38, height: 30)
        try expect(scan(changed).count == 3, "Different widths must not be merged.")
        changed = source
        changed[5][kCGWindowOwnerPID as String] = -2
        try expect(scan(changed).count == 3, "Different host processes must not be merged.")
        changed = source + [window(9, "Item-0", x: 1228, width: 34, height: 33),
                            window(10, "io.example.utility", x: -286, width: 34, height: 30)]
        let multiple = scan(changed).filter { $0.title == "io.example.utility" }
        try expect(multiple.count == 2, "One app may have two independent menu items.")
        try expect(Set(multiple.map(\.id)).count == 2, "Same-app items must retain independent rules.")
        changed = source + [window(9, "Item-0", x: 1262, width: 34, height: 33)]
        try expect(scan(changed).count == 4, "Ambiguous overlapping slots must not be merged.")
        changed = source
        changed[4] = window(5, "Item-0", x: -720, width: 34, height: 33)
        changed[5] = window(6, "io.example.utility", x: -2234, width: 34, height: 30)
        let hidden = scan(changed).first { $0.title == "io.example.utility" }!
        try expect(hidden.mirrors.count == 1, "Offscreen mirrors must remain associated.")
        try expect(hidden.representation(on: displays[0])?.frame.minX == -720, "A hidden primary copy must not be attributed to the left display.")
        changed = source.map { info in
            var value = info
            var bounds = value[kCGWindowBounds as String] as! [String: Double]
            bounds["Height"] = 33
            value[kCGWindowBounds as String] = bounds
            return value
        }
        try expect(scan(changed).count == 2, "Equal-height displays must use visible screen membership.")
        let unknown = scan([window(90, "", x: 1000, width: 30, height: 33),
                            window(91, "", x: 1030, width: 30, height: 33)])
        try expect(Set(unknown.map(\.displayTitle)).count == 2, "Unidentified rows need distinct labels.")
        try expect(unknown.allSatisfy { !$0.displayTitle.isEmpty }, "Missing names must never become empty labels.")
        try expect(unknown.allSatisfy { $0.id.hasPrefix("session|") }, "Anonymous positional rules must not survive into a different application launch.")
        try expect(scan(source + [window(-1, "invalid", x: 1000, width: 30, height: 33)]).count == 2,
                   "Malformed window IDs must be ignored.")
    }

    private static func rulePersistence() throws {
        let name = "MenuBarIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = PreferencesStore(defaults: defaults)
        let item = MenuBarItem(id: "logical", title: "WiFi", ownerName: "System Menu Bar",
                               bundleIdentifier: "com.apple.controlcenter", frame: .zero, axElement: nil,
                               isSelected: false, supportsPressAction: false, isProtectedSystemItem: true)
        preferences.saveRule(.alwaysHidden, for: item.id)
        try expect(preferences.rule(for: item) == .alwaysHidden, "Refreshing Wi-Fi must retain its manual rule.")
        item.title = "Screen Recording"
        try expect(preferences.rule(for: item) == .alwaysVisible, "Privacy indicators must override persisted hidden rules.")
        item.title = "WiFi"
        item.legacyIDs = ["mirror-a", "mirror-b"]
        preferences.resetRules()
        preferences.saveRule(.alwaysHidden, for: "mirror-a")
        try expect(preferences.rule(for: item) == .alwaysHidden, "Known legacy mirror rules must be preserved.")
        preferences.saveRule(.alwaysVisible, for: "mirror-b")
        try expect(preferences.rule(for: item) == .alwaysVisible, "Conflicting legacy rules must prefer visibility.")
        preferences.saveRule(.automatic, for: item.id)
        try expect(preferences.rule(for: item) == .automatic, "An explicit logical rule must win over legacy aliases.")
        try expect(!preferences.hasCompletedOnboarding, "A new installation must still show onboarding.")
        defaults.set(true, forKey: "hasCompletedOnboarding.0.1.0")
        try expect(preferences.hasCompletedOnboarding, "Patch updates must preserve completed onboarding.")
        preferences.hasCompletedOnboarding = false
        try expect(!preferences.hasCompletedOnboarding, "An explicit onboarding reset must override old completion markers.")
        preferences.hasCompletedOnboarding = true
        try expect(preferences.hasCompletedOnboarding, "New onboarding completion must persist.")
    }

    private static func panelPositioning() throws {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -1920, y: -98, width: 1920, height: 1080)]
        let main = CGRect(x: 1296, y: 952, width: 25, height: 30)
        let external = CGRect(x: -218, y: 952, width: 25, height: 30)
        let left = MenuBarGeometry.panelAnchor(buttonFrames: [main, external], pointer: CGPoint(x: -200, y: 970),
                                               displayFrames: screens, menuBarHeight: 30)
        try expect(left == external, "The pointer display must take precedence over the first hosted window.")
        let fallback = MenuBarGeometry.panelAnchor(buttonFrames: [main], pointer: CGPoint(x: -200, y: 970),
                                                   displayFrames: screens, menuBarHeight: 30)
        try expect(fallback?.midX == -200, "A missing mirror anchor must fall back to the active menu-bar pointer.")
        let invalid = MenuBarGeometry.panelAnchor(buttonFrames: [.zero], pointer: CGPoint(x: 300, y: 300),
                                                  displayFrames: screens, menuBarHeight: 30)
        try expect(invalid == nil, "Invalid hosted frames must not position a panel at the desktop origin.")
        let vertical = MenuBarGeometry.appKitFrame(fromQuartz: CGRect(x: 200, y: -1080, width: 30, height: 30), primaryScreenHeight: 982)
        try expect(vertical.minY == 2032, "Quartz conversion must use the primary origin for vertically arranged displays.")
        let ordinary = MenuBarGeometry.panelAnchor(buttonFrames: [main], pointer: CGPoint(x: 300, y: 300),
                                                   displayFrames: screens, menuBarHeight: 30)
        try expect(ordinary == main, "Programmatic opening away from the bar must retain a valid button anchor.")
    }

    private static func captureIdentity() throws {
        let items = scan(mirroredWindows())
        let targets = MenuBarCaptureService.captureTargets(for: items)
        try expect(targets.count == 4, "Both display copies must be tried for icon capture.")
        try expect(Set(targets.map(\.itemID)).count == 2, "Captured copies must map to two logical icons.")
        try expect(Set(targets.map(\.windowID)) == [5, 6, 7, 8], "Capture must target only the matching physical windows.")
        let utility = items.first { $0.title == "io.example.utility" }!
        utility.resolvedApplicationIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        try expect(!utility.hasUsableDisplayIcon, "An application fallback is not proof that the menu-bar glyph was captured.")
        utility.iconImage = NSImage(size: NSSize(width: 24, height: 24))
        try expect(utility.hasUsableDisplayIcon, "A captured menu-bar glyph makes the item ready for layout.")
        utility.isProtectedSystemItem = true
        try expect(!utility.usesTemplateIcon, "Captured system glyphs must retain their original colors.")
        try expect(MenuBarSystemItemClassifier.canonicalName("BentoBox-0") == "Control Center", "The Control Center launcher must not be mislabeled as screen recording.")
        try expect(MenuItemSafetyPolicy.mustRemainVisible(title: "Control Center"), "The system control entry must remain reachable.")
    }

    private static let displays = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   CGRect(x: -1920, y: 0, width: 1920, height: 1080)]

    private static func mirroredWindows() -> [[String: Any]] {
        [window(1, "BarTuckControlItem", x: 1296, width: 25, height: 33),
         window(2, "com.bartuck.app", x: -218, width: 25, height: 30),
         window(3, "BarTuckHiddenSection", x: -700, width: 2003, height: 33),
         window(4, "com.bartuck.app", x: -2214, width: 2003, height: 30),
         window(5, "Item-0", x: 1262, width: 34, height: 33),
         window(6, "io.example.utility", x: -252, width: 34, height: 30),
         window(7, "Clock", x: 1363, width: 151, height: 33),
         window(8, "", x: -151, width: 151, height: 30)]
    }

    private static func window(_ id: Int, _ title: String, x: Double,
                               width: Double, height: Double) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: -1,
         kCGWindowOwnerName as String: "Control Center", kCGWindowName as String: title,
         kCGWindowLayer as String: 25, kCGWindowIsOnscreen as String: true,
         kCGWindowBounds as String: ["X": x, "Y": 0.0, "Width": width, "Height": height]]
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        if !condition { throw TestFailure(description: message) }
    }
}

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
                                     ownBundleIdentifier: "com.bartuck.app",
                                     platformPolicy: MenuBarPlatformPolicy(majorVersion: 26))
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
        try favoriteFiltering()
        try panelPositioning()
        try captureIdentity()
        try iconPresentation()
        try dingTalkNotificationPresentation()
        try inputSourcePresentation()
        try applicationIdentityResolution()
        try macOS27AccessibilityDiscoveryBoundaries()
        try accessibilityItemsDoNotMergeAcrossApplications()
        try ownedStatusItemsStayExcluded()
        try accessibilityRestorationFrame()
        try stableMirrorIdentity()
        try actualVisibility()
        print("MenuBarIdentityTests: \(checks) passed")
    }

    private static func actualVisibility() throws {
        try expect(MenuItemSafetyPolicy.mustRemainVisible(title: "Clock"), "The fixed system clock must not block movable items.")
        try expect(MenuItemVisibility.evaluate([true, true]) == .visible, "Selected but visible copies are not hidden.")
        try expect(MenuItemVisibility.evaluate([false, false]) == .hidden, "Both hidden copies count as hidden.")
        try expect(MenuItemVisibility.evaluate([true, false]) == .partial, "A visible mirror prevents claiming full hiding.")
        try expect(MenuItemVisibility.evaluate([false, nil]) == .unknown, "A missing window is not proof of hidden status.")
        try expect(MenuItemVisibility.evaluate([]) == .unknown, "No window data must not count as hidden.")
        let utility = scan(mirroredWindows()).first { $0.title == "io.example.utility" }!
        utility.isSelected = true
        utility.updateVisibility(displayBounds: displays)
        try expect(utility.visibility == .visible, "A hidden rule must not change actual visibility.")
        let outside = CGRect(x: -6000, y: 0, width: 34, height: 33)
        utility.updateVisibility(displayBounds: displays, currentFrames: [5: outside, 6: outside])
        try expect(utility.visibility == .hidden, "Fresh WindowServer bounds must determine hidden state.")
        utility.updateVisibility(displayBounds: displays, currentFrames: [5: outside])
        try expect(utility.visibility == .unknown, "Disappeared mirrors invalidate the hidden claim.")

        let axItem = MenuBarItem(id: "ax-item", title: "Utility", ownerName: "Utility",
                                 bundleIdentifier: "com.example.utility",
                                 frame: CGRect(x: -255, y: 2, width: 23, height: 24),
                                 axElement: nil, isSelected: true, supportsPressAction: true)
        axItem.sourceDisplayBounds = displays[1]
        axItem.updateVisibility(displayBounds: displays, frameProvider: { _ in outside })
        try expect(axItem.visibility == .hidden,
                   "A live AX frame outside the leftmost display must confirm hidden state.")
        axItem.updateVisibility(displayBounds: displays, frameProvider: { _ in nil })
        try expect(axItem.visibility == .unknown,
                   "A missing live AX frame must not reuse a stale frame to claim success.")
    }

    private static func stableMirrorIdentity() throws {
        var windows = mirroredWindows()
        let scanner = MenuBarScanner(readWindows: { windows }, readDisplayBounds: { displays },
                                     ownBundleIdentifier: "com.bartuck.app",
                                     platformPolicy: MenuBarPlatformPolicy(majorVersion: 26))
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
                       ownBundleIdentifier: "com.bartuck.app",
                       platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)).scan(selectedIDs: [])
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

    private static func favoriteFiltering() throws {
        func item(_ id: String, _ title: String, _ visibility: MenuItemVisibility) -> MenuBarItem {
            let item = MenuBarItem(id: id, title: title, ownerName: "Notes",
                bundleIdentifier: "com.example.notes", frame: .zero,
                axElement: nil, isSelected: true, supportsPressAction: false)
            item.visibility = visibility
            return item
        }
        let hidden = item("hidden", "Clipboard", .hidden)
        let temporary = item("temporary", "输入法", .hidden)
        let pending = item("pending", "Pending", .visible)
        let unknown = item("unknown", "Unknown", .unknown)
        let partial = item("partial", "Partial", .partial)
        let items = [hidden, temporary, pending, unknown, partial]
        let favorites: Set<String> = [temporary.id, partial.id, "missing-app"]
        func matches(_ filter: MenuBarItemFilter, _ query: String = "") -> [String] {
            MenuBarItemCollection.filtered(items, filter: filter, query: query,
                favoriteIDs: favorites, temporaryIDs: [temporary.id], language: .simplifiedChinese).map(\.id)
        }
        try expect(matches(.all) == items.map(\.id), "All must retain menu order.")
        try expect(matches(.favorites) == [temporary.id, partial.id], "Favorites must not create missing app rows.")
        try expect(matches(.tucked) == [hidden.id], "Tucked must exclude temporary, pending and unconfirmed items.")
        try expect(matches(.temporary) == [temporary.id], "Temporary must follow the explicit reveal state.")
        try expect(matches(.favorites, "  输入  ") == [temporary.id], "Chinese search must combine with filters and trim whitespace.")
        try expect(matches(.tucked, "CLIP") == [hidden.id], "English search must ignore case.")
        try expect(matches(.tucked, "notes") == [hidden.id], "Search must match the owning application.")
        try expect(matches(.temporary, "clipboard").isEmpty, "Search must not escape the selected filter.")
        try expect(matches(.all, "\n ") == items.map(\.id), "Whitespace must not hide all rows.")
        try expect(matches(.all, "not-present").isEmpty, "Unknown text must produce an empty result.")
        let groups = MenuBarItemCollection.matchingGroups(items, query: " notes ",
            favoriteIDs: favorites, temporaryIDs: [temporary.id], language: .english)
        try expect(groups[.all]?.map(\.id) == items.map(\.id) && groups[.favorites]?.count == 2,
                   "One search snapshot must preserve row order and favorite counts.")
        try expect(groups[.tucked]?.map(\.id) == [hidden.id] && groups[.temporary]?.map(\.id) == [temporary.id],
                   "Search counts must separate confirmed tucked and temporary items.")
        let expectedOrder = [temporary.id, partial.id, hidden.id, pending.id, unknown.id]
        try expect(MenuBarItemCollection.favoritesFirst(items, favoriteIDs: favorites).map(\.id) == expectedOrder,
                   "Favorites and regular items must both preserve their original relative order.")
        temporary.title = "99+"
        try expect(MenuBarItemCollection.favoritesFirst(items, favoriteIDs: favorites).map(\.id) == expectedOrder,
                   "Notification changes must not reorder tray icons.")
        hidden.legacyIDs = ["legacy-hidden"]
        try expect(MenuBarItemCollection.isFavorite(hidden, favoriteIDs: ["legacy-hidden"]),
                   "Favorites must survive a known item identity migration.")
        try expect(MenuBarItemCollection.favoritesFirst([], favoriteIDs: favorites).isEmpty,
                   "Favorites must not synthesize entries in an empty tray.")

        let domain = "FavoritePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = PreferencesStore(defaults: defaults)
        try expect(preferences.favoriteItemIDs.isEmpty, "New installations must start without favorites.")
        preferences.favoriteItemIDs = favorites
        try expect(PreferencesStore(defaults: defaults).favoriteItemIDs == favorites,
                   "Favorites must survive a new preferences instance.")
        preferences.resetLayoutState()
        try expect(preferences.favoriteItemIDs == favorites, "Layout reset must preserve personal favorites.")
        preferences.favoriteItemIDs = []
        try expect(PreferencesStore(defaults: defaults).favoriteItemIDs.isEmpty,
                   "Removing the final favorite must persist an empty set.")
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

    private static func iconPresentation() throws {
        let captured = NSImage(size: NSSize(width: 24, height: 24))
        captured.isTemplate = true
        let bundled = NSImage(size: NSSize(width: 64, height: 64))
        let resolved = NSImage(size: NSSize(width: 128, height: 128))
        let thirdParty = MenuBarItem(
            id: "third-party",
            title: "com.example.utility",
            ownerName: "Control Center",
            bundleIdentifier: "Control Center",
            frame: .zero,
            axElement: nil,
            iconImage: captured,
            applicationIcon: bundled,
            isSelected: true,
            supportsPressAction: false
        )
        thirdParty.resolvedApplicationIcon = resolved

        try expect(thirdParty.displayImage === resolved,
                   "Third-party tray items must prefer the resolved application icon over the captured monochrome glyph.")
        try expect(!thirdParty.usesTemplateIcon,
                   "Tray rendering must use the template flag from the application icon actually selected for display.")
        try expect(thirdParty.menuBarImage === captured,
                   "Settings must retain the captured menu-bar glyph when one is available.")
        let system = MenuBarItem(
            id: "system",
            title: "WiFi",
            ownerName: "System Menu Bar",
            bundleIdentifier: "com.apple.controlcenter",
            frame: .zero,
            axElement: nil,
            iconImage: captured,
            applicationIcon: bundled,
            isSelected: false,
            supportsPressAction: false,
            isProtectedSystemItem: true
        )
        system.resolvedApplicationIcon = resolved
        try expect(system.displayImage === captured,
                   "Protected system tray items must keep their specific captured status icon.")
        try expect(system.usesTemplateIcon,
                   "System tray rendering must retain the selected captured icon's template behavior.")

        let fallback = MenuBarItem(
            id: "fallback",
            title: "Utility",
            ownerName: "Utility",
            bundleIdentifier: "com.example.utility",
            frame: .zero,
            axElement: nil,
            iconImage: captured,
            isSelected: true,
            supportsPressAction: false
        )
        try expect(fallback.displayImage === captured,
                   "A third-party tray item without an application icon must fall back to its captured glyph.")
    }

    private static func dingTalkNotificationPresentation() throws {
        let item = MenuBarItem(
            id: "ding-talk", title: "1", ownerName: "钉钉",
            bundleIdentifier: "5ZSL2CJU2T.com.dingtalk.mac", frame: .zero,
            axElement: nil, isSelected: false, supportsPressAction: true
        )
        try expect(item.displayTitle(for: .simplifiedChinese) == "钉钉 1",
                   "A DingTalk notification count must include the application name.")
        try expect(item.tooltip(for: .simplifiedChinese) == "钉钉 1",
                   "A notification count must not repeat the application name in its tooltip.")
        try expect(item.showsNotificationCountInTitle,
                   "The settings row must not repeat DingTalk as a subtitle.")
        item.title = "12"
        try expect(item.displayTitle(for: .simplifiedChinese) == "钉钉 12",
                   "A changing notification count must update the label.")
        item.title = "消息"
        try expect(item.displayTitle(for: .simplifiedChinese) == "消息" && !item.showsNotificationCountInTitle,
                   "A nonnumeric DingTalk status title must remain unchanged.")

        let metric = MenuBarItem(
            id: "metric", title: "1", ownerName: "iStat Menus",
            bundleIdentifier: "com.bjango.istatmenus.status", frame: .zero,
            axElement: nil, isSelected: false, supportsPressAction: true
        )
        try expect(metric.displayTitle(for: .english) == "1" && !metric.showsNotificationCountInTitle,
                   "Numeric status titles from unrelated apps must not be treated as notifications.")

        let weChat = MenuBarItem(
            id: "wechat", title: " 1", ownerName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat", frame: .zero,
            axElement: nil, isSelected: false, supportsPressAction: true
        )
        try expect(weChat.displayTitle(for: .simplifiedChinese) == "微信 1" &&
                   weChat.tooltip(for: .simplifiedChinese) == "微信 1" &&
                   weChat.showsNotificationCountInTitle,
                   "WeChat unread counts must retain the application name.")
        weChat.title = "99+"
        try expect(weChat.displayTitle(for: .english) == "微信 99+",
                   "Capped unread counts must retain the application name.")
        weChat.title = "Connected"
        try expect(weChat.displayTitle(for: .english) == "Connected" &&
                   !weChat.showsNotificationCountInTitle,
                   "Nonnumeric WeChat status text must stay unchanged.")
    }

    private static func inputSourcePresentation() throws {
        let captured = NSImage(size: NSSize(width: 24, height: 24))
        captured.isTemplate = true
        let genericApplicationIcon = NSImage(size: NSSize(width: 128, height: 128))
        let inputSource = MenuBarItem(
            id: "input-source",
            title: "com.apple.TextInputMenuAgent",
            ownerName: "Control Center",
            bundleIdentifier: "com.apple.TextInputMenuAgent",
            frame: .zero,
            axElement: nil,
            iconImage: captured,
            applicationIcon: genericApplicationIcon,
            isSelected: true,
            supportsPressAction: false
        )
        inputSource.resolvedApplicationIcon = genericApplicationIcon

        try expect(MenuBarSystemItemClassifier.canonicalName("com.apple.TextInputMenuAgent") == "Input Source",
                   "The input-source agent must use a readable menu item name.")
        try expect(inputSource.displayImage === captured,
                   "The input-source tray entry must keep its captured menu-bar glyph instead of a generic app icon.")
        try expect(!inputSource.usesApplicationIconForDisplay,
                   "The input-source agent must not be styled as a third-party application icon.")
        try expect(inputSource.fallbackSymbolName == "keyboard",
                   "The input-source fallback must remain recognizable when capture is unavailable.")
    }

    private static func applicationIdentityResolution() throws {
        let helperURL = URL(fileURLWithPath: "/Applications/Tencent Lemon.app/Contents/Library/LoginItems/LemonMonitor.app")
        let outerURL = URL(fileURLWithPath: "/Applications/Tencent Lemon.app")
        let helperIcon = NSImage(size: NSSize(width: 32, height: 32))
        let outerIcon = NSImage(size: NSSize(width: 128, height: 128))
        var metadataReads = 0
        let resolver = MenuBarApplicationIdentityResolver(
            runningApplication: { bundleIdentifier in
                guard bundleIdentifier == "com.tencent.LemonMonitor" else { return nil }
                return .init(displayName: "LemonMonitor", bundleIdentifier: bundleIdentifier,
                             bundleURL: helperURL, icon: helperIcon)
            },
            installedApplicationURL: { _ in nil },
            applicationMetadata: { url in
                metadataReads += 1
                guard url == outerURL else { return nil }
                return .init(displayName: "Tencent Lemon", bundleIdentifier: "com.tencent.Lemon",
                             bundleURL: url, icon: outerIcon)
            }
        )

        try expect(MenuBarApplicationIdentityResolver.outermostApplicationURL(for: helperURL) == outerURL,
                   "A nested login item must resolve to its outer application bundle.")
        let first = resolver.resolve(bundleIdentifier: "com.tencent.LemonMonitor")
        let second = resolver.resolve(bundleIdentifier: "com.tencent.LemonMonitor")
        try expect(first?.displayName == "Tencent Lemon" && first?.bundleIdentifier == "com.tencent.Lemon",
                   "A helper process must be labeled with the outer application's identity.")
        try expect(first?.icon === outerIcon,
                   "A helper process must use the outer application's own icon.")
        try expect(second?.icon === first?.icon && metadataReads == 1,
                   "Application identity and NSImage instances must be reused across scans.")

        let scanner = MenuBarScanner(
            readWindows: { [window(120, "com.tencent.LemonMonitor", x: 1000, width: 30, height: 30)] },
            readDisplayBounds: { [CGRect(x: 0, y: 0, width: 1512, height: 982)] },
            ownBundleIdentifier: "com.bartuck.app",
            applicationResolver: resolver,
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let scanned = scanner.scan(selectedIDs: []).first
        try expect(scanned?.displayTitle(for: .english) == "Tencent Lemon",
                   "Window-backed helper items must expose the outer application name.")
        try expect(scanned?.menuBarHostBundleIdentifier == "com.tencent.LemonMonitor",
                   "The real menu-bar host must stay separate from the outer application identity.")
        try expect(scanned?.displayImage === outerIcon,
                   "Window-backed helper items must expose the cached outer application icon.")
        try expect(MenuBarApplicationIdentityResolver.declaresApplicationIcon([
            "CFBundleIconName": "AppIcon"
        ]), "Asset-catalog app icons must be recognized.")
        try expect(MenuBarApplicationIdentityResolver.declaresApplicationIcon([
            "CFBundleIconFiles": ["LegacyIcon"]
        ]), "Legacy macOS icon arrays must be recognized.")
        try expect(MenuBarApplicationIdentityResolver.declaresApplicationIcon([
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconName": "AppIcon"]]
        ]), "Nested bundle icon dictionaries must be recognized.")
        try expect(!MenuBarApplicationIdentityResolver.declaresApplicationIcon([:]),
                   "A helper without declared icon metadata must keep the captured menu-bar fallback.")
    }

    private static func macOS27AccessibilityDiscoveryBoundaries() throws {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let compositeHost = CGRect(x: 756, y: 0, width: 756, height: 30)
        let discreteWindow = CGRect(x: 1372, y: 0, width: 34, height: 30)
        let accessibilityChild = CGRect(x: 1374, y: 0, width: 30, height: 30)

        try expect(!MenuBarScanner.isDiscreteAccessibilitySeed(
            frame: compositeHost,
            displayBounds: [display]
        ), "A composite menu-bar host must never be used for AX enrichment.")
        try expect(MenuBarScanner.isDiscreteAccessibilitySeed(
            frame: discreteWindow,
            displayBounds: [display]
        ), "A real per-item status window can enrich the hybrid compatibility path.")
        try expect(!MenuBarScanner.framesRepresentSameItem(compositeHost, accessibilityChild),
                   "A composite host must not match every overlapping AX child.")
        try expect(MenuBarScanner.framesRepresentSameItem(discreteWindow, accessibilityChild),
                   "Similar per-item WindowServer and AX frames must still merge.")
    }

    private static func accessibilityItemsDoNotMergeAcrossApplications() throws {
        let tailscaleFrame = CGRect(x: 1229.5, y: 4.5, width: 24, height: 24)
        let snipasteFrame = CGRect(x: 1223, y: 4.5, width: 24, height: 24)

        try expect(
            !MenuBarScanner.accessibilityItemMatches(
                existingOwnerPID: 2311,
                existingHasAccessibilityElement: true,
                existingFrame: tailscaleFrame,
                existingTitle: "Tailscale",
                candidateOwnerPID: 2316,
                candidateFrame: snipasteFrame,
                candidateTitle: "Snipaste"
            ),
            "Overlapping AX items from different applications must remain independent."
        )
        try expect(
            MenuBarScanner.accessibilityItemMatches(
                existingOwnerPID: 1110,
                existingHasAccessibilityElement: false,
                existingFrame: tailscaleFrame,
                existingTitle: "io.tailscale.ipn.macsys",
                candidateOwnerPID: 2311,
                candidateFrame: tailscaleFrame,
                candidateTitle: "Tailscale"
            ),
            "A WindowServer seed may still be enriched by its originating AX item."
        )
    }

    private static func ownedStatusItemsStayExcluded() throws {
        let baselineScanner = MenuBarScanner(
            readWindows: { mirroredWindows() },
            readDisplayBounds: { displays },
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )
        let extraSeparators = [
            window(101, "BarTuckHiddenSection2", x: -900, width: 680, height: 33),
            window(102, "BarTuckHiddenSection3", x: -1_580, width: 680, height: 33)
        ]
        let scanner = MenuBarScanner(
            readWindows: { mirroredWindows() + extraSeparators },
            readDisplayBounds: { displays },
            ownBundleIdentifier: "com.bartuck.app",
            platformPolicy: MenuBarPlatformPolicy(majorVersion: 26)
        )

        try expect(
            scanner.scan(selectedIDs: []).map(\.id) == baselineScanner.scan(selectedIDs: []).map(\.id),
            "Every MacBarTuck overflow spacer must stay out of the menu-item list."
        )
        try expect(
            scanner.windowSignature() == baselineScanner.windowSignature(),
            "Overflow spacer creation must not look like an external menu-bar change."
        )
    }

    private static func accessibilityRestorationFrame() throws {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 1372, y: 0, width: 34, height: 30)
        let hiddenFrame = CGRect(x: -50, y: 0, width: 34, height: 30)
        let movedVisibleFrame = CGRect(x: 1320, y: 0, width: 34, height: 30)
        let item = MenuBarItem(
            id: "ax-item",
            title: "Status",
            ownerName: "Utility",
            bundleIdentifier: "com.example.utility",
            frame: visibleFrame,
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )
        let hiddenScan = MenuBarItem(
            id: item.id,
            title: item.title,
            ownerName: item.ownerName,
            bundleIdentifier: item.bundleIdentifier,
            frame: hiddenFrame,
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )

        item.updateRuntimeState(from: hiddenScan, displayBounds: [display])
        try expect(item.frame == hiddenFrame,
                   "Refresh must retain the current offscreen AX frame for visibility checks.")
        try expect(item.restorationFrame == visibleFrame,
                   "An offscreen refresh must not overwrite the last usable AX restore position.")

        let visibleScan = MenuBarItem(
            id: item.id,
            title: item.title,
            ownerName: item.ownerName,
            bundleIdentifier: item.bundleIdentifier,
            frame: movedVisibleFrame,
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )
        item.updateRuntimeState(from: visibleScan, displayBounds: [display])
        try expect(item.restorationFrame == movedVisibleFrame,
                   "A later visible AX position must become the new restore position.")
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

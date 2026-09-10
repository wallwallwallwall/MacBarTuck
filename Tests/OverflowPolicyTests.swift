import Foundation
import CoreGraphics

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(message)\nExpected: \(expected)\nActual:   \(actual)")
    }
}

private func item(
    _ id: String,
    width: Double,
    position: Double,
    rule: MenuItemRule = .automatic,
    protected: Bool = false,
    offscreen: Bool = false
) -> OverflowPolicyItem {
    OverflowPolicyItem(
        id: id,
        width: width,
        position: position,
        rule: rule,
        isProtected: protected,
        isOffscreen: offscreen
    )
}

@main
private enum OverflowPolicyTests {
    static func main() throws {
        try alwaysHiddenWins()
        try protectedItemsStayVisible()
        try hidesLeftmostAutomaticItemsUntilContentFits()
        try alwaysVisibleItemsStillConsumeCapacity()
        try noNotchOnlyRecoversAlreadyOffscreenItems()
        try ruleCodecRoundTripsKnownValues()
        try ruleCodecFallsBackForUnknownValues()
        try missingRuleDefaultsToAutomatic()
        try mostConstrainedNotchedDisplayWins()
        try noNotchedDisplayHasNoConstraint()
        try leftSideDisplayItemsRemainVisible()
        try itemsOutsideEveryDisplayAreOffscreen()
        try leftSideDisplayItemsAreNotHiddenLaneItems()
        try itemsBeyondTheLeftmostDisplayUseTheHiddenLane()
        try regularSystemControlsRemainConfigurable()
        try privacyIndicatorsMustRemainVisible()
        print("OverflowPolicyTests: 16 passed")
    }

    private static func alwaysHiddenWins() throws {
        let items = [
            item("hidden", width: 28, position: 10, rule: .alwaysHidden),
            item("auto", width: 28, position: 40)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 200),
            Set(["hidden"]),
            "Always-hidden items must remain managed even when space is available."
        )
    }

    private static func protectedItemsStayVisible() throws {
        let items = [
            item("recording", width: 34, position: 5, rule: .alwaysHidden, protected: true),
            item("utility", width: 34, position: 40, rule: .alwaysHidden)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 20),
            Set(["utility"]),
            "Protected system indicators must never be hidden."
        )
    }

    private static func hidesLeftmostAutomaticItemsUntilContentFits() throws {
        let items = [
            item("left", width: 40, position: 10),
            item("middle", width: 35, position: 50),
            item("right", width: 35, position: 85)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 70),
            Set(["left"]),
            "Automatic overflow must hide the furthest-left item first."
        )
    }

    private static func alwaysVisibleItemsStillConsumeCapacity() throws {
        let items = [
            item("auto-left", width: 30, position: 5),
            item("auto-right", width: 30, position: 35),
            item("clock", width: 40, position: 70, rule: .alwaysVisible)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 60),
            Set(["auto-left", "auto-right"]),
            "Automatic items must make room for items that are forced visible."
        )
    }

    private static func noNotchOnlyRecoversAlreadyOffscreenItems() throws {
        let items = [
            item("onscreen", width: 30, position: 20),
            item("offscreen", width: 30, position: -30, offscreen: true),
            item("hidden", width: 30, position: 50, rule: .alwaysHidden)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: nil),
            Set(["offscreen", "hidden"]),
            "Without a notch constraint, automatic rules should only recover offscreen items."
        )
    }

    private static func ruleCodecRoundTripsKnownValues() throws {
        let rules: [String: MenuItemRule] = [
            "chat": .alwaysHidden,
            "vpn": .alwaysVisible,
            "sync": .automatic
        ]
        let encoded = MenuItemRuleCodec.encode(rules)
        try expectEqual(
            MenuItemRuleCodec.decode(encoded),
            rules,
            "Known rule values must survive UserDefaults-compatible encoding."
        )
    }

    private static func ruleCodecFallsBackForUnknownValues() throws {
        let decoded = MenuItemRuleCodec.decode([
            "known": "alwaysHidden",
            "future": "newRuleFromLaterVersion"
        ])
        try expectEqual(decoded["known"], .alwaysHidden, "Known raw values must decode normally.")
        try expectEqual(decoded["future"], .automatic, "Unknown raw values must fall back to automatic.")
    }

    private static func missingRuleDefaultsToAutomatic() throws {
        try expectEqual(
            MenuItemRuleCodec.rule(for: "missing", in: ["known": "alwaysVisible"]),
            .automatic,
            "Items without a stored rule must default to automatic."
        )
    }

    private static func mostConstrainedNotchedDisplayWins() throws {
        let displays = [
            DisplayConstraintCandidate(id: 1, availableMenuWidth: 664),
            DisplayConstraintCandidate(id: 2, availableMenuWidth: nil),
            DisplayConstraintCandidate(id: 3, availableMenuWidth: 520)
        ]
        try expectEqual(
            DisplayConstraint.minimumAvailableWidth(from: displays),
            520,
            "Automatic layout must satisfy the narrowest connected notched display."
        )
    }

    private static func noNotchedDisplayHasNoConstraint() throws {
        let displays = [
            DisplayConstraintCandidate(id: 1, availableMenuWidth: nil),
            DisplayConstraintCandidate(id: 2, availableMenuWidth: nil)
        ]
        try expectEqual(
            DisplayConstraint.minimumAvailableWidth(from: displays),
            nil,
            "Roomy non-notched displays must not trigger automatic hiding."
        )
    }

    private static func leftSideDisplayItemsRemainVisible() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        ]
        let item = CGRect(x: -1840, y: 0, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isOffscreenMenuItem(item, displayBounds: displays),
            false,
            "A menu item on a display left of the main display is still visible."
        )
    }

    private static func itemsOutsideEveryDisplayAreOffscreen() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        ]
        let item = CGRect(x: -1990, y: 0, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isOffscreenMenuItem(item, displayBounds: displays),
            true,
            "Only items outside every active display should count as hidden."
        )
    }

    private static func leftSideDisplayItemsAreNotHiddenLaneItems() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        ]
        let item = CGRect(x: -1840, y: 0, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isHiddenLaneMenuItem(item, displayBounds: displays),
            false,
            "A real menu item on a display left of the main display must not be treated as staged offscreen."
        )
    }

    private static func itemsBeyondTheLeftmostDisplayUseTheHiddenLane() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        ]
        let item = CGRect(x: -1970, y: 0, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isHiddenLaneMenuItem(item, displayBounds: displays),
            true,
            "The hidden lane begins only beyond the left edge of every active display."
        )
    }

    private static func regularSystemControlsRemainConfigurable() throws {
        try expectEqual(
            MenuItemSafetyPolicy.mustRemainVisible(title: "WiFi"),
            false,
            "Regular system controls such as Wi-Fi should remain configurable."
        )
    }

    private static func privacyIndicatorsMustRemainVisible() throws {
        try expectEqual(
            MenuItemSafetyPolicy.mustRemainVisible(title: "Screen Recording"),
            true,
            "Active privacy indicators must never be hidden from the menu bar."
        )
        try expectEqual(
            MenuItemSafetyPolicy.mustRemainVisible(title: "Audio and Video Controls"),
            true,
            "Active camera and microphone indicators must never be hidden from the menu bar."
        )
    }
}

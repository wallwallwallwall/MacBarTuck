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
        try exactFitKeepsAutomaticItemsVisible()
        try zeroCapacityHidesAllAutomaticItems()
        try negativeCapacityBehavesLikeZero()
        try protectedOffscreenItemsStayVisible()
        try alwaysVisibleOffscreenItemsStayVisible()
        try offscreenAutomaticItemsDoNotConsumeCapacity()
        try equalPositionsUseStableIdentifierOrder()
        try negativeWidthsDoNotConsumeCapacity()
        try emptyPolicyInputIsStable()
        try ruleCodecIgnoresNonStringValues()
        try unconstrainedDisplaysDoNotMaskNotchConstraint()
        try rightSideDisplayItemsRemainVisible()
        try verticallyOffsetDisplayItemsRemainVisible()
        try appKitCoordinateMenuBarItemsRemainVisible()
        try ordinaryWindowsAreRejected()
        try tinyFramesAreRejected()
        try emptyDisplaySetHasNoMenuBarItems()
        try safetyPolicyNormalizesSpacingAndCase()
        try previewAutomaticRulesRespectAvoidanceToggle()
        try previewManualAndProtectedRulesTakePrecedence()
        print("OverflowPolicyTests: 36 passed")
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

    private static func exactFitKeepsAutomaticItemsVisible() throws {
        let items = [
            item("left", width: 30, position: 10),
            item("right", width: 40, position: 40)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 70),
            Set<String>(),
            "Items that exactly fit the notch-safe capacity must remain visible."
        )
    }

    private static func zeroCapacityHidesAllAutomaticItems() throws {
        let items = [
            item("left", width: 30, position: 10),
            item("right", width: 40, position: 40)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 0),
            Set(["left", "right"]),
            "A zero-width safe area must overflow every automatic item."
        )
    }

    private static func negativeCapacityBehavesLikeZero() throws {
        let items = [item("utility", width: 28, position: 10)]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: -50),
            Set(["utility"]),
            "Defensive handling must clamp an invalid negative capacity to zero."
        )
    }

    private static func protectedOffscreenItemsStayVisible() throws {
        let items = [
            item("privacy", width: 28, position: -40, protected: true, offscreen: true)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: nil),
            Set<String>(),
            "A protected privacy item must not become managed even if reported offscreen."
        )
    }

    private static func alwaysVisibleOffscreenItemsStayVisible() throws {
        let items = [
            item("pinned", width: 28, position: -40, rule: .alwaysVisible, offscreen: true)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 0),
            Set<String>(),
            "Always-visible rules must take precedence over offscreen recovery and capacity pressure."
        )
    }

    private static func offscreenAutomaticItemsDoNotConsumeCapacity() throws {
        let items = [
            item("offscreen", width: 40, position: -40, offscreen: true),
            item("visible", width: 40, position: 20)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 40),
            Set(["offscreen"]),
            "An already-managed offscreen item must not force an additional visible item into overflow."
        )
    }

    private static func equalPositionsUseStableIdentifierOrder() throws {
        let items = [
            item("z-item", width: 30, position: 10),
            item("a-item", width: 30, position: 10)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 30),
            Set(["a-item"]),
            "Equal positions must use stable identifiers for deterministic overflow selection."
        )
    }

    private static func negativeWidthsDoNotConsumeCapacity() throws {
        let items = [
            item("invalid", width: -30, position: 5),
            item("valid", width: 30, position: 35)
        ]
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: items, availableWidth: 30),
            Set<String>(),
            "Invalid negative item widths must not increase layout pressure."
        )
    }

    private static func emptyPolicyInputIsStable() throws {
        try expectEqual(
            OverflowPolicy.managedItemIDs(from: [], availableWidth: 0),
            Set<String>(),
            "An empty scan must produce an empty managed set."
        )
    }

    private static func ruleCodecIgnoresNonStringValues() throws {
        let stored: [String: Any] = [
            "known": "alwaysVisible",
            "invalid": 42
        ]
        try expectEqual(
            MenuItemRuleCodec.decode(stored),
            ["known": .alwaysVisible],
            "Corrupt non-string UserDefaults entries must be ignored without losing valid rules."
        )
    }

    private static func unconstrainedDisplaysDoNotMaskNotchConstraint() throws {
        let displays = [
            DisplayConstraintCandidate(id: 1, availableMenuWidth: nil),
            DisplayConstraintCandidate(id: 2, availableMenuWidth: 580),
            DisplayConstraintCandidate(id: 3, availableMenuWidth: nil)
        ]
        try expectEqual(
            DisplayConstraint.minimumAvailableWidth(from: displays),
            580,
            "External displays without a notch must not mask the connected notch constraint."
        )
    }

    private static func rightSideDisplayItemsRemainVisible() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        ]
        let item = CGRect(x: 1600, y: 0, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isVisibleMenuBarItem(item, displayBounds: displays),
            true,
            "A menu item on an external display to the right must remain visible."
        )
    }

    private static func verticallyOffsetDisplayItemsRemainVisible() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        ]
        let item = CGRect(x: 1700, y: -1080, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isVisibleMenuBarItem(item, displayBounds: displays),
            true,
            "A menu item on a vertically offset display must use that display's own menu-bar edge."
        )
    }

    private static func appKitCoordinateMenuBarItemsRemainVisible() throws {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let item = CGRect(x: 1400, y: 958, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isVisibleMenuBarItem(item, displayBounds: [display]),
            true,
            "Menu-bar frames expressed in AppKit bottom-left coordinates must be recognized."
        )
    }

    private static func ordinaryWindowsAreRejected() throws {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let window = CGRect(x: 1200, y: 200, width: 80, height: 24)
        try expectEqual(
            MenuBarGeometry.isMenuBarItem(window, displayBounds: [display]),
            false,
            "A normal window with status-item-like height must not be mistaken for a menu-bar item."
        )
    }

    private static func tinyFramesAreRejected() throws {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = CGRect(x: 1400, y: 0, width: 3, height: 3)
        try expectEqual(
            MenuBarGeometry.isMenuBarItem(frame, displayBounds: [display]),
            false,
            "Tiny WindowServer artifacts must be filtered before menu-bar classification."
        )
    }

    private static func emptyDisplaySetHasNoMenuBarItems() throws {
        let frame = CGRect(x: 100, y: 0, width: 28, height: 24)
        try expectEqual(
            MenuBarGeometry.isMenuBarItem(frame, displayBounds: []),
            false,
            "No frame can be considered a visible or hidden menu-bar item without an active display."
        )
    }

    private static func safetyPolicyNormalizesSpacingAndCase() throws {
        try expectEqual(
            MenuItemSafetyPolicy.mustRemainVisible(title: "  SCREEN  RECORDING  "),
            true,
            "Privacy indicator matching must be insensitive to spacing and case."
        )
        try expectEqual(
            MenuItemSafetyPolicy.mustRemainVisible(title: "Audio  And  Video  Controls"),
            true,
            "Audio/video privacy controls must remain protected after title normalization."
        )
    }

    private static func previewAutomaticRulesRespectAvoidanceToggle() throws {
        let automaticIDs = Set(["window", "clipboard"])
        try expectEqual(
            PreviewSelectionPolicy.isManaged(
                itemID: "window",
                rule: .automatic,
                isProtected: false,
                automaticAvoidanceEnabled: false,
                automaticManagedIDs: automaticIDs
            ),
            false,
            "Preview automatic rules must stop managing items when automatic avoidance is disabled."
        )
        try expectEqual(
            PreviewSelectionPolicy.isManaged(
                itemID: "window",
                rule: .automatic,
                isProtected: false,
                automaticAvoidanceEnabled: true,
                automaticManagedIDs: automaticIDs
            ),
            true,
            "Preview automatic rules must resume managing constrained items when avoidance is enabled."
        )
    }

    private static func previewManualAndProtectedRulesTakePrecedence() throws {
        let automaticIDs = Set(["window"])
        try expectEqual(
            PreviewSelectionPolicy.isManaged(
                itemID: "vpn",
                rule: .alwaysHidden,
                isProtected: false,
                automaticAvoidanceEnabled: false,
                automaticManagedIDs: automaticIDs
            ),
            true,
            "Always-hidden preview rules must remain managed in manual mode."
        )
        try expectEqual(
            PreviewSelectionPolicy.isManaged(
                itemID: "window",
                rule: .alwaysVisible,
                isProtected: false,
                automaticAvoidanceEnabled: true,
                automaticManagedIDs: automaticIDs
            ),
            false,
            "Always-visible preview rules must override automatic overflow."
        )
        try expectEqual(
            PreviewSelectionPolicy.isManaged(
                itemID: "recording",
                rule: .alwaysHidden,
                isProtected: true,
                automaticAvoidanceEnabled: true,
                automaticManagedIDs: automaticIDs
            ),
            false,
            "Protected preview items must remain visible regardless of their stored rule."
        )
    }
}

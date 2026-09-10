import Foundation
import CoreGraphics

final class PreferencesStore {
    private let selectedKeys = "selectedMenuBarItems"
    private let knownItemsKey = "knownMenuBarItemsV1"
    private let knownWindowIDsKey = "knownMenuBarWindowIDsV1"
    private let deselectedItemsKey = "deselectedMenuBarItemsV1"
    private let layoutManagementKey = "layoutManagementEnabled"
    private let automaticAvoidanceKey = "automaticAvoidanceEnabled"
    private let itemRulesKey = "itemRulesV1"
    private let defaultLayoutKey = "didApplyDefaultLayoutV4"
    private let onboardingCompletedKey = "hasCompletedOnboarding"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isSelected(_ id: String) -> Bool { Set(defaults.stringArray(forKey: selectedKeys) ?? []).contains(id) }

    var selectedIDs: Set<String> { Set(defaults.stringArray(forKey: selectedKeys) ?? []) }
    var knownItemIDs: Set<String> { Set(defaults.stringArray(forKey: knownItemsKey) ?? []) }
    var knownWindowIDs: Set<CGWindowID> {
        Set((defaults.array(forKey: knownWindowIDsKey) as? [NSNumber] ?? []).map { CGWindowID($0.uint32Value) })
    }
    var deselectedItemIDs: Set<String> { Set(defaults.stringArray(forKey: deselectedItemsKey) ?? []) }
    var layoutManagementEnabled: Bool {
        get { defaults.bool(forKey: layoutManagementKey) }
        set { defaults.set(newValue, forKey: layoutManagementKey) }
    }
    var automaticAvoidanceEnabled: Bool {
        get {
            defaults.object(forKey: automaticAvoidanceKey) == nil ||
                defaults.bool(forKey: automaticAvoidanceKey)
        }
        set { defaults.set(newValue, forKey: automaticAvoidanceKey) }
    }
    var didApplyDefaultLayout: Bool {
        get { defaults.bool(forKey: defaultLayoutKey) }
        set { defaults.set(newValue, forKey: defaultLayoutKey) }
    }
    var hasCompletedOnboarding: Bool {
        get {
            if defaults.object(forKey: onboardingCompletedKey) != nil {
                return defaults.bool(forKey: onboardingCompletedKey)
            }
            return defaults.dictionaryRepresentation().keys.contains {
                $0.hasPrefix("hasCompletedOnboarding.") && defaults.bool(forKey: $0)
            }
        }
        set { defaults.set(newValue, forKey: onboardingCompletedKey) }
    }

    func saveSelected(_ ids: Set<String>) { defaults.set(Array(ids), forKey: selectedKeys) }
    func saveKnownItems(_ ids: Set<String>) { defaults.set(Array(ids), forKey: knownItemsKey) }
    func saveKnownWindowIDs(_ ids: Set<CGWindowID>) {
        defaults.set(ids.map { NSNumber(value: $0) }, forKey: knownWindowIDsKey)
    }
    func saveDeselectedItems(_ ids: Set<String>) { defaults.set(Array(ids), forKey: deselectedItemsKey) }

    var itemRules: [String: MenuItemRule] {
        MenuItemRuleCodec.decode(defaults.dictionary(forKey: itemRulesKey) ?? [:])
    }

    func rule(for id: String) -> MenuItemRule {
        itemRules[id] ?? .automatic
    }

    func rule(for item: MenuBarItem) -> MenuItemRule {
        guard !item.isAlwaysVisibleSystemItem else { return .alwaysVisible }
        let rules = itemRules
        if let current = rules[item.id] { return current }
        let previous = item.legacyIDs.compactMap { rules[$0] }
        if previous.contains(.alwaysVisible) { return .alwaysVisible }
        if previous.contains(.alwaysHidden) { return .alwaysHidden }
        return .automatic
    }

    func saveRule(_ rule: MenuItemRule, for id: String) {
        var rules = itemRules
        rules[id] = rule
        defaults.set(MenuItemRuleCodec.encode(rules), forKey: itemRulesKey)
    }

    func saveRules(_ rules: [String: MenuItemRule]) {
        defaults.set(MenuItemRuleCodec.encode(rules), forKey: itemRulesKey)
    }

    func resetRules() {
        defaults.removeObject(forKey: itemRulesKey)
    }

    /// Clears layout discovery state left by an older build or a diagnostic
    /// run while keeping permissions, login behavior, and onboarding intact.
    func resetLayoutState() {
        defaults.removeObject(forKey: selectedKeys)
        defaults.removeObject(forKey: knownItemsKey)
        defaults.removeObject(forKey: knownWindowIDsKey)
        defaults.removeObject(forKey: deselectedItemsKey)
        defaults.removeObject(forKey: itemRulesKey)
        for name in ["BarTuckControlItem", "BarTuckHiddenSection"] {
            defaults.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
            defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
            defaults.removeObject(forKey: "NSStatusItem Preferred Position \(name)Mac26")
            defaults.removeObject(forKey: "NSStatusItem Visible \(name)Mac26")
        }
        defaults.set(false, forKey: layoutManagementKey)
        // Treat the clean, visible state as an already-established default so
        // the next scan does not select every discovered item again.
        defaults.set(true, forKey: defaultLayoutKey)
    }
}

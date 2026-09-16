import Foundation

struct MenuBarAssessmentItem: Equatable {
    let id: String
    let resolvedBundleIdentifier: String?
    let hostBundleIdentifier: String?
    let isSelected: Bool
    let isProtected: Bool
    let isTemporarilyVisible: Bool
}

struct MenuBarAssessmentPlan: Equatable {
    let hiddenBundleIdentifiers: Set<String>
    let hiddenItemIDs: Set<String>
    let allowedBundleIdentifiers: [String]
    let unresolvedSelectedItemIDs: Set<String>
}

enum MenuBarAssessmentModePolicy {
    static let allowedSystemItemIdentifiers = Array(0...8)

    static func effectiveBundleIdentifier(
        resolved: String?,
        host: String?
    ) -> String? {
        normalized(host) ?? normalized(resolved)
    }

    static func expandedManagedItemIDs(
        items: [MenuBarAssessmentItem],
        managedItemIDs: Set<String>
    ) -> Set<String> {
        let managedBundles = Set(items.compactMap { item -> String? in
            guard managedItemIDs.contains(item.id), !item.isProtected else { return nil }
            return effectiveBundleIdentifier(
                resolved: item.resolvedBundleIdentifier,
                host: item.hostBundleIdentifier
            )
        })
        return Set(items.compactMap { item -> String? in
            guard !item.isProtected else { return nil }
            if managedItemIDs.contains(item.id) { return item.id }
            guard let bundleIdentifier = effectiveBundleIdentifier(
                resolved: item.resolvedBundleIdentifier,
                host: item.hostBundleIdentifier
            ), managedBundles.contains(bundleIdentifier) else { return nil }
            return item.id
        })
    }

    static func groupItemIDs(
        items: [MenuBarAssessmentItem],
        itemID: String
    ) -> Set<String> {
        guard let requested = items.first(where: { $0.id == itemID }),
              !requested.isProtected,
              let bundleIdentifier = effectiveBundleIdentifier(
                  resolved: requested.resolvedBundleIdentifier,
                  host: requested.hostBundleIdentifier
              ) else { return [itemID] }
        return Set(items.compactMap { item -> String? in
            guard !item.isProtected,
                  effectiveBundleIdentifier(
                    resolved: item.resolvedBundleIdentifier,
                    host: item.hostBundleIdentifier
                  ) == bundleIdentifier else { return nil }
            return item.id
        })
    }

    static func plan(
        items: [MenuBarAssessmentItem],
        runningBundleIdentifiers: Set<String>,
        ownBundleIdentifier: String?
    ) -> MenuBarAssessmentPlan {
        let selected = items.filter { $0.isSelected && !$0.isProtected }
        let unresolved = Set(selected.compactMap { item -> String? in
            effectiveBundleIdentifier(
                resolved: item.resolvedBundleIdentifier,
                host: item.hostBundleIdentifier
            ) == nil ? item.id : nil
        })
        let selectedBundles = Set(selected.compactMap {
            effectiveBundleIdentifier(
                resolved: $0.resolvedBundleIdentifier,
                host: $0.hostBundleIdentifier
            )
        })
        let temporarilyVisibleBundles = Set(items.compactMap { item -> String? in
            guard item.isTemporarilyVisible else { return nil }
            return effectiveBundleIdentifier(
                resolved: item.resolvedBundleIdentifier,
                host: item.hostBundleIdentifier
            )
        })
        let hiddenBundles = selectedBundles.subtracting(temporarilyVisibleBundles)
        let hiddenItemIDs = Set(items.compactMap { item -> String? in
            guard !item.isProtected,
                  let bundleIdentifier = effectiveBundleIdentifier(
                    resolved: item.resolvedBundleIdentifier,
                    host: item.hostBundleIdentifier
                  ), hiddenBundles.contains(bundleIdentifier) else { return nil }
            return item.id
        })

        var allowed = Set(runningBundleIdentifiers.compactMap(normalized))
        allowed.subtract(hiddenBundles)
        if let ownBundleIdentifier = normalized(ownBundleIdentifier) {
            allowed.insert(ownBundleIdentifier)
        }
        return MenuBarAssessmentPlan(
            hiddenBundleIdentifiers: hiddenBundles,
            hiddenItemIDs: hiddenItemIDs,
            allowedBundleIdentifiers: allowed.sorted(),
            unresolvedSelectedItemIDs: unresolved
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

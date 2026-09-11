import Foundation

struct OverflowPolicyItem: Equatable {
    let id: String
    let width: Double
    let position: Double
    let rule: MenuItemRule
    let isProtected: Bool
    let isOffscreen: Bool
}

enum OverflowPolicy {
    static func managedItemIDs(
        from items: [OverflowPolicyItem],
        availableWidth: Double?
    ) -> Set<String> {
        var managed = Set(items.compactMap { item in
            item.rule == .alwaysHidden && !item.isProtected ? item.id : nil
        })

        let offscreenAutomatic = items.filter {
            $0.rule == .automatic && !$0.isProtected && $0.isOffscreen
        }
        managed.formUnion(offscreenAutomatic.map(\.id))

        guard let availableWidth else { return managed }

        var visibleWidth = items.reduce(into: 0.0) { total, item in
            guard !managed.contains(item.id) else { return }
            total += max(0, item.width)
        }
        let capacity = max(0, availableWidth)

        let automaticCandidates = items
            .filter {
                $0.rule == .automatic &&
                    !$0.isProtected &&
                    !managed.contains($0.id)
            }
            .sorted {
                if $0.position == $1.position { return $0.id < $1.id }
                return $0.position < $1.position
            }

        for item in automaticCandidates where visibleWidth > capacity {
            managed.insert(item.id)
            visibleWidth -= max(0, item.width)
        }

        return managed
    }
}

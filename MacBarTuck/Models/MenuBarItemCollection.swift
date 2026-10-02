import Foundation

enum MenuBarItemFilter: String, CaseIterable, Identifiable {
    case all, favorites, tucked, temporary

    var id: String { rawValue }
    var localizationKey: String { "items.filter.\(rawValue)" }
}

enum MenuBarItemCollection {
    static func isFavorite(_ item: MenuBarItem, favoriteIDs: Set<String>) -> Bool {
        favoriteIDs.contains(item.id) || !favoriteIDs.isDisjoint(with: item.legacyIDs)
    }

    static func favoritesFirst(_ items: [MenuBarItem], favoriteIDs: Set<String>) -> [MenuBarItem] {
        // A stable partition keeps notification/title changes from moving icons.
        items.filter { isFavorite($0, favoriteIDs: favoriteIDs) } +
            items.filter { !isFavorite($0, favoriteIDs: favoriteIDs) }
    }

    static func filtered(
        _ items: [MenuBarItem],
        filter: MenuBarItemFilter,
        query: String,
        favoriteIDs: Set<String>,
        temporaryIDs: Set<String>,
        language: AppLanguage
    ) -> [MenuBarItem] {
        matchingGroups(items, query: query, favoriteIDs: favoriteIDs,
            temporaryIDs: temporaryIDs, language: language)[filter, default: []]
    }

    static func matchingGroups(
        _ items: [MenuBarItem], query: String, favoriteIDs: Set<String>,
        temporaryIDs: Set<String>, language: AppLanguage
    ) -> [MenuBarItemFilter: [MenuBarItem]] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var groups: [MenuBarItemFilter: [MenuBarItem]] = [:]
        for item in items {
            guard query.isEmpty ||
                item.displayTitle(for: language).localizedCaseInsensitiveContains(query) ||
                item.displayOwnerName(for: language).localizedCaseInsensitiveContains(query) ||
                item.title.localizedCaseInsensitiveContains(query) ||
                item.ownerName.localizedCaseInsensitiveContains(query) else { continue }
            groups[.all, default: []].append(item)
            if isFavorite(item, favoriteIDs: favoriteIDs) { groups[.favorites, default: []].append(item) }
            if temporaryIDs.contains(item.id) {
                groups[.temporary, default: []].append(item)
            } else if item.visibility == .hidden && !item.isAlwaysVisibleSystemItem {
                groups[.tucked, default: []].append(item)
            }
        }
        return groups
    }
}

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
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = isFavorite(item, favoriteIDs: favoriteIDs)
            case .tucked:
                matchesFilter = item.visibility == .hidden &&
                    !temporaryIDs.contains(item.id) && !item.isAlwaysVisibleSystemItem
            case .temporary: matchesFilter = temporaryIDs.contains(item.id)
            }
            return matchesFilter && (query.isEmpty ||
                item.displayTitle(for: language).localizedCaseInsensitiveContains(query) ||
                item.displayOwnerName(for: language).localizedCaseInsensitiveContains(query) ||
                item.title.localizedCaseInsensitiveContains(query) ||
                item.ownerName.localizedCaseInsensitiveContains(query))
        }
    }
}

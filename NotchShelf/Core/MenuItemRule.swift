import Foundation

enum MenuItemRule: String, Codable, CaseIterable, Hashable {
    case automatic
    case alwaysVisible
    case alwaysHidden
}

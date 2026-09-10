import Foundation

enum MenuItemRuleCodec {
    static func encode(_ rules: [String: MenuItemRule]) -> [String: String] {
        rules.mapValues(\.rawValue)
    }

    static func decode(_ values: [String: String]) -> [String: MenuItemRule] {
        values.mapValues { MenuItemRule(rawValue: $0) ?? .automatic }
    }

    static func decode(_ values: [String: Any]) -> [String: MenuItemRule] {
        decode(values.reduce(into: [:]) { result, entry in
            if let rawValue = entry.value as? String {
                result[entry.key] = rawValue
            }
        })
    }

    static func rule(for id: String, in values: [String: String]) -> MenuItemRule {
        guard let rawValue = values[id] else { return .automatic }
        return MenuItemRule(rawValue: rawValue) ?? .automatic
    }
}

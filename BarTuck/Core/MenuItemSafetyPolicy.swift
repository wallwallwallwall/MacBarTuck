import Foundation

enum MenuItemSafetyPolicy {
    static func mustRemainVisible(title: String) -> Bool {
        let normalized = title
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        return normalized.contains("screenrecording") ||
            normalized == "controlcenter" ||
            normalized.contains("audioandvideocontrols")
    }
}

import Foundation

enum MenuBarDiscoveryStrategy: Equatable {
    case windowServerWithAccessibility
    case windowServerOnly
    case accessibilityPreferred
}

enum MenuBarMovementStrategy: Equatable {
    case hybrid
    case windowServer
    case accessibility
}

struct MenuBarPlatformPolicy: Equatable {
    let discovery: MenuBarDiscoveryStrategy
    let movement: MenuBarMovementStrategy
    let usesHiddenSection: Bool

    init(discovery: MenuBarDiscoveryStrategy, movement: MenuBarMovementStrategy,
         usesHiddenSection: Bool) {
        self.discovery = discovery
        self.movement = movement
        self.usesHiddenSection = usesHiddenSection
    }

    init(majorVersion: Int) {
        switch majorVersion {
        case 27...:
            self.init(discovery: .accessibilityPreferred, movement: .accessibility,
                      usesHiddenSection: false)
        case 26:
            self.init(discovery: .windowServerOnly, movement: .windowServer,
                      usesHiddenSection: true)
        default:
            self.init(discovery: .windowServerWithAccessibility, movement: .hybrid,
                      usesHiddenSection: true)
        }
    }

    static var current: MenuBarPlatformPolicy {
        MenuBarPlatformPolicy(
            majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }
}

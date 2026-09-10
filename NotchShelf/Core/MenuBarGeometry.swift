import CoreGraphics

enum MenuBarGeometry {
    static func isVisibleMenuBarItem(
        _ frame: CGRect,
        displayBounds: [CGRect]
    ) -> Bool {
        guard hasMenuBarItemDimensions(frame) else { return false }

        return displayBounds.contains { display in
            guard frame.intersects(display) else { return false }
            return isNearMenuBar(frame, on: display)
        }
    }

    static func isHiddenLaneMenuItem(
        _ frame: CGRect,
        displayBounds: [CGRect]
    ) -> Bool {
        guard hasMenuBarItemDimensions(frame),
              !displayBounds.isEmpty,
              !isVisibleMenuBarItem(frame, displayBounds: displayBounds),
              let leftEdge = displayBounds.map(\.minX).min(),
              frame.maxX <= leftEdge else { return false }

        return displayBounds.contains { isNearMenuBar(frame, on: $0) }
    }

    static func isMenuBarItem(
        _ frame: CGRect,
        displayBounds: [CGRect]
    ) -> Bool {
        isVisibleMenuBarItem(frame, displayBounds: displayBounds) ||
            isHiddenLaneMenuItem(frame, displayBounds: displayBounds)
    }

    static func isOffscreenMenuItem(
        _ frame: CGRect,
        displayBounds: [CGRect]
    ) -> Bool {
        !isVisibleMenuBarItem(frame, displayBounds: displayBounds)
    }

    private static func hasMenuBarItemDimensions(_ frame: CGRect) -> Bool {
        frame.width > 4 && frame.height > 4 && frame.height <= 50
    }

    private static func isNearMenuBar(_ frame: CGRect, on display: CGRect) -> Bool {
        let nearQuartzMenuBar = abs(frame.minY - display.minY) <= 4
        let nearAppKitMenuBar = abs(frame.maxY - display.maxY) <= 50
        return nearQuartzMenuBar || nearAppKitMenuBar
    }
}

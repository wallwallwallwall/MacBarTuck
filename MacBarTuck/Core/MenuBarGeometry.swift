import CoreGraphics

enum MenuBarGeometry {
    static func panelAnchor(buttonFrames: [CGRect], pointer: CGPoint,
                            displayFrames: [CGRect], menuBarHeight: CGFloat) -> CGRect? {
        let validFrames = buttonFrames.filter { frame in
            frame.width > 0 && frame.height > 0 && displayFrames.contains { display in
                display.insetBy(dx: -1, dy: -1).contains(CGPoint(x: frame.midX, y: frame.midY)) &&
                    frame.maxY >= display.maxY - menuBarHeight - 8
            }
        }
        if let display = displayFrames.first(where: { $0.insetBy(dx: -1, dy: -1).contains(pointer) }),
           pointer.y >= display.maxY - menuBarHeight - 8 {
            return validFrames.first { display.contains(CGPoint(x: $0.midX, y: $0.midY)) }
                ?? CGRect(x: pointer.x - 1, y: display.maxY - menuBarHeight, width: 2, height: menuBarHeight)
        }
        return validFrames.first
    }

    static func appKitFrame(fromQuartz frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
    }

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
        // Retina AX frames commonly land at 4.5 or 5 points from the screen
        // edge. Keep a small tolerance without admitting ordinary top-level
        // windows into the status-item classifier.
        let edgeTolerance: CGFloat = 6
        let nearQuartzMenuBar = abs(frame.minY - display.minY) <= edgeTolerance
        let nearAppKitMenuBar = abs(frame.maxY - display.maxY) <= edgeTolerance
        return nearQuartzMenuBar || nearAppKitMenuBar
    }
}

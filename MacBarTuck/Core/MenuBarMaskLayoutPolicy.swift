import CoreGraphics
import Foundation

struct MenuBarMaskDisplay: Equatable {
    let id: UInt32
    let quartzFrame: CGRect
    let appKitFrame: CGRect
    let menuBarHeight: CGFloat
}

struct MenuBarMaskPlacement: Equatable {
    let key: String
    let itemID: String
    let displayID: UInt32
    let frame: CGRect
}

struct MenuBarMaskReconciliation: Equatable {
    let removals: Set<String>
    let additions: [MenuBarMaskPlacement]
    let updates: [MenuBarMaskPlacement]

    var isNoOp: Bool {
        removals.isEmpty && additions.isEmpty && updates.isEmpty
    }
}

enum MenuBarMaskLayoutPolicy {
    static let liveGeometrySyncInterval: TimeInterval = 0.25
    private static let horizontalPadding: CGFloat = 1
    private static let frameTolerance: CGFloat = 0.5

    static func placements(
        itemID: String,
        representationFrames: [CGRect],
        displays: [MenuBarMaskDisplay]
    ) -> [MenuBarMaskPlacement] {
        guard !itemID.isEmpty else { return [] }
        let validDisplays = displays.filter(isValidDisplay)
        guard !validDisplays.isEmpty else { return [] }

        let observed = representationFrames.compactMap { frame -> (CGRect, MenuBarMaskDisplay)? in
            guard isValidItemFrame(frame),
                  let display = validDisplays.first(where: { isInMenuBar(frame, on: $0) })
            else { return nil }
            return (frame, display)
        }
        guard let anchor = observed.first else { return [] }

        return validDisplays.compactMap { display in
            let sourceFrame = observed.first(where: { $0.1.id == display.id })?.0
                ?? mirroredFrame(anchor.0, from: anchor.1, to: display)
            guard isInMenuBar(sourceFrame, on: display) else { return nil }
            let frame = appKitMaskFrame(for: sourceFrame, on: display)
            return MenuBarMaskPlacement(
                key: "\(itemID)|\(display.id)",
                itemID: itemID,
                displayID: display.id,
                frame: frame
            )
        }
        .sorted { $0.displayID < $1.displayID }
    }

    static func reconcile(
        current: [String: CGRect],
        desired: [MenuBarMaskPlacement]
    ) -> MenuBarMaskReconciliation {
        let desiredByKey = Dictionary(desired.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let removals = Set(current.keys).subtracting(desiredByKey.keys)
        let additions = desiredByKey.values
            .filter { current[$0.key] == nil }
            .sorted { $0.key < $1.key }
        let updates = desiredByKey.values
            .filter { placement in
                guard let frame = current[placement.key] else { return false }
                return !framesMatch(frame, placement.frame)
            }
            .sorted { $0.key < $1.key }
        return MenuBarMaskReconciliation(
            removals: removals,
            additions: additions,
            updates: updates
        )
    }

    private static func mirroredFrame(
        _ frame: CGRect,
        from source: MenuBarMaskDisplay,
        to destination: MenuBarMaskDisplay
    ) -> CGRect {
        let rightInset = source.quartzFrame.maxX - frame.maxX
        let topInset = frame.minY - source.quartzFrame.minY
        return CGRect(
            x: destination.quartzFrame.maxX - rightInset - frame.width,
            y: destination.quartzFrame.minY + topInset,
            width: frame.width,
            height: frame.height
        )
    }

    private static func appKitMaskFrame(
        for quartzFrame: CGRect,
        on display: MenuBarMaskDisplay
    ) -> CGRect {
        CGRect(
            x: display.appKitFrame.minX +
                (quartzFrame.minX - display.quartzFrame.minX) - horizontalPadding,
            y: display.appKitFrame.maxY - display.menuBarHeight,
            width: quartzFrame.width + horizontalPadding * 2,
            height: display.menuBarHeight
        )
    }

    private static func isInMenuBar(_ frame: CGRect, on display: MenuBarMaskDisplay) -> Bool {
        let strip = CGRect(
            x: display.quartzFrame.minX,
            y: display.quartzFrame.minY,
            width: display.quartzFrame.width,
            height: min(display.quartzFrame.height, max(50, display.menuBarHeight + 8))
        )
        return strip.intersects(frame) && strip.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private static func isValidDisplay(_ display: MenuBarMaskDisplay) -> Bool {
        isFinite(display.quartzFrame) && isFinite(display.appKitFrame) &&
            display.quartzFrame.width > 0 && display.quartzFrame.height > 0 &&
            display.appKitFrame.width > 0 && display.appKitFrame.height > 0 &&
            display.menuBarHeight.isFinite && display.menuBarHeight > 0
    }

    private static func isValidItemFrame(_ frame: CGRect) -> Bool {
        isFinite(frame) && frame.width > 4 && frame.height > 4 && frame.height <= 50
    }

    private static func isFinite(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite &&
            frame.width.isFinite && frame.height.isFinite
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        if coordinatesMatch(lhs, rhs) { return true }
        let alignedLeft = lhs.integral
        let alignedRight = rhs.integral
        return coordinatesMatch(alignedLeft, alignedRight)
    }

    private static func coordinatesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= frameTolerance &&
            abs(lhs.minY - rhs.minY) <= frameTolerance &&
            abs(lhs.width - rhs.width) <= frameTolerance &&
            abs(lhs.height - rhs.height) <= frameTolerance
    }
}

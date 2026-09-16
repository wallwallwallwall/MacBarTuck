import AppKit

private struct MaskControllerTestFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class FakeMaskWindow: MenuBarMaskWindow {
    private(set) var maskFrame: CGRect
    private(set) var isMaskVisible = false
    private(set) var setFrameCount = 0
    private(set) var showCount = 0
    private(set) var hideCount = 0
    private(set) var closeCount = 0
    private(set) var artworkUpdateCount = 0
    private(set) var captureExclusionStates = [Bool]()

    init(frame: CGRect) {
        maskFrame = frame
    }

    func setMaskFrame(_ frame: CGRect) {
        maskFrame = frame
        setFrameCount += 1
    }

    func setMaskArtwork(_ artwork: NSImage?) {
        artworkUpdateCount += 1
    }

    func setCaptureExcluded(_ excluded: Bool) {
        captureExclusionStates.append(excluded)
    }

    func showMask() {
        isMaskVisible = true
        showCount += 1
    }

    func hideMask() {
        isMaskVisible = false
        hideCount += 1
    }

    func closeMask() {
        isMaskVisible = false
        closeCount += 1
    }
}

@main
@MainActor
private enum MenuBarMaskingControllerTests {
    static func main() throws {
        _ = NSApplication.shared
        let builtIn = MenuBarMaskDisplay(
            id: 1,
            quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            menuBarHeight: 25
        )
        let external = MenuBarMaskDisplay(
            id: 2,
            quartzFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            appKitFrame: CGRect(x: -1_920, y: -98, width: 1_920, height: 1_080),
            menuBarHeight: 25
        )
        var displays = [builtIn, external]
        var windows = [FakeMaskWindow]()
        var snapshotRequests = [[UInt32]]()
        var snapshotsAvailable = true
        let controller = MenuBarMaskingController(
            displayProvider: { displays },
            snapshotProvider: { requestedDisplays in
                snapshotRequests.append(requestedDisplays.map(\.id))
                guard snapshotsAvailable else { return [:] }
                return Dictionary(uniqueKeysWithValues: requestedDisplays.compactMap { display in
                    syntheticSnapshot(for: display).map { (display.id, $0) }
                })
            },
            windowFactory: { placement in
                let window = FakeMaskWindow(frame: placement.frame)
                windows.append(window)
                return window
            }
        )
        let item = MenuBarItem(
            id: "utility",
            title: "Utility",
            ownerName: "Utility",
            bundleIdentifier: "com.example.utility",
            frame: CGRect(x: 1_200, y: 4.5, width: 28, height: 18),
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )

        let first = controller.apply(items: [item])
        try expect(first.maskedItemIDs == [item.id] && first.failedItemIDs.isEmpty,
                   "Both display masks must be visible before an item is reported as hidden.")
        try expect(first.changedWindowCount == 2 && windows.count == 2,
                   "The initial apply must create exactly one mask per display.")
        try expect(windows.allSatisfy { $0.isMaskVisible && $0.showCount == 1 },
                   "New mask windows must be shown exactly once.")
        try expect(snapshotRequests == [[builtIn.id, external.id]],
                   "One apply must capture each affected display exactly once.")
        try expect(windows.allSatisfy { $0.artworkUpdateCount == 1 },
                   "Each new mask must receive artwork from its display snapshot.")

        let unchanged = controller.apply(items: [item])
        try expect(unchanged.changedWindowCount == 0 && windows.count == 2,
                   "An unchanged refresh must not create, move, or remove mask windows.")
        try expect(windows.allSatisfy { $0.setFrameCount == 0 && $0.showCount == 1 },
                   "No-op applies must not republish panel frames or visibility.")
        try expect(snapshotRequests.count == 1 &&
                    windows.allSatisfy { $0.artworkUpdateCount == 1 },
                   "A no-op apply must not recapture or republish mask artwork.")

        item.frame = item.frame.offsetBy(dx: -8, dy: 0)
        let moved = controller.apply(items: [item])
        try expect(moved.changedWindowCount == 2 && windows.allSatisfy { $0.setFrameCount == 1 },
                   "A changed status position must move existing masks without recreating them.")
        try expect(snapshotRequests.count == 2 && snapshotRequests.last == [builtIn.id, external.id],
                   "A geometry update must still capture each affected display only once.")
        try expect(windows.allSatisfy { $0.captureExclusionStates == [true, false] },
                   "Existing masks must be excluded while their replacement artwork is captured.")

        let frameCountsBeforeAppearanceRefresh = windows.map(\.setFrameCount)
        let showCountsBeforeAppearanceRefresh = windows.map(\.showCount)
        controller.refreshAppearance()
        try expect(snapshotRequests.count == 3 && snapshotRequests.last == [builtIn.id, external.id],
                   "An appearance refresh must capture one strip per active display.")
        try expect(windows.map(\.setFrameCount) == frameCountsBeforeAppearanceRefresh &&
                    windows.map(\.showCount) == showCountsBeforeAppearanceRefresh,
                   "Refreshing mask artwork must not move or reorder any mask window.")

        let artworkCountsBeforeFailedCapture = windows.map(\.artworkUpdateCount)
        snapshotsAvailable = false
        controller.refreshAppearance()
        try expect(windows.map(\.artworkUpdateCount) == artworkCountsBeforeFailedCapture,
                   "A transient screenshot failure must preserve the last valid mask artwork.")
        snapshotsAvailable = true

        controller.setRevealed(true, itemID: item.id)
        try expect(windows.allSatisfy { !$0.isMaskVisible && $0.hideCount == 1 },
                   "Activation must temporarily reveal only the selected menu-bar item.")
        controller.setRevealed(false, itemID: item.id)
        try expect(windows.allSatisfy { $0.isMaskVisible && $0.showCount == 2 },
                   "The same masks must return after the native menu receives the click.")

        displays = [builtIn]
        let disconnected = controller.apply(items: [item])
        try expect(disconnected.changedWindowCount == 1 && windows.filter { $0.closeCount == 1 }.count == 1,
                   "A display disconnect must close only that display's mask.")

        let removedCount = controller.removeAll()
        try expect(removedCount == 1 && controller.maskedItemIDs.isEmpty,
                   "Disabling layout must synchronously remove every remaining mask.")

        let invalid = MenuBarItem(
            id: "invalid",
            title: "Invalid",
            ownerName: "Invalid",
            bundleIdentifier: nil,
            frame: CGRect(x: 100, y: 200, width: 28, height: 18),
            axElement: nil,
            isSelected: true,
            supportsPressAction: false
        )
        let failed = controller.apply(items: [invalid])
        try expect(failed.maskedItemIDs.isEmpty && failed.failedItemIDs == [invalid.id],
                   "An item without a trustworthy menu-bar frame must not report a false success.")

        var roundedWindows = [FakeMaskWindow]()
        let roundedController = MenuBarMaskingController(
            displayProvider: { [builtIn] },
            snapshotProvider: { _ in [:] },
            windowFactory: { placement in
                let roundedFrame = placement.frame.offsetBy(dx: 0.25, dy: -0.25)
                let window = FakeMaskWindow(frame: roundedFrame)
                roundedWindows.append(window)
                return window
            }
        )
        let rounded = roundedController.apply(items: [item])
        try expect(rounded.maskedItemIDs == [item.id] && rounded.failedItemIDs.isEmpty,
                   "AppKit sub-point frame rounding must not discard a visible mask.")
        try expect(roundedWindows.first?.closeCount == 0,
                   "A mask within the reconciliation tolerance must remain installed.")

        let fractionalItem = MenuBarItem(
            id: "fractional",
            title: "Fractional",
            ownerName: "Fractional",
            bundleIdentifier: "com.example.fractional",
            frame: CGRect(x: 1_200.5, y: 4.5, width: 18, height: 18),
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )
        var integralWindows = [FakeMaskWindow]()
        let integralController = MenuBarMaskingController(
            displayProvider: { [builtIn] },
            snapshotProvider: { _ in [:] },
            windowFactory: { placement in
                let window = FakeMaskWindow(frame: placement.frame.integral)
                integralWindows.append(window)
                return window
            }
        )
        let integral = integralController.apply(items: [fractionalItem])
        try expect(integral.maskedItemIDs == [fractionalItem.id] && integral.failedItemIDs.isEmpty,
                   "AppKit pixel alignment must not reject a half-point menu-bar mask.")
        try expect(integralWindows.first?.closeCount == 0,
                   "A pixel-aligned half-point mask must remain installed.")

        var liveFrame = CGRect(x: 1_200, y: 4.5, width: 28, height: 18)
        var liveWindows = [FakeMaskWindow]()
        let liveController = MenuBarMaskingController(
            displayProvider: { [builtIn] },
            representationFrameProvider: { _ in liveFrame },
            snapshotProvider: { _ in [:] },
            windowFactory: { placement in
                let window = FakeMaskWindow(frame: placement.frame)
                liveWindows.append(window)
                return window
            }
        )
        let staleItem = MenuBarItem(
            id: "live-utility",
            title: "Live Utility",
            ownerName: "Live Utility",
            bundleIdentifier: "com.example.live-utility",
            frame: liveFrame,
            axElement: nil,
            isSelected: true,
            supportsPressAction: true
        )
        _ = liveController.apply(items: [staleItem])
        liveFrame = liveFrame.offsetBy(dx: 18, dy: 0)
        let corrected = liveController.apply(items: [staleItem])
        try expect(corrected.changedWindowCount == 1 && liveWindows.count == 1,
                   "A live menu-bar reflow must move the existing mask without recreating it.")
        try expect(liveWindows[0].maskFrame.minX == liveFrame.minX - 1,
                   "Mask placement must follow the live Accessibility frame instead of stale scan data.")

        let panelPlacement = MenuBarMaskPlacement(
            key: "capture|1",
            itemID: "capture",
            displayID: 1,
            frame: CGRect(x: 1_100, y: 957, width: 32, height: 25)
        )
        let panel = MenuBarMaskPanel(placement: panelPlacement)
        try expect(panel.sharingType == .readOnly,
                   "Mask windows must appear in screenshots so captured evidence matches the visible menu bar.")
        panel.closeMask()

        try snapshotBackgroundReconstruction()

        print("MenuBarMaskingControllerTests: window lifecycle passed")
    }

    private static func snapshotBackgroundReconstruction() throws {
        let width = 18
        let height = 14
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(32 + x * 4)
                pixels[offset + 1] = UInt8(48 + y * 6)
                pixels[offset + 2] = UInt8(70 + x * 2 + y * 3)
                pixels[offset + 3] = 255
            }
        }
        for y in 3..<(height - 3) {
            for x in 2..<(width - 2) {
                let offset = (y * width + x) * 4
                pixels[offset] = 250
                pixels[offset + 1] = 250
                pixels[offset + 2] = 250
            }
        }

        guard let source = image(width: width, height: height, pixels: &pixels),
              let reconstructed = MenuBarMaskSnapshotRenderer.reconstructBackground(from: source),
              let output = rgbaPixels(from: reconstructed) else {
            throw MaskControllerTestFailure(description: "Synthetic menu-bar reconstruction must produce an image.")
        }

        let centerX = width / 2
        let centerY = height / 2
        let center = (centerY * width + centerX) * 4
        let expected = [
            32 + centerX * 4,
            48 + centerY * 6,
            70 + centerX * 2 + centerY * 3
        ]
        for channel in 0..<3 {
            try expect(abs(Int(output[center + channel]) - expected[channel]) <= 3,
                       "The reconstructed mask must remove foreground pixels without flattening the menu-bar gradient.")
        }

        for x in 0..<width {
            let top = x * 4
            let bottom = ((height - 1) * width + x) * 4
            try expect(Array(output[top..<(top + 4)]) == Array(pixels[top..<(top + 4)]),
                       "The top edge must remain pixel-identical so the mask has no visible seam.")
            try expect(Array(output[bottom..<(bottom + 4)]) == Array(pixels[bottom..<(bottom + 4)]),
                       "The bottom edge must remain pixel-identical so the mask has no visible seam.")
        }
    }

    private static func image(width: Int, height: Int, pixels: inout [UInt8]) -> CGImage? {
        let bytesPerRow = width * 4
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    private static func syntheticSnapshot(for display: MenuBarMaskDisplay) -> CGImage? {
        let width = max(1, Int(display.quartzFrame.width.rounded()))
        let height = max(4, Int(display.menuBarHeight.rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 84
            pixels[index + 1] = 112
            pixels[index + 2] = 146
            pixels[index + 3] = 255
        }
        return image(width: width, height: height, pixels: &pixels)
    }

    private static func rgbaPixels(from image: CGImage) -> [UInt8]? {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw MaskControllerTestFailure(description: message) }
    }
}

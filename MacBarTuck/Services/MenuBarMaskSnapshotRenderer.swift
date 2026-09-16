import AppKit
import CoreGraphics

enum MenuBarMaskSnapshotRenderer {
    typealias DisplaySnapshots = [UInt32: CGImage]

    static func captureMenuBars(displays: [MenuBarMaskDisplay]) -> DisplaySnapshots {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        var snapshots = DisplaySnapshots()
        for display in displays {
            let bounds = CGRect(
                x: display.quartzFrame.minX,
                y: display.quartzFrame.minY,
                width: display.quartzFrame.width,
                height: display.menuBarHeight
            )
            guard let image = MacBarTuckCreateScreenImage(
                bounds,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.boundsIgnoreFraming, .bestResolution]
            )?.takeRetainedValue() else { continue }
            snapshots[display.id] = image
        }
        return snapshots
    }

    static func artwork(
        for placement: MenuBarMaskPlacement,
        display: MenuBarMaskDisplay,
        snapshot: CGImage
    ) -> NSImage? {
        guard display.quartzFrame.width > 0,
              display.menuBarHeight > 0,
              snapshot.width > 0,
              snapshot.height > 0 else { return nil }

        let scaleX = CGFloat(snapshot.width) / display.quartzFrame.width
        let scaleY = CGFloat(snapshot.height) / display.menuBarHeight
        let localX = placement.frame.minX - display.appKitFrame.minX
        let pixelRect = CGRect(
            x: localX * scaleX,
            y: 0,
            width: placement.frame.width * scaleX,
            height: placement.frame.height * scaleY
        ).integral.intersection(CGRect(
            x: 0,
            y: 0,
            width: snapshot.width,
            height: snapshot.height
        ))
        guard !pixelRect.isNull,
              pixelRect.width > 0,
              pixelRect.height > 0,
              let cropped = snapshot.cropping(to: pixelRect),
              let reconstructed = reconstructBackground(from: cropped) else { return nil }
        return NSImage(cgImage: reconstructed, size: placement.frame.size)
    }

    /// Rebuilds the smooth menu-bar background from the foreground-free top
    /// and bottom edge pixels. Status glyphs and text occupy the center band,
    /// while the system material remains visible along both horizontal edges.
    static func reconstructBackground(from source: CGImage) -> CGImage? {
        let width = source.width
        let height = source.height
        guard width > 0, height >= 4 else { return nil }
        let bytesPerRow = width * 4
        var sourcePixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let sourceContext = bitmapContext(
            pixels: &sourcePixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        ) else { return nil }
        sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var outputPixels = sourcePixels
        let edgeRows = max(1, min(2, height / 10))
        let firstBackgroundRow = edgeRows - 1
        let lastBackgroundRow = height - edgeRows
        let interpolationSpan = max(1, lastBackgroundRow - firstBackgroundRow)

        for x in 0..<width {
            let firstOffset = firstBackgroundRow * bytesPerRow + x * 4
            let lastOffset = lastBackgroundRow * bytesPerRow + x * 4
            for y in edgeRows..<(height - edgeRows) {
                let outputOffset = y * bytesPerRow + x * 4
                let distance = y - firstBackgroundRow
                for channel in 0..<4 {
                    let start = Int(sourcePixels[firstOffset + channel])
                    let end = Int(sourcePixels[lastOffset + channel])
                    outputPixels[outputOffset + channel] = UInt8(
                        (start * (interpolationSpan - distance) + end * distance) /
                            interpolationSpan
                    )
                }
            }
        }

        guard let outputContext = bitmapContext(
            pixels: &outputPixels,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        ) else { return nil }
        return outputContext.makeImage()
    }

    private static func bitmapContext(
        pixels: inout [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> CGContext? {
        CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
        )
    }
}

/// Xcode 27 marks the legacy WindowServer snapshot symbol unavailable even
/// though it remains exported. ScreenCaptureKit is used for icon capture; this
/// compatibility shim is limited to the already-authorized menu-bar strip so
/// mask creation stays synchronous and does not flash a temporary dark panel.
@_silgen_name("CGWindowListCreateImage")
private func MacBarTuckCreateScreenImage(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> Unmanaged<CGImage>?

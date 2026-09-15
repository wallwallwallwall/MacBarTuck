import AppKit
import CoreGraphics

enum MenuBarDisplayBounds {
    static func current() -> [CGRect] {
        current(
            readScreenBounds: appKitScreenBounds,
            readFallbackBounds: coreGraphicsDisplayBounds
        )
    }

    static func current(
        readScreenBounds: () -> [CGRect],
        readFallbackBounds: () -> [CGRect]
    ) -> [CGRect] {
        let screenBounds = normalized(readScreenBounds())
        if !screenBounds.isEmpty { return screenBounds }
        return normalized(readFallbackBounds())
    }

    private static func appKitScreenBounds() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
    }

    private static func coreGraphicsDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    private static func normalized(_ bounds: [CGRect]) -> [CGRect] {
        bounds.reduce(into: []) { result, frame in
            guard frame.minX.isFinite, frame.minY.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0,
                  !result.contains(frame) else { return }
            result.append(frame)
        }
    }
}

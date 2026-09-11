import AppKit
import CoreGraphics

@MainActor
enum DisplaySnapshotProvider {
    private static let statusControlReservation: CGFloat = 48

    static func snapshots() -> [DisplaySnapshot] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }

            let displayID = number.uint32Value
            let rightArea = screen.auxiliaryTopRightArea
            let hasNotch = screen.safeAreaInsets.top > 0 && rightArea != nil
            let availableWidth = rightArea.map {
                Double(max(0, $0.width - statusControlReservation))
            }

            return DisplaySnapshot(
                id: displayID,
                name: screen.localizedName,
                isMain: displayID == CGMainDisplayID(),
                frame: CGDisplayBounds(displayID),
                pixelSize: CGSize(
                    width: CGDisplayPixelsWide(displayID),
                    height: CGDisplayPixelsHigh(displayID)
                ),
                hasNotch: hasNotch,
                availableMenuWidth: hasNotch ? availableWidth : nil
            )
        }
        .sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

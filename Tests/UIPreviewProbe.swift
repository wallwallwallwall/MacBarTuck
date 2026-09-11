import CoreGraphics
import Foundation

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum UIPreviewProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5,
              let processID = Int32(CommandLine.arguments[1]),
              let minimumWidth = Double(CommandLine.arguments[2]),
              let minimumHeight = Double(CommandLine.arguments[3]) else {
            throw ProbeFailure(description: "usage: UIPreviewProbe <pid> <minimum-width> <minimum-height> [--window-id]")
        }
        let printWindowID = CommandLine.arguments.last == "--window-id"

        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let window = matchingWindow(
                processID: processID,
                minimumWidth: minimumWidth,
                minimumHeight: minimumHeight
            ) {
                print(printWindowID ? String(window.id) : "window=\(Int(window.bounds.width))x\(Int(window.bounds.height))")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        throw ProbeFailure(
            description: "No visible layer-zero window reached \(Int(minimumWidth))x\(Int(minimumHeight)) for PID \(processID)."
        )
    }

    private static func matchingWindow(
        processID: Int32,
        minimumWidth: Double,
        minimumHeight: Double
    ) -> (id: CGWindowID, bounds: CGRect)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        return windows.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == processID,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width >= minimumWidth,
                  bounds.height >= minimumHeight else { return nil }
            return (CGWindowID(number.uint32Value), bounds)
        }
        .max { lhs, rhs in
            lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
        }
    }
}

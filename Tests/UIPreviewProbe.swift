import CoreGraphics
import Foundation

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum UIPreviewProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 4,
              let processID = Int32(CommandLine.arguments[1]),
              let minimumWidth = Double(CommandLine.arguments[2]),
              let minimumHeight = Double(CommandLine.arguments[3]) else {
            throw ProbeFailure(description: "usage: UIPreviewProbe <pid> <minimum-width> <minimum-height>")
        }

        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let bounds = matchingWindowBounds(
                processID: processID,
                minimumWidth: minimumWidth,
                minimumHeight: minimumHeight
            ) {
                print("window=\(Int(bounds.width))x\(Int(bounds.height))")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        throw ProbeFailure(
            description: "No visible layer-zero window reached \(Int(minimumWidth))x\(Int(minimumHeight)) for PID \(processID)."
        )
    }

    private static func matchingWindowBounds(
        processID: Int32,
        minimumWidth: Double,
        minimumHeight: Double
    ) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        return windows.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value == processID,
                  let layer = info[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width >= minimumWidth,
                  bounds.height >= minimumHeight else { return nil }
            return bounds
        }
        .max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
    }
}

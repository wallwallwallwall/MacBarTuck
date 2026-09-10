import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 900, height: 560)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0.035, green: 0.042, blue: 0.047, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let accent = NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.88, alpha: 1)
accent.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 330, y: 275))
arrow.line(to: NSPoint(x: 570, y: 275))
arrow.move(to: NSPoint(x: 570, y: 275))
arrow.line(to: NSPoint(x: 525, y: 315))
arrow.move(to: NSPoint(x: 570, y: 275))
arrow.line(to: NSPoint(x: 525, y: 235))
arrow.stroke()

let title = "安装 BarTuck"
let subtitle = "将应用拖入 Applications 文件夹"
let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1)]
let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor(calibratedWhite: 0.66, alpha: 1)]
(title as NSString).draw(at: NSPoint(x: 330, y: 465), withAttributes: titleAttributes)
(subtitle as NSString).draw(at: NSPoint(x: 316, y: 430), withAttributes: subtitleAttributes)

image.unlockFocus()
guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: output))

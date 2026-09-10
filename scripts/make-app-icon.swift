import AppKit

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let output = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? root.appendingPathComponent("NotchShelf/Resources/NotchShelf.icns")
let workDirectory = root.appendingPathComponent("work/AppIcon", isDirectory: true)
let iconset = workDirectory.appendingPathComponent("NotchShelf.iconset", isDirectory: true)

try? fileManager.removeItem(at: workDirectory)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let canvasSize = NSSize(width: 1024, height: 1024)
let master = NSImage(size: canvasSize)
master.lockFocus()

NSColor(calibratedRed: 0.035, green: 0.047, blue: 0.052, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210).fill()

NSColor(calibratedRed: 0.070, green: 0.086, blue: 0.094, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 112, y: 112, width: 800, height: 800), xRadius: 160, yRadius: 160).fill()

NSColor(calibratedRed: 0.018, green: 0.022, blue: 0.025, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 376, y: 746, width: 272, height: 126), xRadius: 48, yRadius: 48).fill()

let shelfRects = [
    NSRect(x: 220, y: 564, width: 584, height: 104),
    NSRect(x: 184, y: 390, width: 656, height: 112),
    NSRect(x: 148, y: 208, width: 728, height: 120)
]

for (index, rect) in shelfRects.enumerated() {
    let path = NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34)
    NSColor(calibratedRed: 0.031, green: 0.039, blue: 0.043, alpha: 1).setFill()
    path.fill()
    (index == 2
        ? NSColor(calibratedRed: 0.31, green: 0.91, blue: 0.98, alpha: 1)
        : NSColor(calibratedRed: 0.18, green: 0.78, blue: 0.88, alpha: 0.78)
    ).setStroke()
    path.lineWidth = index == 2 ? 14 : 9
    path.stroke()
}

let dotColors = [
    NSColor(calibratedRed: 0.31, green: 0.91, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.35, green: 0.84, blue: 0.59, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.43, blue: 0.38, alpha: 1),
    NSColor(calibratedWhite: 0.92, alpha: 1)
]

for (row, rect) in shelfRects.enumerated() {
    let radius: CGFloat = row == 2 ? 25 : 22
    let spacing: CGFloat = row == 2 ? 92 : 80
    let startX = rect.minX + 64
    for index in 0..<4 {
        let center = NSPoint(x: startX + CGFloat(index) * spacing, y: rect.midY)
        dotColors[index].setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
}

NSColor(calibratedWhite: 0.96, alpha: 0.88).setFill()
NSBezierPath(roundedRect: NSRect(x: 646, y: 237, width: 132, height: 62), xRadius: 24, yRadius: 24).fill()
NSColor(calibratedRed: 0.035, green: 0.047, blue: 0.052, alpha: 1).setFill()
for index in 0..<3 {
    NSBezierPath(ovalIn: NSRect(x: 670 + CGFloat(index) * 37, y: 257, width: 22, height: 22)).fill()
}

master.unlockFocus()

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw NSError(domain: "NotchShelfIcon", code: 1) }

    representation.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "NotchShelfIcon", code: 2)
    }
    try data.write(to: url)
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    try writePNG(master, pixels: pixels, to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }

print(output.path)

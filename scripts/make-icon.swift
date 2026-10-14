// Renders the app icon into an .iconset folder (then `iconutil -c icns`).
// Usage: swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Same geometry as site/assets/logo.svg (512×512, y pointing down).
    let s = CGFloat(pixels)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: s / 512, y: -s / 512)

    let accent = NSColor(calibratedRed: 0x3D / 255, green: 0x3B / 255, blue: 0xF3 / 255, alpha: 1)

    // Background tile.
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: 480, height: 480), xRadius: 112, yRadius: 112).fill()

    // Viewfinder corners.
    let corners = NSBezierPath()
    corners.lineWidth = 28
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    func corner(start: NSPoint, center: NSPoint, from: CGFloat, to: CGFloat, end: NSPoint) {
        corners.move(to: start)
        corners.appendArc(withCenter: center, radius: 40, startAngle: from, endAngle: to)
        corners.line(to: end)
    }
    corner(start: NSPoint(x: 104, y: 184), center: NSPoint(x: 144, y: 144), from: 180, to: 270, end: NSPoint(x: 184, y: 104))
    corner(start: NSPoint(x: 328, y: 104), center: NSPoint(x: 368, y: 144), from: 270, to: 360, end: NSPoint(x: 408, y: 184))
    corner(start: NSPoint(x: 408, y: 328), center: NSPoint(x: 368, y: 368), from: 0, to: 90, end: NSPoint(x: 328, y: 408))
    corner(start: NSPoint(x: 184, y: 408), center: NSPoint(x: 144, y: 368), from: 90, to: 180, end: NSPoint(x: 104, y: 328))
    NSColor.white.setStroke()
    corners.stroke()

    // Clipboard.
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 180, y: 180, width: 152, height: 172), xRadius: 24, yRadius: 24).fill()
    let clip = NSBezierPath(roundedRect: NSRect(x: 216, y: 158, width: 80, height: 44), xRadius: 14, yRadius: 14)
    clip.fill()
    clip.lineWidth = 10
    accent.setStroke()
    clip.stroke()

    accent.withAlphaComponent(0.5).setFill()
    for (y, w) in [(236.0, 88.0), (270.0, 64.0), (304.0, 80.0)] {
        NSBezierPath(roundedRect: NSRect(x: 212, y: y, width: w, height: 16), xRadius: 8, yRadius: 8).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    try render(pixels).write(to: outDir.appendingPathComponent("\(name).png"))
}
print("Wrote \(outDir.path)")

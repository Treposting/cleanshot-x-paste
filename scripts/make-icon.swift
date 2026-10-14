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

    let yellow = NSColor(calibratedRed: 0xFF / 255, green: 0xCF / 255, blue: 0x1A / 255, alpha: 1)
    let ink = NSColor(calibratedRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)

    // Tile.
    yellow.setFill()
    NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: 480, height: 480), xRadius: 116, yRadius: 116).fill()

    // Selection brackets (top-left and bottom-right).
    let brackets = NSBezierPath()
    brackets.lineWidth = 34
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    brackets.move(to: NSPoint(x: 112, y: 196))
    brackets.line(to: NSPoint(x: 112, y: 128))
    brackets.appendArc(withCenter: NSPoint(x: 128, y: 128), radius: 16, startAngle: 180, endAngle: 270)
    brackets.line(to: NSPoint(x: 196, y: 112))
    brackets.move(to: NSPoint(x: 400, y: 316))
    brackets.line(to: NSPoint(x: 400, y: 384))
    brackets.appendArc(withCenter: NSPoint(x: 384, y: 384), radius: 16, startAngle: 0, endAngle: 90)
    brackets.line(to: NSPoint(x: 316, y: 400))
    ink.setStroke()
    brackets.stroke()

    // Copy / paste squares.
    let back = NSBezierPath(roundedRect: NSRect(x: 166, y: 166, width: 124, height: 124), xRadius: 20, yRadius: 20)
    back.lineWidth = 26
    back.stroke()
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: 222, y: 222, width: 124, height: 124), xRadius: 20, yRadius: 20).fill()

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

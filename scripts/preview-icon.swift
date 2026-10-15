// Renders an app's icon in light and dark mode and prints a background and a mark color,
// so CI can check the dark-mode icon. Writes icon-light.png and icon-dark.png.
// Usage: swift scripts/preview-icon.swift build/Marquee.app build
import AppKit

let app = CommandLine.arguments[1]
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ".")
_ = NSApplication.shared

func hex(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "none" }
    return String(format: "#%02X%02X%02X a=%.2f", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), c.alphaComponent)
}

for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
    let appearance = NSAppearance(named: appearanceName)!
    NSApp.appearance = appearance
    appearance.performAsCurrentDrawingAppearance {
        let image = NSWorkspace.shared.icon(forFile: app)
        image.size = NSSize(width: 512, height: 512)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("icon-\(name).png"))
        print("\(name): background \(hex(rep.colorAt(x: 256, y: 150)))  mark \(hex(rep.colorAt(x: 256, y: 256)))")
    }
}

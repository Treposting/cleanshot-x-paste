// Renders the app icon.
//
//   swift scripts/make-icon.swift build/AppIcon.iconset [build/AppIcon.icon]
//
// The .iconset (light icon only) becomes AppIcon.icns with `iconutil -c icns`, for macOS 13–15.
// The optional Icon Composer file adds a dark variant (a graphite tile with yellow marks) that
// macOS 26+ shows in dark mode instead of darkening the yellow tile. Compile it with `actool`.
import AppKit

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// `fullBleed` draws the tile edge to edge with square corners: macOS 26 masks Icon Composer
/// artwork itself.
func render(_ pixels: Int, dark: Bool = false, fullBleed: Bool = false, tile: Bool = true) -> Data {
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
    if fullBleed {
        // Map the 480-point tile at (16, 16) onto the whole canvas.
        ctx.scaleBy(x: 512 / 480, y: 512 / 480)
        ctx.translateBy(x: -16, y: -16)
    }

    let yellow = NSColor(calibratedRed: 0xFF / 255, green: 0xCF / 255, blue: 0x1A / 255, alpha: 1)
    let ink = NSColor(calibratedRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)

    let tileShape = fullBleed
        ? NSBezierPath(rect: NSRect(x: 16, y: 16, width: 480, height: 480))
        : NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: 480, height: 480), xRadius: 116, yRadius: 116)
    let mark: NSColor
    if !tile {
        // Marks only, for an Icon Composer layer over its own background fill.
        mark = dark ? yellow : ink
    } else if dark {
        // Graphite tile, lit slightly from the top, with yellow marks.
        let top = NSColor(calibratedRed: 0x34 / 255, green: 0x34 / 255, blue: 0x37 / 255, alpha: 1)
        let bottom = NSColor(calibratedRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1C / 255, alpha: 1)
        NSGradient(starting: top, ending: bottom)!.draw(in: tileShape, angle: 90)
        NSColor.white.withAlphaComponent(0.08).setStroke()
        tileShape.lineWidth = 3
        tileShape.stroke()
        mark = yellow
    } else {
        yellow.setFill()
        tileShape.fill()
        mark = ink
    }

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
    mark.setStroke()
    brackets.stroke()

    // Copy / paste squares.
    let back = NSBezierPath(roundedRect: NSRect(x: 166, y: 166, width: 124, height: 124), xRadius: 20, yRadius: 20)
    back.lineWidth = 26
    back.stroke()
    mark.setFill()
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

// Icon Composer file: a yellow background with graphite marks; in dark mode a graphite
// background with yellow marks (the layer's fill recolors the marks per appearance).
// Schema: https://github.com/dfabulich/unofficial-apple-icon-composer-json-schema
if args.count > 2 {
    let icon = URL(fileURLWithPath: args[2])
    let assets = icon.appendingPathComponent("Assets")
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try render(1024, fullBleed: true, tile: false).write(to: assets.appendingPathComponent("marks.png"))
    let json = """
    {
      "fill" : {
        "solid" : "srgb:1.00000,0.81176,0.10196,1.00000"
      },
      "fill-specializations" : [
        {
          "appearance" : "dark",
          "value" : {
            "solid" : "srgb:0.16471,0.16471,0.17647,1.00000"
          }
        }
      ],
      "groups" : [
        {
          "layers" : [
            {
              "fill" : {
                "solid" : "srgb:0.11373,0.11373,0.12157,1.00000"
              },
              "fill-specializations" : [
                {
                  "appearance" : "dark",
                  "value" : {
                    "solid" : "srgb:1.00000,0.81176,0.10196,1.00000"
                  }
                }
              ],
              "glass" : false,
              "image-name" : "marks.png",
              "name" : "Marks"
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.3
          },
          "specular" : true
        }
      ],
      "supported-platforms" : {
        "squares" : "shared"
      }
    }
    """
    try Data(json.utf8).write(to: icon.appendingPathComponent("icon.json"))
    print("Wrote \(icon.path)")
}

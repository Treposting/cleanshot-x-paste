// Prints a background and a mark color from rendered icon previews, so CI can check that the
// dark-mode icon is a graphite tile with yellow marks.
// Usage: swift scripts/preview-icon.swift build/icon-Default.png build/icon-Dark.png
import AppKit

func hex(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "none" }
    return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}

for path in CommandLine.arguments.dropFirst() {
    guard let rep = NSImageRep(contentsOfFile: path) as? NSBitmapImageRep else {
        print("\(path): could not read")
        continue
    }
    let w = rep.pixelsWide, h = rep.pixelsHigh
    // Above the marks (background), and the center of the filled square (mark).
    let background = rep.colorAt(x: w / 2, y: h * 150 / 512)
    let mark = rep.colorAt(x: w / 2, y: h / 2)
    print("\((path as NSString).lastPathComponent) \(w)×\(h): background \(hex(background))  mark \(hex(mark))")
    // A coarse 8×8 grid, to see the whole icon in the log.
    for row in 0..<8 {
        let line = (0..<8).map { col -> String in
            let c = rep.colorAt(x: (col * 2 + 1) * w / 16, y: (row * 2 + 1) * h / 16)
            let alpha = c?.alphaComponent ?? 0
            return alpha < 0.1 ? "   ----" : " " + hex(c)
        }.joined()
        print(line)
    }
}

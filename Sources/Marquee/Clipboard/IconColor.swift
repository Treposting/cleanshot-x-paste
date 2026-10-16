import AppKit

/// Finds the color that best represents an app icon, for tinting clipboard cards by source app.
enum IconColor {
    /// Groups the icon's colorful pixels by hue and averages the biggest group. Gray-only icons
    /// (Terminal, Finder's sidebar style) fall back to the average of all visible pixels.
    static func dominant(in image: CGImage, side: Int = 32) -> PickedColor? {
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let bucketCount = 12
        var weight = [Double](repeating: 0, count: bucketCount)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: bucketCount)
        var all = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            // Undo premultiplication.
            let r = Double(pixels[i]) / 255 / alpha
            let g = Double(pixels[i + 1]) / 255 / alpha
            let b = Double(pixels[i + 2]) / 255 / alpha
            all.r += r; all.g += g; all.b += b; all.n += 1

            let maxC = max(r, g, b), minC = min(r, g, b)
            let delta = maxC - minC
            let saturation = maxC > 0 ? delta / maxC : 0
            guard saturation > 0.25, maxC > 0.2 else { continue }
            var hue: Double
            switch maxC {
            case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            if hue < 0 { hue += 6 }
            let bucket = min(bucketCount - 1, Int(hue / 6 * Double(bucketCount)))
            let w = saturation * maxC
            weight[bucket] += w
            sums[bucket].r += r * w
            sums[bucket].g += g * w
            sums[bucket].b += b * w
        }

        if let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0.5 {
            let w = weight[best]
            return PickedColor(red: sums[best].r / w, green: sums[best].g / w, blue: sums[best].b / w)
        }
        guard all.n > 0 else { return nil }
        return PickedColor(red: all.r / all.n, green: all.g / all.n, blue: all.b / all.n)
    }

    static func dominant(in image: NSImage) -> PickedColor? {
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return dominant(in: cg)
    }
}

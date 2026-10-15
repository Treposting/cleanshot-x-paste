import CoreGraphics

/// RGBA8 pixels of a screen snapshot. Row 0 is the top of the screen.
struct PixelBuffer {
    typealias RGB = (r: Int, g: Int, b: Int)

    let width: Int
    let height: Int
    let data: [UInt8]

    init(width: Int, height: Int, data: [UInt8]) {
        precondition(data.count == width * height * 4, "RGBA buffer has the wrong size")
        self.width = width
        self.height = height
        self.data = data
    }

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, data: data)
    }

    @inline(__always)
    func rgb(_ x: Int, _ y: Int) -> RGB {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}

/// A rectangle in pixels, origin at the top-left.
struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

/// How far the same-colored region around a point reaches in each direction, in pixels.
struct EdgeDistances: Equatable {
    var left: Int
    var right: Int
    var up: Int
    var down: Int

    /// Width of the region between the left and right edges, in pixels.
    var width: Int { left + right + 1 }
    /// Height of the region between the top and bottom edges, in pixels.
    var height: Int { up + down + 1 }
}

/// The measuring algorithms. Pure functions over a `PixelBuffer`, so they are unit tested.
enum EdgeFinder {
    /// Default tolerance: ignores anti-aliasing and compression noise, keeps 1 px borders.
    static let defaultTolerance = 12

    @inline(__always)
    static func differs(_ a: PixelBuffer.RGB, _ b: PixelBuffer.RGB, tolerance: Int) -> Bool {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) > tolerance
    }

    /// Walks left, right, up and down from (x, y) until the color changes by more than `tolerance`.
    static func distances(in pixels: PixelBuffer, x: Int, y: Int, tolerance: Int = defaultTolerance) -> EdgeDistances {
        let x = min(max(0, x), pixels.width - 1)
        let y = min(max(0, y), pixels.height - 1)
        let start = pixels.rgb(x, y)

        var left = x
        while left > 0, !differs(pixels.rgb(left - 1, y), start, tolerance: tolerance) { left -= 1 }
        var right = x
        while right < pixels.width - 1, !differs(pixels.rgb(right + 1, y), start, tolerance: tolerance) { right += 1 }
        var top = y
        while top > 0, !differs(pixels.rgb(x, top - 1), start, tolerance: tolerance) { top -= 1 }
        var bottom = y
        while bottom < pixels.height - 1, !differs(pixels.rgb(x, bottom + 1), start, tolerance: tolerance) { bottom += 1 }

        return EdgeDistances(left: x - left, right: right - x, up: y - top, down: bottom - y)
    }

    /// Shrinks a dragged rectangle to the bounds of whatever sits inside it.
    ///
    /// The background is the most common color along the rectangle's border; the result is
    /// the bounding box of every pixel that differs from it. If nothing differs, the
    /// (clamped) rectangle is returned unchanged.
    static func snap(in pixels: PixelBuffer, rect: PixelRect, tolerance: Int = defaultTolerance) -> PixelRect {
        let x0 = min(max(0, rect.x), pixels.width)
        let y0 = min(max(0, rect.y), pixels.height)
        let x1 = min(max(x0, rect.x + rect.width), pixels.width)
        let y1 = min(max(y0, rect.y + rect.height), pixels.height)
        let clamped = PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard clamped.width > 0, clamped.height > 0 else { return clamped }

        func key(_ c: PixelBuffer.RGB) -> Int { c.r << 16 | c.g << 8 | c.b }
        var counts: [Int: Int] = [:]
        for x in x0..<x1 {
            counts[key(pixels.rgb(x, y0)), default: 0] += 1
            counts[key(pixels.rgb(x, y1 - 1)), default: 0] += 1
        }
        for y in y0..<y1 {
            counts[key(pixels.rgb(x0, y)), default: 0] += 1
            counts[key(pixels.rgb(x1 - 1, y)), default: 0] += 1
        }
        guard let backgroundKey = counts.max(by: { $0.value < $1.value })?.key else { return clamped }
        let background: PixelBuffer.RGB = ((backgroundKey >> 16) & 255, (backgroundKey >> 8) & 255, backgroundKey & 255)

        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in y0..<y1 {
            for x in x0..<x1 where differs(pixels.rgb(x, y), background, tolerance: tolerance) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return clamped }
        return PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

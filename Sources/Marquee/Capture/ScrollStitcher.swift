import CoreGraphics
import Foundation

/// One captured frame of the scrolling area: RGBA8 pixels plus a fingerprint per row.
struct ScrollFrame {
    let width: Int
    let height: Int
    let data: [UInt8]
    /// A hash of each row, leaving out the right edge where the scroll bar comes and goes.
    let rowHashes: [UInt64]
    /// Rows that are one solid color (blank space) match anywhere, so they don't count as evidence.
    let flatRows: [Bool]

    /// - Parameter ignoreRight: pixels at the right edge left out of the row hashes.
    init(width: Int, height: Int, data: [UInt8], ignoreRight: Int = 0) {
        precondition(data.count == width * height * 4, "RGBA buffer has the wrong size")
        self.width = width
        self.height = height
        self.data = data
        let usable = max(1, width - max(0, ignoreRight))
        var hashes = [UInt64](repeating: 0, count: height)
        var flat = [Bool](repeating: true, count: height)
        data.withUnsafeBufferPointer { bytes in
            for y in 0..<height {
                let row = y * width * 4
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                let first = (bytes[row], bytes[row + 1], bytes[row + 2])
                var isFlat = true
                for x in 0..<usable {
                    let i = row + x * 4
                    // Drop the lowest bits so dithering and compression noise don't break matches.
                    let r = bytes[i] >> 2, g = bytes[i + 1] >> 2, b = bytes[i + 2] >> 2
                    hash = (hash ^ UInt64(r)) &* 0x100_0000_01b3
                    hash = (hash ^ UInt64(g)) &* 0x100_0000_01b3
                    hash = (hash ^ UInt64(b)) &* 0x100_0000_01b3
                    if isFlat, bytes[i] != first.0 || bytes[i + 1] != first.1 || bytes[i + 2] != first.2 {
                        isFlat = false
                    }
                }
                hashes[y] = hash
                flat[y] = isFlat
            }
        }
        self.rowHashes = hashes
        self.flatRows = flat
    }

    init?(image: CGImage, ignoreRight: Int = 0) {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, data: data, ignoreRight: ignoreRight)
    }
}

/// Builds one tall image from frames of an area being scrolled down.
///
/// Each new frame is compared with the last one used: rows that stay put at the top and
/// bottom (a site header, a bottom bar) are set aside, and the moving middle is matched by
/// row fingerprints to find how far the content scrolled. Only the newly revealed rows are
/// added. The fixed bottom rows are added once, at the end.
struct ScrollStitcher {
    enum Step: Equatable {
        /// The content moved down by this many rows, which were added.
        case added(Int)
        /// Nothing moved (or it moved up, which is ignored).
        case unchanged
        /// No good match: scrolled too far between frames, or the content changed too much.
        case lost
        /// The image reached `maxHeight`; further frames are ignored.
        case full
    }

    let width: Int
    let maxHeight: Int
    private(set) var rows: [UInt8]
    private var reference: ScrollFrame
    /// Height of the fixed bottom bar, found on the first movement and trimmed from the image.
    private var footer: Int?

    var height: Int { rows.count / (width * 4) }

    init(first: ScrollFrame, maxHeight: Int = 40_000) {
        width = first.width
        self.maxHeight = maxHeight
        rows = first.data
        reference = first
    }

    mutating func add(_ frame: ScrollFrame) -> Step {
        guard frame.width == width, frame.height == reference.height else { return .lost }
        if height >= maxHeight { return .full }
        let previous = reference
        let h = frame.height

        // Fixed rows at the top and bottom: identical in the same place in both frames.
        var top = 0
        while top < h, previous.rowHashes[top] == frame.rowHashes[top] { top += 1 }
        if top == h { return .unchanged }
        var bottom = 0
        while bottom < h - top, previous.rowHashes[h - 1 - bottom] == frame.rowHashes[h - 1 - bottom] { bottom += 1 }
        let middleEnd = h - bottom
        let middle = middleEnd - top
        guard middle > 8 else { return .lost }

        // Find the scroll distance d: the frame's middle row i shows what the previous frame
        // had at row i + d. Score only rows with real content; keep at least a quarter overlap.
        let minOverlap = max(8, middle / 4)
        var best = (distance: 0, score: 0, compared: 0)
        if middle - minOverlap >= 1 {
            for d in 1...(middle - minOverlap) {
                var score = 0, compared = 0
                for i in top..<(middleEnd - d) where !frame.flatRows[i] {
                    compared += 1
                    if frame.rowHashes[i] == previous.rowHashes[i + d] { score += 1 }
                }
                if score > best.score { best = (d, score, compared) }
            }
        }
        guard best.score >= 6, Double(best.score) >= Double(best.compared) * 0.6 else { return .lost }

        // The first time content moves, the old fixed bottom bar comes off the image; it's
        // put back from the last frame when the image is made.
        if footer == nil {
            footer = bottom
            rows.removeLast(min(bottom, height) * width * 4)
        }
        let d = best.distance
        let startRow = middleEnd - d
        let room = max(0, maxHeight - height)
        let count = min(d, room)
        let rowBytes = width * 4
        rows.append(contentsOf: frame.data[(startRow * rowBytes)..<((startRow + count) * rowBytes)])
        reference = frame
        return count < d ? .full : .added(count)
    }

    /// The finished image: everything stitched, then the fixed bottom bar from the last frame.
    func image() -> CGImage? {
        var all = rows
        if let footer, footer > 0 {
            let rowBytes = width * 4
            let start = (reference.height - footer) * rowBytes
            all.append(contentsOf: reference.data[start..<(reference.height * rowBytes)])
        }
        let height = all.count / (width * 4)
        guard height > 0,
              let provider = CGDataProvider(data: Data(all) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

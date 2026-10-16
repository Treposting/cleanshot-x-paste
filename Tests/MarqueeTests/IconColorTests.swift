import AppKit
import XCTest
@testable import Marquee

final class IconColorTests: XCTestCase {
    /// An image split into two vertical bands of the given colors, `share` of it the first.
    private func image(_ first: NSColor, _ second: NSColor, share: CGFloat) -> CGImage {
        let side = 32
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let split = CGFloat(side) * share
        context.setFillColor(first.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: split, height: CGFloat(side)))
        context.setFillColor(second.cgColor)
        context.fill(CGRect(x: split, y: 0, width: CGFloat(side) - split, height: CGFloat(side)))
        return context.makeImage()!
    }

    func testPicksTheBiggestColorfulArea() {
        let blue = NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 1)
        let red = NSColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 1)
        XCTAssertEqual(IconColor.dominant(in: image(blue, red, share: 0.75))?.hex, "#0066FF")
    }

    func testIgnoresGraysWhenThereIsColor() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let green = NSColor(srgbRed: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        XCTAssertEqual(IconColor.dominant(in: image(white, green, share: 0.75))?.hex, "#33CC4D")
    }

    func testGrayIconsFallBackToTheirAverage() {
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let gray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let color = IconColor.dominant(in: image(black, gray, share: 0.5))
        XCTAssertNotNil(color)
        XCTAssertEqual(color!.red, color!.blue, accuracy: 0.01)
    }
}

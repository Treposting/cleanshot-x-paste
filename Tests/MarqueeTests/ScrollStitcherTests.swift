import XCTest
@testable import Marquee

final class ScrollStitcherTests: XCTestCase {
    /// A tall "page" where every row has its own pattern that never repeats, like real content,
    /// with a blank gap every 50 rows.
    private func page(width: Int, height: Int) -> [UInt8] {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let seed = UInt64(y + 1) &* 0x9E37_79B9_7F4A_7C15
            for x in 0..<width {
                let i = (y * width + x) * 4
                let blank = y % 50 >= 45
                let v = (seed ^ (UInt64(x) &* 0xBF58_476D_1CE4_E5B9)) &* 0x94D0_49BB_1331_11EB
                data[i] = blank ? 250 : UInt8(truncatingIfNeeded: v >> 16)
                data[i + 1] = blank ? 250 : UInt8(truncatingIfNeeded: v >> 32)
                data[i + 2] = blank ? 250 : UInt8(truncatingIfNeeded: v >> 48)
                data[i + 3] = 255
            }
        }
        return data
    }

    /// What a window of `height` rows shows when scrolled to `offset`, with optional fixed
    /// header and footer bars painted over it.
    private func frame(_ page: [UInt8], width: Int, offset: Int, height: Int,
                       header: Int = 0, footer: Int = 0) -> ScrollFrame {
        let rowBytes = width * 4
        var data = Array(page[(offset * rowBytes)..<((offset + height) * rowBytes)])
        for y in 0..<header { for b in 0..<rowBytes { data[y * rowBytes + b] = b % 4 == 3 ? 255 : 40 } }
        for y in (height - footer)..<height {
            for b in 0..<rowBytes { data[y * rowBytes + b] = b % 4 == 3 ? 255 : UInt8(90 + (y % 3)) }
        }
        return ScrollFrame(width: width, height: height, data: data)
    }

    func testStitchesAPlainScroll() throws {
        let w = 40, view = 100
        let content = page(width: w, height: 400)
        var stitcher = ScrollStitcher(first: frame(content, width: w, offset: 0, height: view))
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 30, height: view)), .added(30))
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 30, height: view)), .unchanged)
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 85, height: view)), .added(55))
        XCTAssertEqual(stitcher.height, 185)

        let image = try XCTUnwrap(stitcher.image())
        XCTAssertEqual(image.height, 185)
        // The stitched rows are exactly the page's first 185 rows.
        XCTAssertEqual(stitcher.rows, Array(content[0..<(185 * w * 4)]))
    }

    func testFixedHeaderAndFooterAppearOnce() throws {
        let w = 40, view = 120, header = 12, footer = 10
        let content = page(width: w, height: 500)
        var stitcher = ScrollStitcher(first: frame(content, width: w, offset: 0, height: view, header: header, footer: footer))
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 40, height: view, header: header, footer: footer)), .added(40))
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 90, height: view, header: header, footer: footer)), .added(50))

        // Header + content scrolled past + the footer once: view + 90 rows in total.
        let image = try XCTUnwrap(stitcher.image())
        XCTAssertEqual(image.height, view + 90)
    }

    func testScrollingUpIsIgnoredAndTooFarIsLost() {
        let w = 40, view = 100
        let content = page(width: w, height: 600)
        var stitcher = ScrollStitcher(first: frame(content, width: w, offset: 100, height: view))
        XCTAssertNotEqual(stitcher.add(frame(content, width: w, offset: 60, height: view)).isAdded, true,
                          "moving up never adds rows")
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 400, height: view)), .lost,
                       "no overlap with the last frame")
        XCTAssertEqual(stitcher.height, view)
        // After getting lost, scrolling back near the last good frame picks up again.
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 130, height: view)), .added(30))
    }

    func testStopsAtTheHeightLimit() {
        let w = 20, view = 100
        let content = page(width: w, height: 600)
        var stitcher = ScrollStitcher(first: frame(content, width: w, offset: 0, height: view), maxHeight: 150)
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 70, height: view)), .full)
        XCTAssertEqual(stitcher.height, 150)
        XCTAssertEqual(stitcher.add(frame(content, width: w, offset: 120, height: view)), .full)
    }

    func testScrollBarEdgeIsIgnored() {
        let w = 40, view = 100
        let content = page(width: w, height: 400)
        let a = Array(content[0..<(view * w * 4)])
        var b = Array(content[(30 * w * 4)..<((30 + view) * w * 4)])
        // A scroll bar appears in the last 4 columns of the second frame only.
        for y in 0..<view { for x in (w - 4)..<w { b[(y * w + x) * 4] = 0 } }
        var stitcher = ScrollStitcher(first: ScrollFrame(width: w, height: view, data: a, ignoreRight: 6))
        XCTAssertEqual(stitcher.add(ScrollFrame(width: w, height: view, data: b, ignoreRight: 6)), .added(30))
    }
}

private extension ScrollStitcher.Step {
    var isAdded: Bool {
        if case .added = self { return true }
        return false
    }
}

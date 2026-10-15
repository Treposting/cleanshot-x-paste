import XCTest
@testable import Marquee

final class EdgeFinderTests: XCTestCase {
    private typealias Color = (UInt8, UInt8, UInt8)

    /// A synthetic "screen": a background with filled rectangles painted in order.
    private func screen(width: Int, height: Int, background: Color = (255, 255, 255),
                        boxes: [(PixelRect, Color)] = []) -> PixelBuffer {
        var data = [UInt8](repeating: 255, count: width * height * 4)
        func paint(_ x: Int, _ y: Int, _ c: Color) {
            let i = (y * width + x) * 4
            data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2; data[i + 3] = 255
        }
        for y in 0..<height { for x in 0..<width { paint(x, y, background) } }
        for (rect, color) in boxes {
            for y in rect.y..<(rect.y + rect.height) {
                for x in rect.x..<(rect.x + rect.width) { paint(x, y, color) }
            }
        }
        return PixelBuffer(width: width, height: height, data: data)
    }

    func testDistancesInsideABox() {
        let box = PixelRect(x: 20, y: 10, width: 30, height: 40)
        let pixels = screen(width: 100, height: 80, boxes: [(box, (0, 0, 0))])

        let d = EdgeFinder.distances(in: pixels, x: 30, y: 20, tolerance: 12)

        XCTAssertEqual(d, EdgeDistances(left: 10, right: 19, up: 10, down: 29))
        XCTAssertEqual(d.width, 30)
        XCTAssertEqual(d.height, 40)
    }

    func testDistancesInGapBetweenBoxes() {
        let pixels = screen(width: 100, height: 20, boxes: [
            (PixelRect(x: 0, y: 0, width: 10, height: 20), (0, 0, 0)),
            (PixelRect(x: 60, y: 0, width: 40, height: 20), (0, 0, 0)),
        ])

        let d = EdgeFinder.distances(in: pixels, x: 30, y: 10)

        XCTAssertEqual(d.width, 50, "the white gap runs from x=10 to x=59")
    }

    func testDistancesStopAtImageBounds() {
        let pixels = screen(width: 40, height: 30)

        let d = EdgeFinder.distances(in: pixels, x: 5, y: 5)

        XCTAssertEqual(d, EdgeDistances(left: 5, right: 34, up: 5, down: 24))
    }

    func testToleranceIgnoresSubtleDifferences() {
        let faint = PixelRect(x: 10, y: 0, width: 10, height: 10)
        let pixels = screen(width: 40, height: 10, boxes: [(faint, (250, 250, 250))])

        XCTAssertEqual(EdgeFinder.distances(in: pixels, x: 2, y: 5, tolerance: 12).width, 40)
        XCTAssertEqual(EdgeFinder.distances(in: pixels, x: 2, y: 5, tolerance: 0).width, 10)
    }

    func testOnePixelBorderIsAnEdge() {
        let border = PixelRect(x: 20, y: 0, width: 1, height: 10)
        let pixels = screen(width: 40, height: 10, boxes: [(border, (200, 200, 200))])

        XCTAssertEqual(EdgeFinder.distances(in: pixels, x: 5, y: 5).right, 14)
    }

    func testSnapShrinksToTheElement() {
        let button = PixelRect(x: 20, y: 10, width: 30, height: 12)
        let pixels = screen(width: 100, height: 60, boxes: [(button, (61, 59, 243))])

        let snapped = EdgeFinder.snap(in: pixels, rect: PixelRect(x: 5, y: 2, width: 70, height: 40))

        XCTAssertEqual(snapped, button)
    }

    func testSnapCoversSeveralElements() {
        let pixels = screen(width: 100, height: 60, boxes: [
            (PixelRect(x: 10, y: 10, width: 10, height: 10), (0, 0, 0)),
            (PixelRect(x: 40, y: 30, width: 5, height: 5), (0, 0, 0)),
        ])

        let snapped = EdgeFinder.snap(in: pixels, rect: PixelRect(x: 0, y: 0, width: 100, height: 60))

        XCTAssertEqual(snapped, PixelRect(x: 10, y: 10, width: 35, height: 25))
    }

    func testSnapOnDarkBackground() {
        let card = PixelRect(x: 30, y: 20, width: 20, height: 10)
        let pixels = screen(width: 80, height: 50, background: (28, 28, 30), boxes: [(card, (245, 245, 247))])

        XCTAssertEqual(EdgeFinder.snap(in: pixels, rect: PixelRect(x: 20, y: 10, width: 50, height: 30)), card)
    }

    func testSnapWithNothingInsideKeepsTheRectangle() {
        let pixels = screen(width: 50, height: 50)
        let dragged = PixelRect(x: 5, y: 5, width: 20, height: 20)

        XCTAssertEqual(EdgeFinder.snap(in: pixels, rect: dragged), dragged)
    }

    func testSnapClampsToTheScreen() {
        let pixels = screen(width: 50, height: 50)

        let snapped = EdgeFinder.snap(in: pixels, rect: PixelRect(x: 40, y: 40, width: 30, height: 30))

        XCTAssertEqual(snapped, PixelRect(x: 40, y: 40, width: 10, height: 10))
    }
}

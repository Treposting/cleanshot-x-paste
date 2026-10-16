import XCTest
@testable import Marquee

final class GuideTests: XCTestCase {
    func testAddSelectsAndClampsToTheScreen() {
        var set = GuideSet(width: 200, height: 100)
        let a = set.add(.vertical, at: 50)
        XCTAssertEqual(set.selected, a)
        let b = set.add(.vertical, at: 500)
        XCTAssertEqual(b.position, 200, "a vertical guide can sit on the right edge, not past it")
        XCTAssertEqual(set.add(.horizontal, at: -5).position, 0)
        XCTAssertEqual(set.selected?.axis, .horizontal)
    }

    func testNudgeMovesOnlyTheSelectedGuide() {
        var set = GuideSet(width: 200, height: 100)
        let a = set.add(.vertical, at: 50)
        let b = set.add(.vertical, at: 80)
        set.nudgeSelected(by: 2)
        set.nudgeSelected(by: -20)
        XCTAssertEqual(set.guides.first { $0.id == b.id }?.position, 62)
        XCTAssertEqual(set.guides.first { $0.id == a.id }?.position, 50)
        set.nudgeSelected(by: -1000)
        XCTAssertEqual(set.selected?.position, 0)
    }

    func testNudgeAndRemoveNeedASelection() {
        var set = GuideSet(width: 200, height: 100)
        set.add(.horizontal, at: 10)
        set.select(nil)
        XCTAssertFalse(set.nudgeSelected(by: 1))
        XCTAssertFalse(set.removeSelected())
        set.selectNext()
        XCTAssertTrue(set.removeSelected())
        XCTAssertTrue(set.isEmpty)
    }

    func testSelectNextWrapsAround() {
        var set = GuideSet(width: 200, height: 100)
        let a = set.add(.vertical, at: 10)
        let b = set.add(.horizontal, at: 20)
        XCTAssertEqual(set.selectedID, b.id)
        set.selectNext()
        XCTAssertEqual(set.selectedID, a.id)
        set.selectNext()
        XCTAssertEqual(set.selectedID, b.id)
    }

    func testHitFindsTheClosestGuideOnItsAxis() {
        var set = GuideSet(width: 200, height: 100)
        let v = set.add(.vertical, at: 100)
        let h = set.add(.horizontal, at: 40)
        XCTAssertEqual(set.hit(x: 103, y: 80, within: 6), v)
        XCTAssertEqual(set.hit(x: 10, y: 38, within: 6), h)
        XCTAssertNil(set.hit(x: 120, y: 80, within: 6))
    }

    func testGapsBetweenNeighbours() {
        var set = GuideSet(width: 300, height: 100)
        set.add(.vertical, at: 200)
        set.add(.vertical, at: 50)
        set.add(.vertical, at: 120)
        set.add(.vertical, at: 120)
        set.add(.horizontal, at: 30)
        XCTAssertEqual(set.gaps(.vertical), [GuideGap(start: 50, end: 120), GuideGap(start: 120, end: 200)])
        XCTAssertEqual(set.gaps(.vertical).map(\.length), [70, 80])
        XCTAssertEqual(set.gaps(.horizontal), [])
    }

    func testGuideSnapsToANearbyEdge() {
        // A black box from x=40 to x=79 on white; the pointer is inside it.
        var data = [UInt8](repeating: 255, count: 120 * 20 * 4)
        for y in 0..<20 {
            for x in 40..<80 {
                let i = (y * 120 + x) * 4
                data[i] = 0; data[i + 1] = 0; data[i + 2] = 0
            }
        }
        let pixels = PixelBuffer(width: 120, height: 20, data: data)

        XCTAssertEqual(EdgeFinder.snapGuide(.vertical, position: 43, pointerX: 43, pointerY: 10, in: pixels, within: 8), 40)
        XCTAssertEqual(EdgeFinder.snapGuide(.vertical, position: 77, pointerX: 77, pointerY: 10, in: pixels, within: 8), 80)
        XCTAssertEqual(EdgeFinder.snapGuide(.vertical, position: 60, pointerX: 60, pointerY: 10, in: pixels, within: 8), 60,
                       "too far from either edge, so it stays where it is")
        XCTAssertEqual(EdgeFinder.snapGuide(.horizontal, position: 3, pointerX: 60, pointerY: 3, in: pixels, within: 8), 0)
    }
}

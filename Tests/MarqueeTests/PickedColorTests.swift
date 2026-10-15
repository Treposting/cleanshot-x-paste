import XCTest
@testable import Marquee

final class PickedColorTests: XCTestCase {
    func testFormatsForBrandYellow() {
        let yellow = PickedColor(red: 1, green: 207.0 / 255, blue: 26.0 / 255)
        XCTAssertEqual(yellow.hex, "#FFCF1A")
        XCTAssertEqual(yellow.rgb, "rgb(255, 207, 26)")
        XCTAssertEqual(yellow.hsl, "hsl(47, 100%, 55%)")
        XCTAssertEqual(yellow.swiftUI, "Color(red: 1.000, green: 0.812, blue: 0.102)")
    }

    func testGraysHaveNoHueOrSaturation() {
        XCTAssertEqual(PickedColor(red: 0, green: 0, blue: 0).hsl, "hsl(0, 0%, 0%)")
        XCTAssertEqual(PickedColor(red: 1, green: 1, blue: 1).hsl, "hsl(0, 0%, 100%)")
        XCTAssertEqual(PickedColor(red: 0.5, green: 0.5, blue: 0.5).hex, "#808080")
    }

    func testPrimaryHues() {
        XCTAssertEqual(PickedColor(red: 1, green: 0, blue: 0).hsl, "hsl(0, 100%, 50%)")
        XCTAssertEqual(PickedColor(red: 0, green: 1, blue: 0).hsl, "hsl(120, 100%, 50%)")
        XCTAssertEqual(PickedColor(red: 0, green: 0, blue: 1).hsl, "hsl(240, 100%, 50%)")
        XCTAssertEqual(PickedColor(red: 1, green: 0, blue: 1).hsl, "hsl(300, 100%, 50%)")
    }

    func testFormatSelection() {
        let blue = PickedColor(red: 0, green: 0, blue: 1)
        XCTAssertEqual(blue.string(in: .hex), "#0000FF")
        XCTAssertEqual(blue.string(in: .rgb), "rgb(0, 0, 255)")
    }
}

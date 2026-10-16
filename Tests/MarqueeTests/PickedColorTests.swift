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

    func testParsesHexForms() {
        XCTAssertEqual(PickedColor(parsing: "#FFCF1A")?.hex, "#FFCF1A")
        XCTAssertEqual(PickedColor(parsing: "  #ffcf1a\n")?.hex, "#FFCF1A")
        XCTAssertEqual(PickedColor(parsing: "#0f8")?.hex, "#00FF88")
        XCTAssertEqual(PickedColor(parsing: "#0f8c")?.hex, "#00FF88")
        XCTAssertEqual(PickedColor(parsing: "#FFCF1A80")?.hex, "#FFCF1A")
    }

    func testParsesFunctionalForms() {
        XCTAssertEqual(PickedColor(parsing: "rgb(255, 207, 26)")?.hex, "#FFCF1A")
        XCTAssertEqual(PickedColor(parsing: "rgba(255 207 26 / 0.5)")?.hex, "#FFCF1A")
        XCTAssertEqual(PickedColor(parsing: "rgb(100%, 0%, 0%)")?.hex, "#FF0000")
        XCTAssertEqual(PickedColor(parsing: "hsl(240, 100%, 50%)")?.hex, "#0000FF")
        XCTAssertEqual(PickedColor(parsing: "hsl(120deg 100% 25%)")?.hex, "#008000")
        // What Marquee copies parses back to the same color.
        let yellow = PickedColor(red: 1, green: 207.0 / 255, blue: 26.0 / 255)
        XCTAssertEqual(PickedColor(parsing: yellow.rgb)?.hex, yellow.hex)
    }

    func testRejectsTextThatIsNotJustAColor() {
        XCTAssertNil(PickedColor(parsing: "123456"))
        XCTAssertNil(PickedColor(parsing: "#12345"))
        XCTAssertNil(PickedColor(parsing: "#GGGGGG"))
        XCTAssertNil(PickedColor(parsing: "Issue #123"))
        XCTAssertNil(PickedColor(parsing: "#FFCF1A is the brand yellow"))
        XCTAssertNil(PickedColor(parsing: "rgb(300, 0, 0)"))
        XCTAssertNil(PickedColor(parsing: "rgb(1, 2)"))
        XCTAssertNil(PickedColor(parsing: "calc(1 + 2 + 3)"))
        XCTAssertNil(PickedColor(parsing: ""))
    }
}

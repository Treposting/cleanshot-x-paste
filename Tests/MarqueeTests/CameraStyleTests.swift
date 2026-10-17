import XCTest
@testable import Marquee

final class CameraStyleTests: XCTestCase {
    func testBubbleSitsInTheChosenCornerOfTheArea() {
        let area = CGRect(x: 100, y: 50, width: 800, height: 600)
        let size = CGSize(width: 170, height: 170)
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .bottomLeft).origin, CGPoint(x: 124, y: 74))
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .bottomRight).origin, CGPoint(x: 706, y: 74))
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .topLeft).origin, CGPoint(x: 124, y: 456))
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .topRight).origin, CGPoint(x: 706, y: 456))
    }

    func testShapes() {
        XCTAssertEqual(CameraStyle.Shape.circle.cornerRadius(for: CGSize(width: 170, height: 170)), 85)
        XCTAssertEqual(CameraStyle.Shape.portrait.aspect, 0.75)
        XCTAssertEqual(CameraStyle.Shape.square.aspect, 1)
    }
}

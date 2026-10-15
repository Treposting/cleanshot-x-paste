import XCTest
@testable import Marquee

final class ElapsedTimeTests: XCTestCase {
    func testSecondsThenMinutesThenHours() {
        XCTAssertEqual(ElapsedTime.format(0), "0s")
        XCTAssertEqual(ElapsedTime.format(12.9), "12s")
        XCTAssertEqual(ElapsedTime.format(59), "59s")
        XCTAssertEqual(ElapsedTime.format(60), "1:00")
        XCTAssertEqual(ElapsedTime.format(245), "4:05")
        XCTAssertEqual(ElapsedTime.format(3599), "59:59")
        XCTAssertEqual(ElapsedTime.format(3600), "1:00:00")
        XCTAssertEqual(ElapsedTime.format(3845), "1:04:05")
    }

    func testNegativeIsZero() {
        XCTAssertEqual(ElapsedTime.format(-3), "0s")
    }
}

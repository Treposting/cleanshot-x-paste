import XCTest
@testable import Marquee

final class AppVersionTests: XCTestCase {
    func testParsesTagsAndPlainVersions() {
        XCTAssertEqual(AppVersion("v0.3.0")?.parts, [0, 3, 0])
        XCTAssertEqual(AppVersion("1.2")?.parts, [1, 2])
        XCTAssertEqual(AppVersion("2.0.0-beta.1")?.parts, [2, 0, 0])
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
    }

    func testOrdering() throws {
        let v = { (s: String) in try XCTUnwrap(AppVersion(s)) }
        XCTAssertLessThan(try v("0.3.0"), try v("0.4.0"))
        XCTAssertLessThan(try v("0.9.9"), try v("0.10.0"))
        XCTAssertLessThan(try v("1.2"), try v("1.2.1"))
        XCTAssertGreaterThan(try v("1.0.0"), try v("0.99.99"))
        XCTAssertEqual(try v("1.2"), try v("1.2.0"))
        XCTAssertFalse(try v("1.2.0") < v("1.2"))
    }

    func testDescription() {
        XCTAssertEqual(AppVersion("v0.3.0")?.description, "0.3.0")
    }
}

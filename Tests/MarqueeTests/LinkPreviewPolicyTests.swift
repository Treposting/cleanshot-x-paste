import XCTest
@testable import Marquee

final class LinkPreviewPolicyTests: XCTestCase {
    private func allows(_ string: String) -> Bool { LinkPreviewPolicy.allows(URL(string: string)!) }

    func testAllowsPublicWebsites() {
        XCTAssertTrue(allows("https://github.com/Treposting/marquee"))
        XCTAssertTrue(allows("http://example.com/page?x=1"))
        XCTAssertTrue(allows("https://8.8.8.8/"))
    }

    func testNeverLoadsLocalOrPrivateAddresses() {
        XCTAssertFalse(allows("http://localhost:3000"))
        XCTAssertFalse(allows("http://127.0.0.1:8080/admin"))
        XCTAssertFalse(allows("http://192.168.1.1"))
        XCTAssertFalse(allows("http://10.0.0.5/files"))
        XCTAssertFalse(allows("http://172.20.1.1"))
        XCTAssertFalse(allows("http://169.254.1.1"))
        XCTAssertFalse(allows("http://100.100.1.1"))
        XCTAssertFalse(allows("http://nas.local/share"))
        XCTAssertFalse(allows("http://printer.lan"))
        XCTAssertFalse(allows("http://[::1]:8000"))
        XCTAssertFalse(allows("http://[fd00::1]/"))
        XCTAssertFalse(allows("http://intranet/wiki"), "single-label hosts are local names")
    }

    func testOnlyWebLinks() {
        XCTAssertFalse(allows("ftp://example.com/file"))
        XCTAssertFalse(allows("file:///Users/me/notes.txt"))
        XCTAssertFalse(allows("mailto:someone@example.com"))
    }
}

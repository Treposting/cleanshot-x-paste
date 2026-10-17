import XCTest
@testable import Marquee

final class ClipCategoryTests: XCTestCase {
    func testCopiedAgeHasNoSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func age(_ seconds: TimeInterval) -> String { CopiedAge.text(since: now.addingTimeInterval(-seconds), now: now) }
        XCTAssertEqual(age(0), "Just now")
        XCTAssertEqual(age(59), "Just now")
        XCTAssertEqual(age(60), "1 min ago")
        XCTAssertEqual(age(5 * 60 + 40), "5 min ago")
        XCTAssertEqual(age(2 * 3600 + 10), "2 hr ago")
        XCTAssertEqual(age(3 * 86_400), "3 days ago")
        XCTAssertEqual(CopiedAge.text(since: now.addingTimeInterval(60), now: now), "Just now", "clock skew is not negative")
    }

    func testFilterMatchesCategoryAndKinds() {
        var link = ClipItem(kind: .link, text: "https://example.com", contentHash: "a", sourceAppName: nil, sourceBundleID: nil)
        let category = ClipCategory(name: "Work", tint: .blue)
        XCTAssertTrue(ClipFilter.links.matches(link))
        XCTAssertFalse(ClipFilter.category(category.id).matches(link))
        link.categoryID = category.id
        XCTAssertTrue(ClipFilter.category(category.id).matches(link))
        XCTAssertTrue(link.isKept, "items in a category are kept like pinned ones")
    }

    func testOldHistoryWithoutCategoriesStillLoads() throws {
        let json = """
        [{"id":"7B1D6C2E-8C1A-4B7E-9A51-0E2F7B6A1C11","kind":"text","text":"hi","contentHash":"x",
          "date":0,"pinned":false}]
        """
        let items = try JSONDecoder().decode([ClipItem].self, from: Data(json.utf8))
        XCTAssertEqual(items.first?.text, "hi")
        XCTAssertNil(items.first?.categoryID)
    }
}

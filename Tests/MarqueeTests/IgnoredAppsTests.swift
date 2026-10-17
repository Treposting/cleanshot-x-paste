import XCTest
@testable import Marquee

final class IgnoredAppsTests: XCTestCase {
    func testPasswordManagersAreIgnoredWhenTheSettingIsOn() {
        XCTAssertTrue(IgnoredApps.isIgnored("com.apple.Passwords", custom: [], passwordManagers: true))
        XCTAssertTrue(IgnoredApps.isIgnored("com.1password.1password", custom: [], passwordManagers: true))
        XCTAssertTrue(IgnoredApps.isIgnored("com.apple.keychainaccess", custom: [], passwordManagers: true))
        XCTAssertFalse(IgnoredApps.isIgnored("com.apple.Passwords", custom: [], passwordManagers: false))
    }

    func testUserListApplies() {
        XCTAssertTrue(IgnoredApps.isIgnored("com.example.bank", custom: ["com.example.bank"], passwordManagers: false))
        XCTAssertFalse(IgnoredApps.isIgnored("com.apple.Safari", custom: ["com.example.bank"], passwordManagers: true))
    }

    func testUnknownSourceIsKept() {
        XCTAssertFalse(IgnoredApps.isIgnored(nil, custom: ["com.example.bank"], passwordManagers: true))
    }
}

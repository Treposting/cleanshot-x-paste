import Carbon
import XCTest
@testable import Marquee

final class KeyComboTests: XCTestCase {
    func testStorageRoundTrip() {
        let combo = KeyCombo(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey | optionKey)
        XCTAssertEqual(KeyCombo(storageString: combo.storageString), combo)
        XCTAssertNil(KeyCombo(storageString: "none"))
    }

    func testDisplayString() {
        XCTAssertEqual(KeyCombo(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey | optionKey).displayString, "⌥⇧⌘4")
        XCTAssertEqual(KeyCombo(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey).displayString, "⇧⌘V")
        XCTAssertEqual(KeyCombo(keyCode: kVK_F5, modifiers: 0).displayString, "F5")
    }

    func testValidity() {
        XCTAssertFalse(KeyCombo(keyCode: kVK_ANSI_A, modifiers: shiftKey).isValid, "Shift alone would eat normal typing")
        XCTAssertFalse(KeyCombo(keyCode: kVK_ANSI_A, modifiers: 0).isValid)
        XCTAssertTrue(KeyCombo(keyCode: kVK_ANSI_A, modifiers: controlKey).isValid)
        XCTAssertTrue(KeyCombo(keyCode: kVK_F5, modifiers: 0).isValid, "Function keys work without modifiers")
    }

    func testDefaultsAreUnique() {
        let combos = ShortcutAction.allCases.compactMap(\.defaultCombo).map(\.storageString)
        XCTAssertEqual(combos.count, Set(combos).count)
    }

    func testMenuKeyEquivalent() {
        XCTAssertEqual(KeyCombo(keyCode: kVK_ANSI_M, modifiers: cmdKey).menuKeyEquivalent, "m")
        XCTAssertNil(KeyCombo(keyCode: kVK_F5, modifiers: 0).menuKeyEquivalent)
    }
}

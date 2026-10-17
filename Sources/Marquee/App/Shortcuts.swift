import AppKit
import Carbon

/// A key + modifier combination, stored with Carbon modifier flags so it can be
/// handed straight to `RegisterEventHotKey`.
struct KeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = KeyCombo.carbonFlags(from: event.modifierFlags)
    }

    init?(storageString: String) {
        let parts = storageString.split(separator: ":").compactMap { UInt32($0) }
        guard parts.count == 2 else { return nil }
        keyCode = parts[0]
        modifiers = parts[1]
    }

    var storageString: String { "\(keyCode):\(modifiers)" }

    var isFunctionKey: Bool { KeyNames.functionKeys.contains(Int(keyCode)) }

    /// Shift alone is not enough for a global shortcut (it would eat normal typing).
    var isValid: Bool {
        let required = UInt32(cmdKey | controlKey | optionKey)
        return modifiers & required != 0 || isFunctionKey
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyNames.name(for: Int(keyCode))
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Key equivalent for showing the shortcut next to a menu item, when the key is a plain character.
    var menuKeyEquivalent: String? {
        let name = KeyNames.name(for: Int(keyCode))
        guard name.count == 1, KeyNames.characterKeys.contains(Int(keyCode)) else { return nil }
        return name.lowercased()
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return UInt32(m)
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case allInOne
    case captureArea
    case captureWindow
    case captureFullscreen
    case captureTimed
    case captureText
    case captureScrolling
    case recordArea
    case recordScreen
    case measure
    case pickColor
    case clipboardHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .captureFullscreen: return "Capture Full Screen"
        case .captureTimed: return "Capture Full Screen in 5 Seconds"
        case .captureText: return "Capture Text (OCR)"
        case .captureScrolling: return "Capture Scrolling"
        case .recordArea: return "Record Area"
        case .recordScreen: return "Record Screen"
        case .measure: return "Measure"
        case .pickColor: return "Pick Color"
        case .clipboardHistory: return "Clipboard History"
        }
    }

    enum Category: String, CaseIterable, Identifiable {
        case capture = "Capture"
        case record = "Record"
        case tools = "Tools"
        case clipboard = "Clipboard"

        var id: String { rawValue }

        var actions: [ShortcutAction] { ShortcutAction.allCases.filter { $0.category == self } }
    }

    var category: Category {
        switch self {
        case .allInOne, .captureArea, .captureWindow, .captureFullscreen, .captureTimed, .captureText, .captureScrolling:
            return .capture
        case .recordArea, .recordScreen: return .record
        case .measure, .pickColor: return .tools
        case .clipboardHistory: return .clipboard
        }
    }

    /// Only the two entry points get a shortcut out of the box; everything else is reachable
    /// from All-in-One, the menu bar and the Marquee window, and users add shortcuts they want.
    var defaultCombo: KeyCombo? {
        switch self {
        case .allInOne: return KeyCombo(keyCode: kVK_ANSI_A, modifiers: cmdKey | shiftKey | optionKey)
        case .clipboardHistory: return KeyCombo(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey)
        default: return nil
        }
    }
}

/// Persists user-chosen shortcuts in UserDefaults ("shortcut.<action>").
/// A missing value means "use the default"; "none" means the user cleared it.
enum ShortcutStore {
    static let didChange = Notification.Name("Marquee.shortcutsDidChange")
    /// Posted while a recorder is listening, so global hotkeys can be suspended
    /// (otherwise the system would swallow an already-registered combo).
    static let recordingWillBegin = Notification.Name("Marquee.shortcutRecordingWillBegin")
    static let recordingDidEnd = Notification.Name("Marquee.shortcutRecordingDidEnd")

    private static var defaults: UserDefaults { .standard }
    private static func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }

    static func combo(for action: ShortcutAction) -> KeyCombo? {
        guard let stored = defaults.string(forKey: key(action)) else { return action.defaultCombo }
        return KeyCombo(storageString: stored)
    }

    static func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        if let combo {
            // One combo can only trigger one action: clear any other owner.
            for other in ShortcutAction.allCases where other != action && self.combo(for: other) == combo {
                defaults.set("none", forKey: key(other))
            }
        }
        defaults.set(combo?.storageString ?? "none", forKey: key(action))
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func reset(_ action: ShortcutAction) {
        defaults.removeObject(forKey: key(action))
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func resetAll() {
        ShortcutAction.allCases.forEach { defaults.removeObject(forKey: key($0)) }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// Human-readable names for virtual key codes (US layout labels).
enum KeyNames {
    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let characters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]

    static var characterKeys: Set<Int> { Set(characters.keys) }

    private static let special: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func name(for keyCode: Int) -> String {
        characters[keyCode] ?? special[keyCode] ?? "Key \(keyCode)"
    }
}

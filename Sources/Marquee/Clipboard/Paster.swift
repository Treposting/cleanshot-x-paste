import AppKit
import ApplicationServices

/// Simulates ⌘V in the frontmost app. Needs the Accessibility permission
/// (System Settings → Privacy & Security → Accessibility).
@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func pasteIntoFrontApp() {
        guard isTrusted else {
            requestAccess()
            Toast.show("Copied. Allow Marquee in Accessibility to paste directly", duration: 3)
            return
        }
        // Give the previous app a moment to become key again after our panel hides.
        runAfter(0.08) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}

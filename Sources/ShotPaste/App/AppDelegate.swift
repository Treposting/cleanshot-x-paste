import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let captureService = CaptureService()
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var historyPanel = HistoryPanelController(store: store, monitor: monitor)
    private var settingsWindow: NSWindow?
    private var pauseItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        setupStatusItem()
        registerHotKeys()
        monitor.start()
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        let hk = HotKeyCenter.shared
        hk.register(.cmdShiftOption(kVK_ANSI_4)) { [weak self] in self?.capture(.area) }
        hk.register(.cmdShiftOption(kVK_ANSI_5)) { [weak self] in self?.capture(.window) }
        hk.register(.cmdShiftOption(kVK_ANSI_3)) { [weak self] in self?.capture(.fullscreen) }
        hk.register(.cmdShiftOption(kVK_ANSI_2)) { [weak self] in self?.capture(.text) }
        hk.register(.cmdShift(kVK_ANSI_V)) { [weak self] in self?.historyPanel.toggle() }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShotPaste")
        }

        let menu = NSMenu()
        let optCmdShift: NSEvent.ModifierFlags = [.command, .shift, .option]
        menu.addItem(item("Capture Area", #selector(captureArea), key: "4", mods: optCmdShift))
        menu.addItem(item("Capture Window", #selector(captureWindow), key: "5", mods: optCmdShift))
        menu.addItem(item("Capture Fullscreen", #selector(captureFullscreen), key: "3", mods: optCmdShift))
        menu.addItem(item("Capture Fullscreen in 5 s", #selector(captureTimed)))
        menu.addItem(item("Capture Text (OCR)", #selector(captureText), key: "2", mods: optCmdShift))
        menu.addItem(.separator())
        menu.addItem(item("Clipboard History", #selector(showHistory), key: "v", mods: [.command, .shift]))
        let pause = item(pauseTitle, #selector(togglePause))
        pauseItem = pause
        menu.addItem(pause)
        menu.addItem(item("Clear Clipboard History…", #selector(clearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Open Screenshots Folder", #selector(openFolder)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit ShotPaste", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = self
        return item
    }

    private var pauseTitle: String {
        Preferences.monitorPaused ? "Resume Clipboard History" : "Pause Clipboard History"
    }

    @objc private func captureArea() { capture(.area) }
    @objc private func captureWindow() { capture(.window) }
    @objc private func captureFullscreen() { capture(.fullscreen) }
    @objc private func captureTimed() { capture(.timedFullscreen) }
    @objc private func captureText() { capture(.text) }
    @objc private func showHistory() { historyPanel.show() }

    @objc private func togglePause() {
        Preferences.monitorPaused.toggle()
        pauseItem?.title = pauseTitle
        Toast.show(Preferences.monitorPaused ? "Clipboard history paused" : "Clipboard history resumed")
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear(keepPinned: true)
        }
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(Preferences.saveFolder)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "ShotPaste Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Capture flow

    private func capture(_ mode: CaptureMode) {
        captureService.capture(mode) { [weak self] url in
            guard let self, let url else { return }
            if mode == .text {
                self.recognizeText(at: url)
            } else {
                self.handleCapture(at: url)
            }
        }
    }

    private func recognizeText(at url: URL) {
        TextRecognizer.recognize(imageAt: url) { text in
            try? FileManager.default.removeItem(at: url)
            guard !text.isEmpty else {
                Toast.show("No text found")
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            Toast.show("Copied text (\(text.count) characters)")
        }
    }

    private func handleCapture(at url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let capture = Capture(url: url, image: image)
        if Preferences.copyAfterCapture { capture.copyToPasteboard() }
        if Preferences.saveAfterCapture { _ = capture.save() }
        if Preferences.showOverlay {
            QuickAccessManager.shared.show(capture)
        } else if Preferences.copyAfterCapture {
            Toast.show("Screenshot copied")
        }
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainMenu = NSMenu()
    private let captureService = CaptureService()
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var historyPanel = HistoryPanelController(store: store, monitor: monitor)
    private var settingsWindow: NSWindow?
    private var pauseItem: NSMenuItem?
    private var recordingTimer: Timer?
    private var recordingDotVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.migrateLegacySettings()
        Preferences.registerDefaults()
        setupStatusItem()
        registerHotKeys()
        observeShortcutChanges()
        monitor.start()
        let recording = RecordingController.shared
        recording.onRecordingChanged = { [weak self] active in self?.setRecordingUI(active) }
        recording.onFinished = { [weak self] url in self?.deliverRecording(url) }
        recording.onError = { [weak self] error in self?.showRecordingError(error) }
        Updater.shared.onStateChange = { [weak self] in self?.rebuildMenu() }
        Updater.shared.startAutomaticChecks()
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        for action in ShortcutAction.allCases {
            guard let combo = ShortcutStore.combo(for: action) else { continue }
            HotKeyCenter.shared.register(combo) { [weak self] in self?.perform(action) }
        }
    }

    private func observeShortcutChanges() {
        let center = NotificationCenter.default
        center.addObserver(forName: ShortcutStore.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.registerHotKeys()
                self?.rebuildMenu()
            }
        }
        // While the user is typing a new shortcut, global hotkeys must not swallow it.
        center.addObserver(forName: ShortcutStore.recordingWillBegin, object: nil, queue: .main) { _ in
            Task { @MainActor in HotKeyCenter.shared.unregisterAll() }
        }
        center.addObserver(forName: ShortcutStore.recordingDidEnd, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotKeys() }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .captureArea: capture(.area)
        case .captureWindow: capture(.window)
        case .captureFullscreen: capture(.fullscreen)
        case .captureTimed: capture(.timedFullscreen)
        case .captureText: capture(.text)
        case .recordArea: toggleRecording(selectArea: true)
        case .recordScreen: toggleRecording(selectArea: false)
        case .measure: MeasureController.shared.toggle()
        case .clipboardHistory: historyPanel.toggle()
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.idleIcon
        rebuildMenu()
    }

    private static var idleIcon: NSImage? {
        NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Marquee")
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for action: ShortcutAction in [.captureArea, .captureWindow, .captureFullscreen, .captureTimed, .captureText] {
            menu.addItem(actionItem(action))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(.recordArea))
        menu.addItem(actionItem(.recordScreen))
        menu.addItem(.separator())
        menu.addItem(actionItem(.measure))
        menu.addItem(.separator())
        menu.addItem(actionItem(.clipboardHistory))
        let pause = item(pauseTitle, #selector(togglePause))
        pauseItem = pause
        menu.addItem(pause)
        menu.addItem(item("Clear Clipboard History…", #selector(clearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Open Screenshots Folder", #selector(openFolder)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        if Updater.shared.isReadyToInstall {
            menu.addItem(item("Restart to Update", #selector(restartToUpdate)))
        } else {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Marquee", #selector(quit), key: "q"))
        mainMenu = menu
        if !RecordingController.shared.isRecording {
            statusItem.menu = menu
        }
    }

    private func actionItem(_ action: ShortcutAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        if let combo = ShortcutStore.combo(for: action), let key = combo.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.eventModifierFlags
        }
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private var pauseTitle: String {
        Preferences.monitorPaused ? "Resume Clipboard History" : "Pause Clipboard History"
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ShortcutAction(rawValue: raw) else { return }
        perform(action)
    }

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
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "Marquee Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { Updater.shared.check(userInitiated: true) }
    @objc private func restartToUpdate() { Updater.shared.restartToUpdate() }

    // MARK: - Screenshot flow

    private func capture(_ mode: CaptureMode) {
        guard !RecordingController.shared.isBusy, !MeasureController.shared.isActive else { return }
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
        deliver(Capture(url: url, image: image))
    }

    /// Applies the "after capture" preferences to a new screenshot or recording.
    private func deliver(_ capture: Capture) {
        if Preferences.copyAfterCapture { capture.copyToPasteboard() }
        if Preferences.saveAfterCapture { capture.save() }
        if Preferences.showOverlay {
            QuickAccessManager.shared.show(capture)
        } else if Preferences.copyAfterCapture {
            Toast.show(capture.isVideo ? "Recording copied" : "Screenshot copied")
        }
    }

    // MARK: - Recording flow

    private func toggleRecording(selectArea: Bool) {
        guard !MeasureController.shared.isActive else { return }
        RecordingController.shared.toggle(selectArea: selectArea)
    }

    @objc private func stopRecording() {
        RecordingController.shared.stop()
    }

    private func deliverRecording(_ url: URL) {
        Task {
            let poster = await VideoTools.thumbnail(for: url)
                ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil)
                ?? NSImage()
            deliver(Capture(url: url, image: poster, kind: .video))
        }
    }

    /// While recording, the menu-bar item becomes a blinking red dot and the elapsed time
    /// ("12s", then "4:05", then "1:04:05"). Clicking it stops the recording.
    private func setRecordingUI(_ recording: Bool) {
        guard let button = statusItem.button else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if recording {
            statusItem.menu = nil
            recordingDotVisible = true
            button.image = Self.recordingDot(visible: true)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.title = " " + ElapsedTime.format(0)
            button.toolTip = "Recording. Click to stop."
            button.target = self
            button.action = #selector(stopRecording)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateRecordingTime() }
            }
            RunLoop.main.add(timer, forMode: .common)
            recordingTimer = timer
        } else {
            button.image = Self.idleIcon
            button.title = ""
            button.toolTip = nil
            button.action = nil
            button.target = nil
            statusItem.menu = mainMenu
        }
    }

    private func updateRecordingTime() {
        guard let button = statusItem.button, let start = RecordingController.shared.startDate else { return }
        recordingDotVisible.toggle()
        button.image = Self.recordingDot(visible: recordingDotVisible)
        button.title = " " + ElapsedTime.format(Date().timeIntervalSince(start))
    }

    private static func recordingDot(visible: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor.systemRed.withAlphaComponent(visible ? 1 : 0.25).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func showRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't start recording"
        alert.informativeText = """
        \(error.localizedDescription)

        Marquee needs the Screen Recording permission. Enable it in System Settings → \
        Privacy & Security → Screen & System Audio Recording, then quit and reopen Marquee.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

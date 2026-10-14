import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainMenu = NSMenu()
    private let captureService = CaptureService()
    private let recorder = ScreenRecorder()
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var historyPanel = HistoryPanelController(store: store, monitor: monitor)
    private var settingsWindow: NSWindow?
    private var pauseItem: NSMenuItem?
    private var recordingTimer: Timer?
    private var isStartingRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        setupStatusItem()
        registerHotKeys()
        observeShortcutChanges()
        monitor.start()
        recorder.onUnexpectedStop = { [weak self] in self?.stopRecording() }
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
        NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShotPaste")
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
        menu.addItem(actionItem(.clipboardHistory))
        let pause = item(pauseTitle, #selector(togglePause))
        pauseItem = pause
        menu.addItem(pause)
        menu.addItem(item("Clear Clipboard History…", #selector(clearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Open Screenshots Folder", #selector(openFolder)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit ShotPaste", #selector(quit), key: "q"))
        mainMenu = menu
        if !recorder.isRecording {
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
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
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

    // MARK: - Screenshot flow

    private func capture(_ mode: CaptureMode) {
        guard !recorder.isRecording else { return }
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
        if recorder.isRecording {
            stopRecording()
            return
        }
        guard !isStartingRecording else { return }
        if selectArea {
            AreaSelector.select { [weak self] selection in
                guard let self, let selection else { return }
                self.startRecording(screen: selection.0, rect: selection.1)
            }
        } else if let screen = NSScreen.underMouse {
            startRecording(screen: screen, rect: screen.frame)
        }
    }

    private func startRecording(screen: NSScreen, rect: CGRect) {
        isStartingRecording = true
        Task {
            defer { isStartingRecording = false }
            do {
                try await recorder.start(screen: screen, rect: rect)
                setRecordingUI(true)
            } catch {
                showRecordingError(error)
            }
        }
    }

    @objc private func stopRecording() {
        guard recorder.isRecording else { return }
        setRecordingUI(false)
        Task {
            guard let url = await recorder.stop() else {
                Toast.show("Nothing was recorded")
                return
            }
            let poster = await VideoTools.thumbnail(for: url)
                ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil)
                ?? NSImage()
            deliver(Capture(url: url, image: poster, kind: .video))
        }
    }

    /// While recording, the menu-bar icon becomes a red stop button with a timer.
    private func setRecordingUI(_ recording: Bool) {
        guard let button = statusItem.button else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if recording {
            statusItem.menu = nil
            button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")
            button.contentTintColor = .systemRed
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.title = " 0:00"
            button.target = self
            button.action = #selector(stopRecording)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateRecordingTime() }
            }
            RunLoop.main.add(timer, forMode: .common)
            recordingTimer = timer
        } else {
            button.image = Self.idleIcon
            button.contentTintColor = nil
            button.title = ""
            button.action = nil
            button.target = nil
            statusItem.menu = mainMenu
        }
    }

    private func updateRecordingTime() {
        guard let start = recorder.startDate else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        statusItem.button?.title = String(format: " %d:%02d", seconds / 60, seconds % 60)
    }

    private func showRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't start recording"
        alert.informativeText = """
        \(error.localizedDescription)

        ShotPaste needs the Screen Recording permission. Enable it in System Settings → \
        Privacy & Security → Screen & System Audio Recording, then quit and reopen ShotPaste.
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

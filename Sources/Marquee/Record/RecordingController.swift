import AppKit
import SwiftUI

/// Runs a recording from start to finish:
/// pick an area → toolbar (choose mic and desktop audio) → countdown → record → stop.
@MainActor
final class RecordingController {
    static let shared = RecordingController()

    /// Recording started (true) or stopped (false); the menu bar shows a stop button meanwhile.
    var onRecordingChanged: ((Bool) -> Void)?
    /// A finished recording, ready for the Quick Access overlay.
    var onFinished: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    private let recorder = ScreenRecorder()
    private var microphone: MicrophoneCapture?
    private var session: RecordingSession?
    private var target: (screen: NSScreen, rect: CGRect)?
    private var toolbar: NSPanel?
    private var countdownPanel: NSPanel?
    private var countdownTask: Task<Void, Never>?
    private var meterTimer: Timer?
    private var clockTimer: Timer?
    private var discarding = false

    var isRecording: Bool { recorder.isRecording }
    /// True from the moment the toolbar appears until the recording is saved.
    var isBusy: Bool { session != nil || recorder.isRecording }
    var startDate: Date? { recorder.startDate }

    private init() {
        recorder.onUnexpectedStop = { [weak self] in self?.stop() }
    }

    // MARK: - Entry point (shortcut or menu)

    func toggle(selectArea: Bool) {
        if recorder.isRecording {
            stop()
            return
        }
        if let session {
            // Pressing the shortcut again on the toolbar starts recording right away.
            if session.phase == .ready { start() }
            return
        }
        if selectArea {
            AreaSelector.select { [weak self] selection in
                guard let selection else { return }
                self?.prepare(screen: selection.0, rect: selection.1)
            }
        } else if let screen = NSScreen.underMouse {
            prepare(screen: screen, rect: screen.frame)
        }
    }

    // MARK: - Toolbar phase

    private func prepare(screen: NSScreen, rect: CGRect) {
        let isFullScreen = rect == screen.frame
        let sizeLabel = isFullScreen ? "Full screen" : "\(Int(rect.width)) × \(Int(rect.height))"
        let session = RecordingSession(
            micEnabled: Preferences.recordMicrophone,
            micID: Preferences.recordMicrophoneID,
            desktopAudio: Preferences.recordAudio,
            sizeLabel: sizeLabel
        )
        self.session = session
        target = (screen, rect)
        discarding = false

        if !isFullScreen { recorder.showBorder(around: rect) }
        if session.micEnabled { startMicrophone() }
        showToolbar(session: session, screen: screen, rect: rect)
        startMeter()
    }

    func showMicMenu() {
        guard let session else { return }
        let menu = NSMenu()
        let none = NSMenuItem(title: "No Microphone", action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
        none.state = session.micEnabled ? .off : .on
        none.target = MenuTarget.shared
        menu.addItem(none)
        menu.addItem(.separator())

        let devices = MicrophoneCapture.devices()
        let selected = session.micID ?? MicrophoneCapture.defaultDeviceID
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.representedObject = device.id
            item.state = session.micEnabled && device.id == selected ? .on : .off
            item.target = MenuTarget.shared
            menu.addItem(item)
        }
        if devices.isEmpty {
            let empty = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        if session.micProblem != nil {
            menu.addItem(.separator())
            let settings = NSMenuItem(title: "Open Microphone Settings…", action: #selector(MenuTarget.openSettings), keyEquivalent: "")
            settings.target = MenuTarget.shared
            menu.addItem(settings)
        }
        MenuTarget.shared.onPick = { [weak self] id in self?.selectMicrophone(id) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func selectMicrophone(_ id: String?) {
        guard let session else { return }
        if let id {
            session.micID = id
            session.micEnabled = true
            Preferences.recordMicrophoneID = id
            Preferences.recordMicrophone = true
            startMicrophone()
        } else {
            session.micEnabled = false
            session.micProblem = nil
            session.micLevel = 0
            Preferences.recordMicrophone = false
            microphone?.stop()
            microphone = nil
        }
    }

    func toggleDesktopAudio() {
        guard let session else { return }
        session.desktopAudio.toggle()
        Preferences.recordAudio = session.desktopAudio
    }

    private func startMicrophone() {
        guard let session else { return }
        switch MicrophoneCapture.authorization {
        case .authorized:
            break
        case .notDetermined:
            Task {
                if await MicrophoneCapture.requestAccess() {
                    startMicrophone()
                } else {
                    markMicrophoneBlocked()
                }
            }
            return
        default:
            markMicrophoneBlocked()
            return
        }
        let mic = microphone ?? MicrophoneCapture()
        do {
            try mic.start(deviceID: session.micID)
            microphone = mic
            session.micName = mic.deviceName ?? "Microphone"
            session.micEnabled = true
            session.micProblem = nil
        } catch {
            session.micProblem = error.localizedDescription
            session.micEnabled = false
            microphone = nil
        }
    }

    private func markMicrophoneBlocked() {
        guard let session else { return }
        session.micEnabled = false
        session.micProblem = "Marquee isn't allowed to use the microphone. Allow it in System Settings → Privacy & Security → Microphone."
    }

    // MARK: - Countdown and recording

    func start() {
        guard let session, session.phase == .ready else { return }
        let seconds = Preferences.recordCountdownSeconds
        guard seconds > 0 else {
            beginRecording()
            return
        }
        showCountdown(session: session)
        countdownTask = Task { [weak self] in
            // 3, 2, 1 … then "Go" for a beat, then record.
            for n in stride(from: seconds, through: 1, by: -1) {
                session.phase = .countdown(n)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            session.phase = .countdown(0)
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self?.hideCountdown()
            self?.beginRecording()
        }
    }

    private func beginRecording() {
        guard let session, let target else { return }
        session.phase = .starting
        let mic = session.micEnabled ? microphone : nil
        Task {
            do {
                try await recorder.start(
                    screen: target.screen, rect: target.rect,
                    desktopAudio: session.desktopAudio, microphone: mic
                )
                session.phase = .recording
                startClock()
                onRecordingChanged?(true)
            } catch {
                tearDown()
                onError?(error)
            }
        }
    }

    func stop() {
        guard recorder.isRecording else { return }
        session?.phase = .saving
        clockTimer?.invalidate()
        onRecordingChanged?(false)
        let discard = discarding
        Task {
            let url = await recorder.stop()
            tearDown()
            guard let url else {
                Toast.show("Nothing was recorded")
                return
            }
            if discard {
                try? FileManager.default.removeItem(at: url)
                Toast.show("Recording discarded")
            } else {
                onFinished?(url)
            }
        }
    }

    func discard() {
        discarding = true
        stop()
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        hideCountdown()
        tearDown()
    }

    private func tearDown() {
        countdownTask?.cancel()
        countdownTask = nil
        meterTimer?.invalidate()
        meterTimer = nil
        clockTimer?.invalidate()
        clockTimer = nil
        microphone?.stop()
        microphone = nil
        toolbar?.orderOut(nil)
        toolbar = nil
        hideCountdown()
        recorder.hideBorder()
        session = nil
        target = nil
    }

    // MARK: - Timers

    private func startMeter() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let session = self.session else { return }
                session.micLevel = session.micEnabled ? (self.microphone?.level ?? 0) : 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func startClock() {
        clockTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recorder.startDate else { return }
                self.session?.elapsed = Date().timeIntervalSince(start)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    // MARK: - Windows

    private func showToolbar(session: RecordingSession, screen: NSScreen, rect: CGRect) {
        let actions = RecordingToolbar.Actions(
            start: { [weak self] in self?.start() },
            cancel: { [weak self] in self?.cancel() },
            stop: { [weak self] in self?.stop() },
            discard: { [weak self] in self?.discard() },
            showMicMenu: { [weak self] in self?.showMicMenu() },
            toggleDesktopAudio: { [weak self] in self?.toggleDesktopAudio() }
        )
        let size = NSSize(width: 720, height: 64)
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            RecordingToolbar(session: session, actions: actions)
                .frame(width: size.width, height: size.height)
        )

        // Below the area when there's room, otherwise inside its bottom edge.
        let visible = screen.visibleFrame
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 8)
        if rect == screen.frame || origin.y < visible.minY + 8 {
            origin.y = rect == screen.frame ? visible.minY + 28 : rect.minY + 12
        }
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        toolbar = panel
    }

    private func showCountdown(session: RecordingSession) {
        guard let target else { return }
        let size = NSSize(width: 160, height: 160)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CountdownView(session: session).frame(width: size.width, height: size.height))
        panel.setFrameOrigin(NSPoint(x: target.rect.midX - size.width / 2, y: target.rect.midY - size.height / 2))
        panel.orderFrontRegardless()
        countdownPanel = panel
    }

    private func hideCountdown() {
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
    }
}

/// Target for the microphone NSMenu (NSMenuItem needs an Objective-C target).
@MainActor
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    var onPick: ((String?) -> Void)?

    @objc func pick(_ sender: NSMenuItem) {
        onPick?(sender.representedObject as? String)
    }

    @objc func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

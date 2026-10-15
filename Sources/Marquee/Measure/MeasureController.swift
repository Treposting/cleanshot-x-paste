import AppKit

/// Starts and ends measure mode: freezes the display under the mouse, shows the
/// measuring overlay on it, and hands exported measurements to Quick Access.
@MainActor
final class MeasureController {
    static let shared = MeasureController()

    private var window: NSWindow?
    private var isStarting = false

    var isActive: Bool { window != nil || isStarting }

    func toggle() {
        if window != nil {
            close()
        } else {
            start()
        }
    }

    private func start() {
        guard !isStarting, let screen = NSScreen.underMouse else { return }
        if #available(macOS 14.0, *) {
            begin(on: screen)
        } else {
            let alert = NSAlert()
            alert.messageText = "Measure needs macOS 14 Sonoma or later"
            alert.informativeText = "Everything else in Marquee works on macOS 13."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @available(macOS 14.0, *)
    private func begin(on screen: NSScreen) {
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                let image = try await ScreenSnapshot.capture(screen: screen)
                guard let pixels = PixelBuffer(image: image) else { return }
                present(image: image, pixels: pixels, on: screen)
            } catch {
                showPermissionAlert(error)
            }
        }
    }

    private func present(image: CGImage, pixels: PixelBuffer, on screen: NSScreen) {
        let frame = screen.frame
        let window = MeasureWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(frame, display: false)

        // Pixels per point of the snapshot (2 on Retina, other values in scaled modes).
        let scale = CGFloat(image.width) / max(frame.width, 1)
        let view = MeasureView(
            frame: NSRect(origin: .zero, size: frame.size),
            image: image, pixels: pixels, scale: scale,
            tolerance: Preferences.measureTolerance
        )
        view.onClose = { [weak self] in self?.close() }
        view.onExport = { [weak self] image in
            self?.close()
            self?.deliver(image)
        }
        window.contentView = view

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    /// ⌘S: the frozen screen with measurements drawn on it becomes a normal capture.
    private func deliver(_ image: NSImage) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee-measure-\(UUID().uuidString).png")
        guard let data = image.pngData, (try? data.write(to: url, options: .atomic)) != nil else { return }
        let capture = Capture(url: url, image: image)
        if Preferences.copyAfterCapture { capture.copyToPasteboard() }
        QuickAccessManager.shared.show(capture)
    }

    private func showPermissionAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't read the screen"
        alert.informativeText = """
        \(error.localizedDescription)

        Measure needs the Screen Recording permission. Enable Marquee in System Settings → \
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

final class MeasureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

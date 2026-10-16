import AppKit

/// Starts and ends measure mode: freezes every display, shows a measuring overlay on
/// each one, and hands exported measurements to Quick Access. Keys go to the display
/// under the pointer; Esc or the shortcut ends measuring everywhere.
@MainActor
final class MeasureController {
    static let shared = MeasureController()

    private var windows: [NSWindow] = []
    private var isStarting = false

    var isActive: Bool { !windows.isEmpty || isStarting }

    func toggle() {
        if !windows.isEmpty {
            close()
        } else {
            start()
        }
    }

    private func start() {
        guard !isStarting, !NSScreen.screens.isEmpty else { return }
        if #available(macOS 14.0, *) {
            begin(on: NSScreen.screens)
        } else {
            let alert = NSAlert()
            alert.messageText = "Measure needs macOS 14 Sonoma or later"
            alert.informativeText = "Everything else in Marquee works on macOS 13."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @available(macOS 14.0, *)
    private func begin(on screens: [NSScreen]) {
        isStarting = true
        Task {
            defer { isStarting = false }
            // Freeze every display first, then show all overlays together. A display that
            // can't be captured is skipped; the alert only shows when none could be.
            var snapshots: [(NSScreen, CGImage, PixelBuffer)] = []
            var failure: Error?
            for screen in screens {
                do {
                    let image = try await ScreenSnapshot.capture(screen: screen)
                    guard let pixels = PixelBuffer(image: image) else { continue }
                    snapshots.append((screen, image, pixels))
                } catch {
                    failure = failure ?? error
                }
            }
            guard !snapshots.isEmpty else {
                if let failure { showPermissionAlert(failure) }
                return
            }
            for (screen, image, pixels) in snapshots {
                present(image: image, pixels: pixels, on: screen)
            }
            // Keys start on the display under the pointer.
            let pointerScreen = NSScreen.underMouse?.frame
            let active = windows.first { $0.frame == pointerScreen } ?? windows.first
            NSApp.activate(ignoringOtherApps: true)
            active?.makeKeyAndOrderFront(nil)
            active?.makeFirstResponder(active?.contentView)
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
        window.orderFrontRegardless()
        windows.append(window)
    }

    func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
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

        Measure needs the Screen Recording permission. If it's already on in System Settings, \
        use Fix Permissions on the Permissions page, then restart Marquee.
        """
        alert.addButton(withTitle: "Open Permissions")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.shared.showMain(.permissions)
        }
    }
}

final class MeasureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

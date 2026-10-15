import AppKit

/// Highlights the window under the pointer and returns its frame when clicked.
/// Used to record a single window from All-in-One. Esc cancels.
@MainActor
final class WindowPicker {
    private static var active: WindowPicker?

    private let window: PickerWindow
    private let view: PickerView
    private let screen: NSScreen
    private let completion: @MainActor ((NSScreen, CGRect)?) -> Void

    static func pick(completion: @escaping @MainActor ((NSScreen, CGRect)?) -> Void) {
        guard active == nil, let screen = NSScreen.underMouse else { return }
        let picker = WindowPicker(screen: screen, completion: completion)
        active = picker
        picker.show()
    }

    private init(screen: NSScreen, completion: @escaping @MainActor ((NSScreen, CGRect)?) -> Void) {
        self.screen = screen
        self.completion = completion
        window = PickerWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    private func show() {
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)

        view.screenFrame = screen.frame
        view.onFinish = { [weak self] rect in self?.finish(rect) }
        window.contentView = view

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.updateHighlight()
    }

    private func finish(_ globalRect: CGRect?) {
        window.orderOut(nil)
        WindowPicker.active = nil
        guard let globalRect else {
            completion(nil)
            return
        }
        completion((screen, globalRect))
    }

    /// The frontmost normal window under a point, in AppKit global coordinates.
    static func windowFrame(at point: NSPoint, excludingWindowNumber excluded: Int) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowNumber as String] as? Int) != excluded,
                  (entry[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict),
                  cgBounds.width > 40, cgBounds.height > 40
            else { continue }
            // Window-server bounds are top-left based; flip into AppKit coordinates.
            let frame = CGRect(x: cgBounds.minX, y: mainHeight - cgBounds.maxY, width: cgBounds.width, height: cgBounds.height)
            if frame.contains(point) { return frame }
        }
        return nil
    }
}

private final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    var screenFrame: CGRect = .zero
    /// Highlighted window in global coordinates.
    private var highlight: CGRect?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func updateHighlight() {
        let found = WindowPicker.windowFrame(at: NSEvent.mouseLocation, excludingWindowNumber: window?.windowNumber ?? -1)
        if found != highlight {
            highlight = found
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) { updateHighlight() }

    override func mouseDown(with event: NSEvent) {
        updateHighlight()
        guard let highlight else { return }
        // Keep the recording inside this display.
        let clipped = highlight.intersection(screenFrame).integral
        guard clipped.width >= 20, clipped.height >= 20 else { return }
        onFinish?(clipped)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        let dim = NSBezierPath(rect: bounds)
        let yellow = NSColor(calibratedRed: 1, green: 0.81, blue: 0.1, alpha: 1)
        if let highlight {
            let local = highlight.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            dim.append(NSBezierPath(rect: local))
            dim.windingRule = .evenOdd
            dim.fill()
            yellow.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: local).fill()
            yellow.setStroke()
            let border = NSBezierPath(rect: local.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = 3
            border.stroke()
        } else {
            dim.fill()
        }
        let hint = "Click a window to record it  ·  Esc: cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = hint.size(withAttributes: attributes)
        let pill = NSRect(x: bounds.midX - size.width / 2 - 10, y: bounds.maxY - 90, width: size.width + 20, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        hint.draw(at: NSPoint(x: pill.minX + 10, y: pill.minY + 5), withAttributes: attributes)
    }
}

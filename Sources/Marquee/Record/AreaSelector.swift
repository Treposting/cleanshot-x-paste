import AppKit

/// Full-screen crosshair overlay for choosing the area to record.
/// Drag to select, Return to record the whole screen, Esc to cancel.
@MainActor
final class AreaSelector {
    private static var active: AreaSelector?

    private let window: SelectionWindow
    private let screen: NSScreen
    private let completion: @MainActor ((NSScreen, CGRect)?) -> Void

    nonisolated static let recordHint = "Drag to select an area to record  ·  Return: whole screen  ·  Esc: cancel"

    static func select(
        hint: String = recordHint,
        completion: @escaping @MainActor ((NSScreen, CGRect)?) -> Void
    ) {
        guard active == nil, let screen = NSScreen.underMouse else { return }
        let selector = AreaSelector(screen: screen, hint: hint, completion: completion)
        active = selector
        selector.show()
    }

    private let hint: String

    private init(screen: NSScreen, hint: String, completion: @escaping @MainActor ((NSScreen, CGRect)?) -> Void) {
        self.screen = screen
        self.hint = hint
        self.completion = completion
        window = SelectionWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
    }

    private func show() {
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.hint = hint
        view.onFinish = { [weak self] localRect in self?.finish(localRect) }
        window.contentView = view

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.crosshair.push()
    }

    private func finish(_ localRect: NSRect?) {
        NSCursor.pop()
        window.orderOut(nil)
        AreaSelector.active = nil
        guard let localRect else {
            completion(nil)
            return
        }
        let global = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        completion((screen, global))
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((NSRect?) -> Void)?
    var hint = AreaSelector.recordHint
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything except the selection.
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()

        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()

            let label = "\(Int(selection.width)) × \(Int(selection.height))"
            drawPill(label, at: NSPoint(x: selection.minX, y: selection.minY - 26))
        } else {
            let size = (hint as NSString).size(withAttributes: Self.attributes)
            drawPill(hint, at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY))
        }
    }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func drawPill(_ text: String, at origin: NSPoint) {
        let size = (text as NSString).size(withAttributes: Self.attributes)
        let y = max(4, origin.y)
        let rect = NSRect(x: origin.x, y: y, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 8, y: rect.minY + 4), withAttributes: Self.attributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        if let selection, selection.width >= 20, selection.height >= 20 {
            onFinish?(selection.integral)
        } else {
            start = nil
            current = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish?(nil)        // Esc
        case 36, 76: onFinish?(bounds) // Return / Enter
        default: super.keyDown(with: event)
        }
    }
}

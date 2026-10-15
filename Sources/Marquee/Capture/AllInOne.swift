import AppKit
import SwiftUI

/// One shortcut for everything. The toolbar shows right away; until an area is selected its
/// actions apply to the whole screen. Drag to select an area, then drag again anywhere to
/// replace it, drag inside it to move it, or drag a handle to resize it.
@MainActor
final class AllInOneController {
    static let shared = AllInOneController()

    /// What a screenshot or recording covers. `.area` is the current selection, or the whole
    /// screen when nothing is selected.
    enum Target: Equatable {
        case area, fullScreen, window
    }

    enum Choice: Equatable {
        case screenshot(Target), record(Target), copy, copyText, pin, pickColor, settings
    }

    /// Set by the app delegate: runs the chosen action on the selected area. For a
    /// `.window` target the rectangle is unused: the app delegate lets the user pick a window.
    var onChoice: ((Choice, NSScreen, CGRect) -> Void)?

    private var overlay: NSWindow?
    private var overlayView: AllInOneOverlayView?
    private var toolbar: NSPanel?
    private var screen: NSScreen?
    private let state = AllInOneState()

    var isActive: Bool { overlay != nil }

    func start() {
        if isActive {
            dismiss()
            return
        }
        guard let screen = NSScreen.underMouse else { return }
        self.screen = screen

        let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)

        let view = AllInOneOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onSelectionChange = { [weak self] _ in self?.selectionChanged() }
        view.onDragging = { [weak self] dragging in
            // Hidden while dragging; moved and updated once the drag ends.
            if !dragging { self?.selectionChanged() }
            self?.toolbar?.alphaValue = dragging ? 0 : 1
        }
        view.onChoice = { [weak self] choice in self?.choose(choice) }
        view.onCancel = { [weak self] in self?.dismiss() }
        window.contentView = view

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        overlay = window
        overlayView = view

        showToolbar(on: screen)
        selectionChanged()
    }

    private func showToolbar(on screen: NSScreen) {
        let hosting = FirstMouseHostingView(rootView:
            AllInOneToolbar(state: state) { [weak self] choice in
                self?.choose(choice)
            } cancel: { [weak self] in
                self?.dismiss()
            }
        )
        // A fixed-size panel: the hosting view must not resize its window while the
        // selection (and the size label) changes.
        // Measure first, then stop the hosting view from resizing the panel afterwards
        // (with no sizing options it reports a zero fitting size).
        var size = hosting.fittingSize
        if size.width < 100 || size.height < 40 { size = NSSize(width: 860, height: 76) }
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        toolbar = panel
    }

    /// The selection in global coordinates, or the whole screen when nothing is selected.
    private var targetRect: CGRect? {
        guard let screen else { return nil }
        guard let local = overlayView?.selection else { return screen.frame }
        return local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    private func selectionChanged() {
        guard let screen, let toolbar else { return }
        let selection = overlayView?.selection
        state.sizeLabel = selection.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Full screen"
        state.hasSelection = selection != nil

        let size = toolbar.frame.size
        let visible = screen.visibleFrame
        var origin: NSPoint
        if let rect = targetRect, selection != nil {
            origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 10)
            if origin.y < visible.minY + 8 {
                // No room below: sit just inside the bottom of the selection, or above it.
                origin.y = rect.maxY + 8 + size.height < visible.maxY ? rect.maxY + 8 : max(visible.minY + 8, rect.minY + 12)
            }
        } else {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 40)
        }
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        toolbar.setFrameOrigin(origin)
    }

    private func choose(_ choice: Choice) {
        guard let screen, var rect = targetRect else { return }
        if choice == .screenshot(.fullScreen) || choice == .record(.fullScreen) {
            rect = screen.frame
        }
        dismiss()
        if choice == .settings {
            onChoice?(choice, screen, rect)
            return
        }
        // Let the overlay and toolbar leave the screen before capturing.
        runAfter(0.15) { [weak self] in
            self?.onChoice?(choice, screen, rect)
        }
    }

    func dismiss() {
        guard overlay != nil else { return }
        toolbar?.orderOut(nil)
        toolbar = nil
        overlay?.orderOut(nil)
        overlay = nil
        overlayView = nil
        screen = nil
    }
}

@MainActor
private final class AllInOneState: ObservableObject {
    @Published var sizeLabel = "Full screen"
    @Published var hasSelection = false
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Lets toolbar buttons work on the first click while the overlay keeps keyboard focus.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Selection overlay

private final class AllInOneOverlayView: NSView {
    var onSelectionChange: ((NSRect?) -> Void)?
    var onDragging: ((Bool) -> Void)?
    var onChoice: ((AllInOneController.Choice) -> Void)?
    var onCancel: (() -> Void)?

    private(set) var selection: NSRect? {
        didSet {
            needsDisplay = true
            // While dragging, cursor rects and the toolbar are updated once, when the drag ends.
            guard drag == nil else { return }
            window?.invalidateCursorRects(for: self)
            onSelectionChange?(selection)
        }
    }

    private enum Handle: CaseIterable {
        case bottomLeft, bottom, bottomRight, left, right, topLeft, top, topRight
    }

    private enum Drag {
        case new(start: NSPoint, previous: NSRect?)
        case move(start: NSPoint, original: NSRect)
        case resize(Handle, original: NSRect)
    }

    private var drag: Drag?
    private static let minimumSize: CGFloat = 8
    private static let yellow = NSColor(calibratedRed: 1, green: 0.81, blue: 0.1, alpha: 1)

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private func point(of handle: Handle, in rect: NSRect) -> NSPoint {
        switch handle {
        case .bottomLeft: return NSPoint(x: rect.minX, y: rect.minY)
        case .bottom: return NSPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return NSPoint(x: rect.maxX, y: rect.minY)
        case .left: return NSPoint(x: rect.minX, y: rect.midY)
        case .right: return NSPoint(x: rect.maxX, y: rect.midY)
        case .topLeft: return NSPoint(x: rect.minX, y: rect.maxY)
        case .top: return NSPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return NSPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func handle(at p: NSPoint) -> Handle? {
        guard let selection else { return nil }
        return Handle.allCases.first { handle in
            let c = point(of: handle, in: selection)
            return abs(c.x - p.x) <= 8 && abs(c.y - p.y) <= 8
        }
    }

    private func resized(_ r: NSRect, _ handle: Handle, to p: NSPoint) -> NSRect {
        var left = r.minX, right = r.maxX, bottom = r.minY, top = r.maxY
        switch handle {
        case .bottomLeft: left = p.x; bottom = p.y
        case .bottom: bottom = p.y
        case .bottomRight: right = p.x; bottom = p.y
        case .left: left = p.x
        case .right: right = p.x
        case .topLeft: left = p.x; top = p.y
        case .top: top = p.y
        case .topRight: right = p.x; top = p.y
        }
        return NSRect(x: min(left, right), y: min(bottom, top), width: abs(right - left), height: abs(top - bottom))
    }

    private func clamped(_ r: NSRect) -> NSRect {
        var r = r
        r.origin.x = min(max(bounds.minX, r.origin.x), bounds.maxX - r.width)
        r.origin.y = min(max(bounds.minY, r.origin.y), bounds.maxY - r.height)
        return r
    }

    // MARK: Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard drag == nil, let selection, selection.width >= 1, selection.height >= 1 else { return }
        // insetBy returns CGRect.null for small rects, which must never reach AppKit.
        if selection.width > 24, selection.height > 24 {
            addCursorRect(selection.insetBy(dx: 8, dy: 8), cursor: .openHand)
        }
        for handle in Handle.allCases {
            let c = point(of: handle, in: selection)
            let cursor: NSCursor
            switch handle {
            case .left, .right: cursor = .resizeLeftRight
            case .top, .bottom: cursor = .resizeUpDown
            default: cursor = .crosshair
            }
            addCursorRect(NSRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16), cursor: cursor)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(selection == nil ? 0.18 : 0.38).setFill()
        dim.fill()

        guard let selection else {
            let hint = "Drag to select an area  ·  F: full screen  ·  W: window  ·  ⌘C: copy  ·  Esc: cancel"
            let size = (hint as NSString).size(withAttributes: Self.attributes)
            drawPill(hint, at: NSPoint(x: bounds.midX - size.width / 2 - 8, y: bounds.midY))
            return
        }

        Self.yellow.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.75, dy: -0.75))
        border.lineWidth = 1.5
        border.stroke()

        if case .new? = drag {} else {
            for handle in Handle.allCases {
                let c = point(of: handle, in: selection)
                let dot = NSBezierPath(ovalIn: NSRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9))
                NSColor.white.setFill()
                dot.fill()
                Self.yellow.setStroke()
                dot.lineWidth = 1.5
                dot.stroke()
            }
        }

        let label = "\(Int(selection.width)) × \(Int(selection.height))"
        let labelY = selection.maxY + 8 + 24 < bounds.maxY ? selection.maxY + 8 : selection.maxY - 30
        drawPill(label, at: NSPoint(x: selection.minX, y: labelY))
    }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private func drawPill(_ text: String, at origin: NSPoint) {
        let size = (text as NSString).size(withAttributes: Self.attributes)
        let rect = NSRect(x: max(4, origin.x), y: max(4, origin.y), width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 8, y: rect.minY + 4), withAttributes: Self.attributes)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let selection, let handle = handle(at: p) {
            drag = .resize(handle, original: selection)
        } else if let selection, selection.contains(p) {
            drag = .move(start: p, original: selection)
            NSCursor.closedHand.set()
        } else {
            drag = .new(start: p, previous: selection)
        }
        onDragging?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let clampedPoint = NSPoint(x: min(max(bounds.minX, p.x), bounds.maxX), y: min(max(bounds.minY, p.y), bounds.maxY))
        switch drag {
        case .new(let start, _):
            selection = NSRect(x: min(start.x, clampedPoint.x), y: min(start.y, clampedPoint.y),
                               width: abs(start.x - clampedPoint.x), height: abs(start.y - clampedPoint.y))
        case .move(let start, let original):
            selection = clamped(original.offsetBy(dx: p.x - start.x, dy: p.y - start.y))
        case .resize(let handle, let original):
            selection = resized(original, handle, to: clampedPoint)
        case nil:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let ending = drag else { return }
        // A click or a tiny drag keeps the previous selection instead of losing it.
        if let current = selection, current.width < Self.minimumSize || current.height < Self.minimumSize {
            switch ending {
            case .new(_, let previous): selection = previous
            case .move(_, let original), .resize(_, let original): selection = original
            }
        } else if let current = selection {
            selection = current.integral
        }
        drag = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onDragging?(false)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()                                   // Esc
        case 36, 76: onChoice?(.screenshot(.area))              // Return, Enter
        case 51, 117:                                           // Delete: back to the whole screen
            selection = nil
        case 123, 124, 125, 126:                                // Arrows nudge the selection
            guard let selection else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let dx: CGFloat = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy: CGFloat = event.keyCode == 125 ? -step : event.keyCode == 126 ? step : 0
            self.selection = clamped(selection.offsetBy(dx: dx, dy: dy))
        default:
            let key = event.charactersIgnoringModifiers?.lowercased()
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌘C or ⌃C copies the selected area (or the whole screen) to the clipboard.
            if key == "c", flags.contains(.command) || flags.contains(.control) {
                onChoice?(.copy)
                return
            }
            let shift = flags.contains(.shift)
            switch key {
            case "f": onChoice?(shift ? .record(.fullScreen) : .screenshot(.fullScreen))
            case "w": onChoice?(shift ? .record(.window) : .screenshot(.window))
            case "r": onChoice?(.record(.area))
            case "t": onChoice?(.copyText)
            case "p": onChoice?(.pin)
            case "c": onChoice?(.pickColor)
            case ",": onChoice?(.settings)
            default: super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Toolbar

/// A Liquid Glass capsule in the style of the macOS 26/27 screenshot bar. It follows the
/// system appearance; Screenshot is the default action (Return).
@MainActor
private struct AllInOneToolbar: View {
    @ObservedObject var state: AllInOneState
    let choose: (AllInOneController.Choice) -> Void
    let cancel: () -> Void

    var body: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 4) {
                SplitAction(
                    main: ToolbarAction(symbol: "camera.viewfinder", title: "Screenshot", key: "↩", prominent: true) { choose(.screenshot(.area)) },
                    areaTitle: state.hasSelection ? "Selected Area" : "Whole Screen",
                    keys: ("↩", "F", "W"),
                    pick: { choose(.screenshot($0)) }
                )
                SplitAction(
                    main: ToolbarAction(symbol: "record.circle", title: "Record", key: "R", symbolColor: .red) { choose(.record(.area)) },
                    areaTitle: state.hasSelection ? "Selected Area" : "Whole Screen",
                    keys: ("R", "⇧F", "⇧W"),
                    pick: { choose(.record($0)) }
                )
                ToolbarAction(symbol: "doc.on.doc", title: "Copy", key: "⌘C") { choose(.copy) }
                ToolbarAction(symbol: "text.viewfinder", title: "Copy Text", key: "T") { choose(.copyText) }
                ToolbarAction(symbol: "pin", title: "Pin", key: "P") { choose(.pin) }
                ToolbarAction(symbol: "eyedropper", title: "Color", key: "C") { choose(.pickColor) }

                Divider()
                    .frame(height: 22)
                    .padding(.horizontal, 6)

                HStack(spacing: 5) {
                    Image(systemName: state.hasSelection ? "rectangle.dashed" : "display")
                        .font(.system(size: 11, weight: .medium))
                    Text(state.sizeLabel)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .frame(width: 104)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(state.hasSelection ? "Selection \(state.sizeLabel)" : "Full screen")

                CircleButton(symbol: "gearshape", help: "Marquee Settings (,)") { choose(.settings) }
                CircleButton(symbol: "xmark", help: "Cancel (Esc)", action: cancel)
            }
            .padding(6)
            .glassSurface(Capsule())
        }
        .padding(14) // room for the glass edge and shadow
        .fixedSize()
    }
}

/// A toolbar action with a ▾ menu for choosing what it covers.
private struct SplitAction: View {
    let main: ToolbarAction
    let areaTitle: String
    let keys: (area: String, fullScreen: String, window: String)
    let pick: (AllInOneController.Target) -> Void

    var body: some View {
        HStack(spacing: 0) {
            main
            Menu {
                Button { pick(.area) } label: { Label("\(areaTitle)  (\(keys.area))", systemImage: "rectangle.dashed") }
                Button { pick(.fullScreen) } label: { Label("Full Screen  (\(keys.fullScreen))", systemImage: "display") }
                Button { pick(.window) } label: { Label("Window…  (\(keys.window))", systemImage: "macwindow") }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 38)
            .contentShape(Rectangle())
            .help("Selected area, full screen or a window")
            .accessibilityLabel("\(main.title) options")
        }
    }
}

private struct ToolbarAction: View {
    let symbol: String
    let title: String
    let key: String
    var prominent = false
    var symbolColor: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    private static let yellow = Color(red: 1, green: 0.81, blue: 0.1)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(prominent ? Color.black.opacity(0.85) : (symbolColor ?? .primary))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(key)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 17)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(prominent ? Color.black.opacity(0.12) : Color.primary.opacity(0.08))
                    )
                    .opacity(0.8)
            }
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : .primary)
            .padding(.leading, 12)
            .padding(.trailing, 9)
            .frame(height: 38)
            .background(
                Capsule().fill(prominent
                    ? Self.yellow.opacity(hovering ? 1 : 0.92)
                    : Color.primary.opacity(hovering ? 0.09 : 0))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("\(title) (\(key))")
        .accessibilityLabel(title)
    }
}

private struct CircleButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

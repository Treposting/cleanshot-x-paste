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
    enum Target: String, Equatable, CaseIterable {
        case area, fullScreen, window
        /// A long screenshot of the selection (or the screen) while it scrolls. Screenshots only.
        case scrolling

        static func choices(for mode: Mode) -> [Target] {
            mode == .screenshot ? allCases : [.area, .fullScreen, .window]
        }
    }

    /// The two capture modes; each remembers the target last used with it.
    enum Mode: Equatable {
        case screenshot, record
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

    /// The target last chosen for a mode, kept across launches.
    static func lastTarget(_ mode: Mode) -> Target {
        Target(rawValue: UserDefaults.standard.string(forKey: key(for: mode)) ?? "") ?? .area
    }

    private static func key(for mode: Mode) -> String {
        mode == .screenshot ? Preferences.Key.allInOneScreenshotTarget.rawValue : Preferences.Key.allInOneRecordTarget.rawValue
    }

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
        // Esc first leaves the target picker, then closes All-in-One.
        view.onCancel = { [weak self] in
            guard let self else { return }
            if self.state.choosing != nil {
                self.state.choosing = nil
            } else {
                self.dismiss()
            }
        }
        view.target = { [weak self] mode in self?.state.effectiveTarget(mode) ?? .area }
        state.screenshotTarget = Self.lastTarget(.screenshot)
        state.recordTarget = Self.lastTarget(.record)
        state.choosing = nil
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
        remember(choice)
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

    /// Saves the target of a screenshot or recording as that mode's default. A selection
    /// always wins for the moment, so acting on one doesn't replace the saved default.
    private func remember(_ choice: Choice) {
        let mode: Mode, target: Target
        switch choice {
        case .screenshot(let t): (mode, target) = (.screenshot, t)
        case .record(let t): (mode, target) = (.record, t)
        default: return
        }
        guard !(target == .area && state.hasSelection) else { return }
        UserDefaults.standard.set(target.rawValue, forKey: Self.key(for: mode))
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
    @Published var hasSelection = false
    @Published var screenshotTarget: AllInOneController.Target = .area
    @Published var recordTarget: AllInOneController.Target = .area
    /// The mode whose target picker is showing, if any.
    @Published var choosing: AllInOneController.Mode?

    /// What a mode's main button does now: a selection wins, otherwise the remembered target.
    func effectiveTarget(_ mode: AllInOneController.Mode) -> AllInOneController.Target {
        hasSelection ? .area : (mode == .screenshot ? screenshotTarget : recordTarget)
    }
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
    /// The target the main Screenshot and Record actions use (Return and R).
    var target: ((AllInOneController.Mode) -> AllInOneController.Target)?

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
        case 36, 76: onChoice?(.screenshot(target?(.screenshot) ?? .area)) // Return, Enter
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
            case "r": onChoice?(.record(target?(.record) ?? .area))
            case "s": onChoice?(.screenshot(.scrolling))
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

/// A compact Liquid Glass bar. Screenshot and Record each run with the target you used last
/// (a selection always wins); the small icon at the end of each shows that target, and clicking
/// it swaps the bar for a target picker with a back button. Then Copy, Copy Text, Pin and Color.
@MainActor
private struct AllInOneToolbar: View {
    @ObservedObject var state: AllInOneState
    let choose: (AllInOneController.Choice) -> Void
    let cancel: () -> Void

    fileprivate static let yellow = Color(red: 1, green: 0.81, blue: 0.1)

    var body: some View {
        GlassGroup(spacing: 10) {
            // Both layers always take part in layout, so the panel (sized once) fits either.
            ZStack(alignment: .leading) {
                main
                    .opacity(state.choosing == nil ? 1 : 0)
                    .allowsHitTesting(state.choosing == nil)
                    .accessibilityHidden(state.choosing != nil)
                TargetPicker(mode: state.choosing ?? .screenshot, state: state, choose: choose)
                    .opacity(state.choosing == nil ? 0 : 1)
                    .offset(x: state.choosing == nil ? 16 : 0)
                    .allowsHitTesting(state.choosing != nil)
                    .accessibilityHidden(state.choosing == nil)
            }
            .animation(.easeOut(duration: 0.18), value: state.choosing)
            .padding(5)
            .glassSurface(Capsule())
        }
        .padding(14) // room for the glass edge and shadow
        .fixedSize()
    }

    private var main: some View {
        HStack(spacing: 6) {
            ModeButton(mode: .screenshot, state: state, choose: choose)
            ModeButton(mode: .record, state: state, choose: choose)
            HStack(spacing: 2) {
                IconAction(symbol: "doc.on.doc", title: "Copy", key: "⌘C") { choose(.copy) }
                IconAction(symbol: "text.viewfinder", title: "Copy text", key: "T") { choose(.copyText) }
                IconAction(symbol: "pin", title: "Pin", key: "P") { choose(.pin) }
                IconAction(symbol: "eyedropper", title: "Pick color", key: "C") { choose(.pickColor) }
            }
            CircleButton(symbol: "gearshape", help: "Marquee Settings (,)") { choose(.settings) }
            CircleButton(symbol: "xmark", help: "Cancel (Esc)", action: cancel)
        }
    }
}

/// How each target is shown and named.
private extension AllInOneController.Target {
    func symbol(hasSelection: Bool) -> String {
        switch self {
        case .area: return hasSelection ? "rectangle.dashed" : "display"
        case .fullScreen: return "display"
        case .window: return "macwindow"
        case .scrolling: return "scroll"
        }
    }

    var pickerSymbol: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .fullScreen: return "display"
        case .window: return "macwindow"
        case .scrolling: return "scroll"
        }
    }

    var title: String {
        switch self {
        case .area: return "Area"
        case .fullScreen: return "Full Screen"
        case .window: return "Window"
        case .scrolling: return "Scrolling"
        }
    }

    func summary(hasSelection: Bool) -> String {
        switch self {
        case .area: return hasSelection ? "the selection" : "the whole screen (or drag to select an area)"
        case .fullScreen: return "the full screen"
        case .window: return "a window you click"
        case .scrolling: return hasSelection ? "the selection as you scroll it" : "the screen as you scroll"
        }
    }
}

private extension AllInOneController.Mode {
    var title: String { self == .screenshot ? "Screenshot" : "Record" }
    var symbol: String { self == .screenshot ? "camera.fill" : "record.circle.fill" }
    var key: String { self == .screenshot ? "↩" : "R" }

    func choice(_ target: AllInOneController.Target) -> AllInOneController.Choice {
        self == .screenshot ? .screenshot(target) : .record(target)
    }
}

/// Screenshot or Record: the main part runs it with the current target; the small target icon
/// at the end opens the target picker.
private struct ModeButton: View {
    let mode: AllInOneController.Mode
    @ObservedObject var state: AllInOneState
    let choose: (AllInOneController.Choice) -> Void
    @State private var hoverMain = false
    @State private var hoverTarget = false

    private var isShot: Bool { mode == .screenshot }
    private var fill: Color { isShot ? AllInOneToolbar.yellow : Color.red.opacity(0.14) }
    private var ink: Color { isShot ? Color.black.opacity(0.85) : .red }

    var body: some View {
        let target = state.effectiveTarget(mode)
        HStack(spacing: 0) {
            Button {
                choose(mode.choice(target))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: mode.symbol).font(.system(size: 13, weight: .semibold))
                    Text(mode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .fixedSize()
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(height: 34)
                .background(Color.primary.opacity(hoverMain ? 0.08 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverMain = $0 }
            .help("\(mode.title) \(target.summary(hasSelection: state.hasSelection)) (\(mode.key))")
            .accessibilityLabel("\(mode.title) \(target.summary(hasSelection: state.hasSelection))")

            Rectangle().fill(ink.opacity(0.25)).frame(width: 1, height: 18)

            Button {
                state.choosing = mode
            } label: {
                Image(systemName: target.symbol(hasSelection: state.hasSelection))
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 30, height: 34)
                    .background(Color.primary.opacity(hoverTarget ? 0.1 : 0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverTarget = $0 }
            .help("Change what \(mode.title) covers")
            .accessibilityLabel("Change what \(mode.title) covers")
        }
        .foregroundStyle(ink)
        .background(fill, in: Capsule())
        .clipShape(Capsule())
        .animation(.easeOut(duration: 0.12), value: hoverMain)
        .animation(.easeOut(duration: 0.12), value: hoverTarget)
    }
}

/// Shown in place of the main bar: back, the mode, and Area / Full Screen / Window. Picking one
/// runs it and makes it the default.
private struct TargetPicker: View {
    let mode: AllInOneController.Mode
    @ObservedObject var state: AllInOneState
    let choose: (AllInOneController.Choice) -> Void

    private var current: AllInOneController.Target {
        mode == .screenshot ? state.screenshotTarget : state.recordTarget
    }

    var body: some View {
        HStack(spacing: 6) {
            CircleButton(symbol: "chevron.left", help: "Back (Esc)") { state.choosing = nil }
            HStack(spacing: 5) {
                Image(systemName: mode.symbol)
                    .foregroundStyle(mode == .screenshot ? AllInOneToolbar.yellow : .red)
                Text(mode.title).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
            ForEach(AllInOneController.Target.choices(for: mode), id: \.self) { target in
                TargetChip(target: target, selected: target == current,
                           help: "\(mode.title) \(target.summary(hasSelection: state.hasSelection))") {
                    choose(mode.choice(target))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TargetChip: View {
    let target: AllInOneController.Target
    let selected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: target.pickerSymbol).font(.system(size: 12, weight: .medium))
                Text(target.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.22)
                                       : Color.primary.opacity(hovering ? 0.1 : 0.05)))
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(target.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One icon button; its tooltip gives the name and key.
private struct IconAction: View {
    let symbol: String
    let title: String
    let key: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("\(title) (\(key))")
        .accessibilityLabel(title)
        .accessibilityHint("Shortcut \(key)")
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

import AppKit
import QuartzCore

/// Full-screen measuring surface drawn over a frozen snapshot of one display.
///
/// - Move the pointer: distance lines to the nearest edges, with sizes.
/// - Drag: snap to the element inside the rectangle.
/// - H / V: add a horizontal or vertical guide at the pointer. Drag a guide to move it,
///   arrow keys nudge the selected one (⇧ for 10 pt), Tab selects the next, ⌫ removes it.
/// - Space: keep the current measurement on screen. ⌫ clears kept ones when no guide is selected.
/// - ⇧ (hold): show pixels instead of points.
/// - ⌘C: copy the last measurement. ⌘S: capture the screen with measurements.
/// - Esc: leave measure mode.
@MainActor
final class MeasureView: NSView {
    var onClose: (() -> Void)?
    var onExport: ((NSImage) -> Void)?

    private let image: CGImage
    private let pixels: PixelBuffer
    private let scale: CGFloat
    private let tolerance: Int

    private let keptLayer = CALayer()
    private let guidesLayer = CALayer()
    private let liveLayer = CALayer()
    private var liveItems: [CALayer] = []
    private var hintLayer: CALayer?

    private var guides: GuideSet
    private var draggingGuideID: Int?

    private var dragStart: NSPoint?
    private var lastPointer: NSPoint?
    private var lastSnap: PixelRect?
    private var lastText: String?
    private var showPixels = false

    private static let tape = NSColor(calibratedRed: 1, green: 0.812, blue: 0.102, alpha: 1)
    private static let ink = NSColor(calibratedRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
    private static let guideColor = NSColor(calibratedRed: 1, green: 0.271, blue: 0.533, alpha: 1)

    /// How close, in points, the pointer has to be to grab a guide or snap one to an edge.
    private static let guideReach: CGFloat = 4

    init(frame: NSRect, image: CGImage, pixels: PixelBuffer, scale: CGFloat, tolerance: Int) {
        self.image = image
        self.pixels = pixels
        self.scale = max(scale, 1)
        self.tolerance = tolerance
        self.guides = GuideSet(width: pixels.width, height: pixels.height)
        super.init(frame: frame)

        // Layer-hosting view: we own the layer tree. Origin is bottom-left, like the view.
        let root = CALayer()
        root.contents = image
        root.contentsGravity = .resize
        root.contentsScale = self.scale
        layer = root
        wantsLayer = true

        for sub in [keptLayer, guidesLayer, liveLayer] {
            sub.frame = bounds
            root.addSublayer(sub)
        }
        showHint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self, userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: - Mouse

    /// With a measure window on every display, keys go to the display the pointer is on.
    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil, draggingGuideID == nil, lastSnap == nil else { return }
        setLive([])
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragStart == nil, draggingGuideID == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
        showDistances(at: point)
        if !guides.isEmpty { drawGuides() }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let (px, py) = pixel(at: point)
        if let guide = guides.hit(x: px, y: py, within: Int((Self.guideReach * scale).rounded())) {
            guides.select(guide.id)
            draggingGuideID = guide.id
            setLive([])
            guidesChanged()
            return
        }
        if guides.selectedID != nil {
            guides.select(nil)
            drawGuides()
        }
        dragStart = point
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = draggingGuideID, let guide = guides.guides.first(where: { $0.id == id }) {
            lastPointer = point
            guides.move(id, to: snappedGuidePosition(guide.axis, at: point))
            guidesChanged()
            return
        }
        guard let start = dragStart else { return }
        let rect = Self.rect(start, point)
        let box = shape(CGPath(rect: rect, transform: nil), dashed: true, fill: false)
        let size = label("\(format(Int((rect.width * scale).rounded()))) × \(format(Int((rect.height * scale).rounded())))",
                         center: NSPoint(x: rect.midX, y: rect.minY - 14))
        setLive([box, size])
    }

    override func mouseUp(with event: NSEvent) {
        if draggingGuideID != nil {
            draggingGuideID = nil
            return
        }
        guard let start = dragStart else { return }
        dragStart = nil
        let end = convert(event.locationInWindow, from: nil)
        let rect = Self.rect(start, end)
        guard rect.width >= 4, rect.height >= 4 else {
            showDistances(at: end)
            return
        }
        let dragged = PixelRect(
            x: Int((rect.minX * scale).rounded(.down)),
            y: Int(((bounds.height - rect.maxY) * scale).rounded(.down)),
            width: Int((rect.width * scale).rounded(.up)),
            height: Int((rect.height * scale).rounded(.up))
        )
        showSnap(EdgeFinder.snap(in: pixels, rect: dragged, tolerance: tolerance))
    }

    private func updateCursor(at point: NSPoint) {
        let (px, py) = pixel(at: point)
        switch guides.hit(x: px, y: py, within: Int((Self.guideReach * scale).rounded()))?.axis {
        case .vertical: NSCursor.resizeLeftRight.set()
        case .horizontal: NSCursor.resizeUpDown.set()
        case nil: NSCursor.crosshair.set()
        }
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // Esc
            onClose?()
        case 49: // Space
            keepCurrent()
        case 51, 117: // ⌫ ⌦
            if guides.removeSelected() {
                drawGuides()
            } else {
                keptLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            }
        case 48: // Tab
            guides.selectNext()
            guidesChanged()
        case 123, 124, 125, 126: // ← → ↓ ↑
            nudge(keyCode: event.keyCode, points: shift ? 10 : 1)
        default:
            let key = event.charactersIgnoringModifiers?.lowercased()
            if command && key == "c" {
                copyLast()
            } else if command && key == "s" {
                export()
            } else if !command && key == "h" {
                addGuide(.horizontal)
            } else if !command && key == "v" {
                addGuide(.vertical)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let pixelsHeld = event.modifierFlags.contains(.shift)
        guard pixelsHeld != showPixels else { return }
        showPixels = pixelsHeld
        if let lastSnap {
            showSnap(lastSnap)
        } else if let lastPointer {
            showDistances(at: lastPointer)
        }
        drawGuides()
    }

    // MARK: - Guides

    private func addGuide(_ axis: Guide.Axis) {
        hideHint()
        let point = lastPointer ?? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
            ?? NSPoint(x: bounds.midX, y: bounds.midY)
        guides.add(axis, at: snappedGuidePosition(axis, at: point))
        guidesChanged()
    }

    /// Arrow keys move the selected guide along its own axis: ← → for vertical guides,
    /// ↑ ↓ for horizontal ones.
    private func nudge(keyCode: UInt16, points: Int) {
        guard let selected = guides.selected else { return }
        let step = max(1, Int((CGFloat(points) * scale).rounded()))
        let delta: Int
        switch (selected.axis, keyCode) {
        case (.vertical, 123), (.horizontal, 126): delta = -step
        case (.vertical, 124), (.horizontal, 125): delta = step
        default: return
        }
        guides.nudgeSelected(by: delta)
        guidesChanged()
    }

    /// The guide position (a pixel boundary) under `point`, moved onto a nearby edge.
    private func snappedGuidePosition(_ axis: Guide.Axis, at point: NSPoint) -> Int {
        let (px, py) = pixel(at: point)
        let position = axis == .vertical
            ? Int((point.x * scale).rounded())
            : Int(((bounds.height - point.y) * scale).rounded())
        return EdgeFinder.snapGuide(axis, position: position, pointerX: px, pointerY: py, in: pixels,
                                    tolerance: tolerance, within: Int((Self.guideReach * scale).rounded()))
    }

    private func positionText(_ guide: Guide) -> String {
        "\(guide.axis == .vertical ? "x" : "y") \(format(guide.position))"
    }

    /// Redraws guides after a guide action; ⌘C then copies the selected guide's position.
    private func guidesChanged() {
        if let selected = guides.selected { lastText = positionText(selected) }
        drawGuides()
    }

    /// Guide lines, the selected guide's position, and the distance between neighbouring guides.
    /// Gap labels sit near the pointer so they're readable wherever you're looking.
    private func drawGuides() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guidesLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let pointer = lastPointer ?? NSPoint(x: bounds.midX, y: bounds.midY)

        for guide in guides.guides {
            let selected = guide.id == guides.selectedID
            let path = CGMutablePath()
            if guide.axis == .vertical {
                let x = viewX(guide.position)
                path.move(to: NSPoint(x: x, y: 0))
                path.addLine(to: NSPoint(x: x, y: bounds.height))
            } else {
                let y = viewY(guide.position)
                path.move(to: NSPoint(x: 0, y: y))
                path.addLine(to: NSPoint(x: bounds.width, y: y))
            }
            let line = shape(path, color: Self.guideColor)
            line.lineWidth = selected ? 2 : 1
            guidesLayer.addSublayer(line)

            if selected {
                let text = positionText(guide)
                let center = guide.axis == .vertical
                    ? NSPoint(x: viewX(guide.position) + 6, y: pointer.y + 34)
                    : NSPoint(x: pointer.x + 34, y: viewY(guide.position) + 12)
                guidesLayer.addSublayer(label(text, center: center, anchorLeft: true,
                                              background: Self.guideColor, foreground: .white))
            }
        }

        for gap in guides.gaps(.vertical) {
            let y = pointer.y - 22
            let a = NSPoint(x: viewX(gap.start), y: y), b = NSPoint(x: viewX(gap.end), y: y)
            guidesLayer.addSublayer(shape(Self.measureLine(from: a, to: b), color: Self.guideColor))
            guidesLayer.addSublayer(label(format(gap.length), center: NSPoint(x: (a.x + b.x) / 2, y: y - 12),
                                          background: Self.guideColor, foreground: .white))
        }
        for gap in guides.gaps(.horizontal) {
            let x = pointer.x + 22
            let a = NSPoint(x: x, y: viewY(gap.start)), b = NSPoint(x: x, y: viewY(gap.end))
            guidesLayer.addSublayer(shape(Self.measureLine(from: a, to: b), color: Self.guideColor))
            guidesLayer.addSublayer(label(format(gap.length), center: NSPoint(x: x + 8, y: (a.y + b.y) / 2),
                                          anchorLeft: true, background: Self.guideColor, foreground: .white))
        }
        CATransaction.commit()
    }

    // MARK: - Measurements

    private func showDistances(at point: NSPoint) {
        hideHint()
        lastPointer = point
        lastSnap = nil
        let (px, py) = pixel(at: point)
        let d = EdgeFinder.distances(in: pixels, x: px, y: py, tolerance: tolerance)

        let x0 = viewX(px - d.left), x1 = viewX(px + d.right + 1)
        let top = viewY(py - d.up), bottom = viewY(py + d.down + 1)
        let y = viewY(py) - 0.5 / scale
        let x = viewX(px) + 0.5 / scale

        let horizontal = shape(Self.measureLine(from: NSPoint(x: x0, y: y), to: NSPoint(x: x1, y: y)))
        let vertical = shape(Self.measureLine(from: NSPoint(x: x, y: bottom), to: NSPoint(x: x, y: top)))
        let width = format(d.width), height = format(d.height)
        let widthLabel = label(width, center: NSPoint(x: (x0 + x1) / 2, y: y + 14))
        let heightLabel = label(height, center: NSPoint(x: x + 8, y: (top + bottom) / 2), anchorLeft: true)

        lastText = "\(width) × \(height)"
        setLive([horizontal, vertical, widthLabel, heightLabel])
    }

    private func showSnap(_ snapped: PixelRect) {
        lastSnap = snapped
        let rect = NSRect(
            x: viewX(snapped.x),
            y: viewY(snapped.y + snapped.height),
            width: CGFloat(snapped.width) / scale,
            height: CGFloat(snapped.height) / scale
        )
        let box = shape(CGPath(rect: rect, transform: nil), dashed: false, fill: true)
        let text = "\(format(snapped.width)) × \(format(snapped.height))"
        let size = label(text, center: NSPoint(x: rect.midX, y: rect.minY - 14))
        lastText = text
        setLive([box, size])
    }

    private func keepCurrent() {
        guard !liveItems.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in liveItems {
            item.removeFromSuperlayer()
            keptLayer.addSublayer(item)
        }
        CATransaction.commit()
        liveItems = []
    }

    /// Edit → Copy (⌘C) while measuring.
    @objc func copy(_ sender: Any?) {
        copyLast()
    }

    private func copyLast() {
        guard let lastText else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lastText, forType: .string)
        Sounds.play(.copy)
        flash("Copied \(lastText)")
    }

    private func export() {
        hideHint()
        guard let root = layer,
              let context = CGContext(
                data: nil, width: pixels.width, height: pixels.height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        context.scaleBy(x: scale, y: scale)
        root.render(in: context)
        guard let cg = context.makeImage() else { return }
        onExport?(NSImage(cgImage: cg, size: bounds.size))
    }

    // MARK: - Drawing helpers

    private func setLive(_ items: [CALayer]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        liveItems.forEach { $0.removeFromSuperlayer() }
        items.forEach(liveLayer.addSublayer)
        liveItems = items
        CATransaction.commit()
    }

    /// A line with short perpendicular end caps, like a dimension line on a drawing.
    private static func measureLine(from a: NSPoint, to b: NSPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let cap: CGFloat = 4
        if a.y == b.y {
            path.move(to: NSPoint(x: a.x, y: a.y - cap)); path.addLine(to: NSPoint(x: a.x, y: a.y + cap))
            path.move(to: NSPoint(x: b.x, y: b.y - cap)); path.addLine(to: NSPoint(x: b.x, y: b.y + cap))
        } else {
            path.move(to: NSPoint(x: a.x - cap, y: a.y)); path.addLine(to: NSPoint(x: a.x + cap, y: a.y))
            path.move(to: NSPoint(x: b.x - cap, y: b.y)); path.addLine(to: NSPoint(x: b.x + cap, y: b.y))
        }
        return path
    }

    private func shape(_ path: CGPath, dashed: Bool = false, fill: Bool = false, color: NSColor? = nil) -> CAShapeLayer {
        let color = color ?? Self.tape
        let layer = CAShapeLayer()
        layer.frame = bounds
        layer.path = path
        layer.lineWidth = 1
        layer.strokeColor = color.cgColor
        layer.fillColor = fill ? color.withAlphaComponent(0.18).cgColor : nil
        if dashed { layer.lineDashPattern = [4, 3] }
        // A thin dark halo keeps lines visible on content of the same color.
        layer.shadowColor = Self.ink.cgColor
        layer.shadowOpacity = 0.8
        layer.shadowRadius = 0.6
        layer.shadowOffset = .zero
        layer.contentsScale = scale
        return layer
    }

    private func label(_ text: String, center: NSPoint, anchorLeft: Bool = false,
                       background: NSColor? = nil, foreground: NSColor? = nil) -> CALayer {
        let background = background ?? Self.tape
        let foreground = foreground ?? Self.ink
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: foreground])
        let textSize = string.size()
        let padX: CGFloat = 6, padY: CGFloat = 3
        let size = NSSize(width: ceil(textSize.width) + padX * 2, height: ceil(textSize.height) + padY * 2)
        var origin = NSPoint(
            x: anchorLeft ? center.x : center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        origin.x = min(max(4, origin.x), bounds.width - size.width - 4)
        origin.y = min(max(4, origin.y), bounds.height - size.height - 4)

        let box = CALayer()
        box.frame = NSRect(origin: origin, size: size).integral
        box.backgroundColor = background.cgColor
        box.cornerRadius = 4
        box.contentsScale = scale

        let textLayer = CATextLayer()
        textLayer.string = string
        textLayer.contentsScale = scale
        textLayer.frame = NSRect(x: padX, y: padY - 1, width: ceil(textSize.width) + 1, height: ceil(textSize.height) + 1)
        box.addSublayer(textLayer)
        return box
    }

    private func showHint() {
        let hint = label(
            "Point to measure   Drag to snap   H / V guide   ← → nudge   Space keep   ⇧ pixels   ⌘C copy   ⌘S capture   Esc done",
            center: NSPoint(x: bounds.midX, y: bounds.maxY - 40)
        )
        layer?.addSublayer(hint)
        hintLayer = hint
    }

    private func hideHint() {
        hintLayer?.removeFromSuperlayer()
        hintLayer = nil
    }

    private func flash(_ text: String) {
        let note = label(text, center: NSPoint(x: bounds.midX, y: bounds.maxY - 40))
        layer?.addSublayer(note)
        runAfter(1.2) { note.removeFromSuperlayer() }
    }

    // MARK: - Units and coordinates

    /// Pixels → the number shown: points by default, pixels while ⇧ is held.
    private func format(_ pixelCount: Int) -> String {
        if showPixels { return "\(pixelCount)" }
        let points = CGFloat(pixelCount) / scale
        let rounded = points.rounded()
        return abs(points - rounded) < 0.05 ? "\(Int(rounded))" : String(format: "%.1f", points)
    }

    private func pixel(at point: NSPoint) -> (Int, Int) {
        let x = Int((point.x * scale).rounded(.down))
        let y = Int(((bounds.height - point.y) * scale).rounded(.down))
        return (min(max(0, x), pixels.width - 1), min(max(0, y), pixels.height - 1))
    }

    /// Left edge of pixel column `px`, in view points.
    private func viewX(_ px: Int) -> CGFloat { CGFloat(px) / scale }
    /// Top edge of pixel row `py`, in view points (view origin is bottom-left).
    private func viewY(_ py: Int) -> CGFloat { bounds.height - CGFloat(py) / scale }

    private static func rect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

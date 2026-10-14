import AppKit
import SwiftUI

@MainActor
final class AnnotationDocument: ObservableObject {
    let baseImage: NSImage
    let pixelated: NSImage

    @Published var annotations: [Annotation] = []
    @Published var current: Annotation?
    @Published var tool: AnnotationTool = .arrow
    @Published var color: Color = .red
    @Published var lineWidth: CGFloat = 5
    @Published private var redoStack: [Annotation] = []

    init(image: NSImage) {
        baseImage = image
        pixelated = AnnotationRenderer.pixelate(image)
    }

    var size: CGSize { baseImage.size }
    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Everything that should be drawn right now, including the shape being dragged.
    var visibleAnnotations: [Annotation] {
        current.map { annotations + [$0] } ?? annotations
    }

    // MARK: - Gestures (image coordinates)

    func dragChanged(from start: CGPoint, to location: CGPoint) {
        switch tool {
        case .text, .counter:
            return
        case .pen:
            if current == nil {
                current = Annotation(tool: tool, color: color, lineWidth: lineWidth, points: [start])
            }
            current?.points.append(location)
        default:
            current = Annotation(tool: tool, color: color, lineWidth: lineWidth, points: [start, location])
        }
    }

    func dragEnded(at location: CGPoint) {
        switch tool {
        case .counter:
            let next = (annotations.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1
            append(Annotation(tool: .counter, color: color, lineWidth: lineWidth, points: [location], number: next))
        case .text:
            // Run the modal prompt outside the gesture callback.
            runAfter(0) { [weak self] in
                guard let self, let text = Self.promptForText() else { return }
                self.append(Annotation(tool: .text, color: self.color, lineWidth: self.lineWidth,
                                       points: [location], text: text))
            }
        default:
            if let shape = current, shape.rect.width > 2 || shape.rect.height > 2 || shape.tool == .pen {
                append(shape)
            }
            current = nil
        }
    }

    private func append(_ a: Annotation) {
        annotations.append(a)
        redoStack.removeAll()
    }

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
    }

    // MARK: - Export

    func render() -> NSImage {
        let size = self.size
        let base = baseImage
        let pixelated = Image(nsImage: self.pixelated)
        let annotations = self.annotations
        let view = Canvas { ctx, _ in
            ctx.draw(Image(nsImage: base), in: CGRect(origin: .zero, size: size))
            AnnotationRenderer.draw(annotations, in: ctx, imageSize: size, pixelated: pixelated)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = base.pixelScale
        guard let output = renderer.nsImage else { return base }
        return output
    }

    private static func promptForText() -> String? {
        let alert = NSAlert()
        alert.messageText = "Add Text"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

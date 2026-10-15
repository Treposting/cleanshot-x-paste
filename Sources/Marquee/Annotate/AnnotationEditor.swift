import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    private let document: AnnotationDocument
    private let onDone: (NSImage) -> Void
    private var window: NSWindow?
    var onClose: (() -> Void)?

    init(image: NSImage, onDone: @escaping (NSImage) -> Void) {
        self.document = AnnotationDocument(image: image)
        self.onDone = onDone
        super.init()
    }

    func present() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(document.size.width + 60, 760), screen.width * 0.85)
        let height = min(max(document.size.height + 110, 480), screen.height * 0.85)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Annotate"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: AnnotationEditorView(
            document: document,
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.saveAs() },
            onDone: { [weak self] in self?.finish() }
        ))
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func copy() {
        let image = document.render()
        image.copyToPasteboard()
        onDone(image)
        Toast.show("Copied to clipboard")
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Capture.fileName(for: Date())
        panel.directoryURL = Preferences.saveFolder
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self, let url = panel.url else { return }
                let image = self.document.render()
                try? image.pngData?.write(to: url, options: .atomic)
                self.onDone(image)
            }
        }
    }

    private func finish() {
        onDone(document.render())
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
struct AnnotationEditorView: View {
    @ObservedObject var document: AnnotationDocument
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDone: () -> Void

    private static let swatches: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let size = document.size
                let scale = min(1, (geo.size.width - 40) / size.width, (geo.size.height - 40) / size.height)
                canvas(scale: max(scale, 0.05))
                    .frame(width: size.width * scale, height: size.height * scale)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 420)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $document.tool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Image(systemName: tool.symbol).help(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            HStack(spacing: 4) {
                ForEach(Self.swatches, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(document.color == color ? 0.9 : 0.2),
                                                 lineWidth: document.color == color ? 2 : 1))
                        .onTapGesture { document.color = color }
                }
                ColorPicker("Color", selection: $document.color).labelsHidden()
            }

            Slider(value: $document.lineWidth, in: 1...20)
                .frame(width: 90)
                .help("Size")

            Spacer()

            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.canUndo)
                .help("Undo")
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.canRedo)
                .help("Redo")
            Button("Copy", action: onCopy).keyboardShortcut("c", modifiers: .command)
            Button("Save…", action: onSave).keyboardShortcut("s", modifiers: .command)
            Button("Done", action: onDone)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
    }

    private func canvas(scale: CGFloat) -> some View {
        let size = document.size
        let base = Image(nsImage: document.baseImage)
        let pixelated = Image(nsImage: document.pixelated)
        let annotations = document.visibleAnnotations
        return Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            ctx.draw(base, in: CGRect(origin: .zero, size: size))
            AnnotationRenderer.draw(annotations, in: ctx, imageSize: size, pixelated: pixelated)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    document.dragChanged(from: value.startLocation.scaled(1 / scale),
                                         to: value.location.scaled(1 / scale))
                }
                .onEnded { value in
                    document.dragEnded(at: value.location.scaled(1 / scale))
                }
        )
    }
}

private extension CGPoint {
    func scaled(_ s: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
}

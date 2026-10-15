import AppKit
import SwiftUI

/// The floating thumbnail that appears in the corner after every capture
/// (CleanShot calls it the "Quick Access Overlay"). Several can stack up.
@MainActor
final class QuickAccessManager {
    static let shared = QuickAccessManager()

    private var panels: [(capture: Capture, panel: NSPanel)] = []
    private var editors: [AnnotationWindowController] = []

    private let size = NSSize(width: 260, height: 190)
    private let margin: CGFloat = 18
    private let spacing: CGFloat = 12

    func show(_ capture: Capture) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: QuickAccessView(capture: capture) { [weak self] action in
            self?.perform(action, on: capture)
        })

        panels.append((capture, panel))
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }

        let timeout = Preferences.overlayTimeout
        if timeout > 0 {
            runAfter(Double(timeout)) { [weak self] in
                self?.dismiss(capture)
            }
        }
    }

    func dismiss(_ capture: Capture) {
        guard let index = panels.firstIndex(where: { $0.capture === capture }) else { return }
        let panel = panels.remove(at: index).panel
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) {
            Task { @MainActor in panel.orderOut(nil) }
        }
        layout()
    }

    private func layout() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        for (i, entry) in panels.reversed().enumerated() {
            let origin = NSPoint(
                x: visible.minX + margin,
                y: visible.minY + margin + CGFloat(i) * (size.height + spacing)
            )
            entry.panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
        }
    }

    private func perform(_ action: QuickAccessAction, on capture: Capture) {
        switch action {
        case .copy:
            capture.copyToPasteboard()
            Toast.show("Copied to clipboard")
            dismiss(capture)
        case .save:
            if let url = capture.save() {
                Toast.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            }
            dismiss(capture)
        case .annotate:
            openEditor(for: capture)
        case .pin:
            PinnedImageWindow.pin(capture.image)
            dismiss(capture)
        case .open:
            NSWorkspace.shared.open(capture.url)
        case .saveGIF:
            exportGIF(capture)
        case .close:
            dismiss(capture)
        }
    }

    private func exportGIF(_ capture: Capture) {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = Capture.uniqueURL(in: folder, date: capture.date, ext: "gif")
        let source = capture.url
        Toast.show("Creating GIF…", duration: 30)
        Task {
            do {
                try await VideoTools.exportGIF(from: source, to: dest)
                Toast.show("Saved \(dest.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            } catch {
                Toast.show(error.localizedDescription)
            }
        }
    }

    func openEditor(for capture: Capture) {
        let editor = AnnotationWindowController(image: capture.image) { [weak capture] edited in
            capture?.update(image: edited)
        }
        editor.onClose = { [weak self, weak editor] in
            self?.editors.removeAll { $0 === editor }
        }
        editors.append(editor)
        editor.present()
    }
}

enum QuickAccessAction {
    case copy, save, annotate, pin, open, saveGIF, close
}

@MainActor
struct QuickAccessView: View {
    @ObservedObject var capture: Capture
    var onAction: (QuickAccessAction) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                Image(nsImage: capture.image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if capture.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 34))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .onTapGesture { onAction(.open) }
                        }
                    }
                    .onDrag {
                        NSItemProvider(contentsOf: capture.url) ?? NSItemProvider()
                    }
                    .help("Drag into any app")

                HStack(spacing: 6) {
                    actionButton("doc.on.doc", "Copy") { onAction(.copy) }
                    actionButton("square.and.arrow.down", "Save") { onAction(.save) }
                    if capture.isVideo {
                        actionButton("photo.stack", "Save as GIF") { onAction(.saveGIF) }
                        actionButton("play.rectangle", "Open") { onAction(.open) }
                    } else {
                        actionButton("pencil.tip.crop.circle", "Annotate") { onAction(.annotate) }
                        actionButton("pin", "Pin to screen") { onAction(.pin) }
                    }
                }
            }
            .padding(10)

            Button { onAction(.close) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .frame(width: 260, height: 190)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity, minHeight: 22)
        }
        .glassButtonStyle()
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
    }
}

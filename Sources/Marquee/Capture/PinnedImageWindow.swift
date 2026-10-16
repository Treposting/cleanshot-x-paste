import AppKit

/// Keeps a screenshot floating above all windows ("Pin to screen").
/// Drag to move, scroll to change opacity, double-click or Esc to close,
/// right-click for a menu.
@MainActor
final class PinnedImageWindow: NSPanel {
    private static var open: [PinnedImageWindow] = []

    static func pin(_ image: NSImage) {
        let window = PinnedImageWindow(image: image)
        open.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    private var image: NSImage?

    private convenience init(image: NSImage) {
        var size = image.size
        let maxSide: CGFloat = 600
        if max(size.width, size.height) > maxSide {
            let s = maxSide / max(size.width, size.height)
            size = NSSize(width: size.width * s, height: size.height * s)
        }
        let mouse = NSEvent.mouseLocation
        let rect = NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2,
                          width: size.width, height: size.height)
        self.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        self.image = image
        isReleasedWhenClosed = false
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentAspectRatio = image.size

        let view = DraggableImageView()
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: #selector(copyImage), keyEquivalent: "c")
        copy.target = self
        let close = NSMenuItem(title: "Close", action: #selector(closePin), keyEquivalent: "")
        close.target = self
        menu.addItem(copy)
        menu.addItem(close)
        view.menu = menu

        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { closePin() } else { super.keyDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        alphaValue = min(1, max(0.2, alphaValue + event.scrollingDeltaY * 0.01))
    }

    @objc private func copyImage() {
        image?.copyToPasteboard()
        Sounds.play(.copy)
        Toast.show("Copied to clipboard")
    }

    @objc func closePin() {
        orderOut(nil)
        PinnedImageWindow.open.removeAll { $0 === self }
    }
}

private final class DraggableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (window as? PinnedImageWindow)?.closePin()
        } else {
            window?.performDrag(with: event)
        }
    }
}

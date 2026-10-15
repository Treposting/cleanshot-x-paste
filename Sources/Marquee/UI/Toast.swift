import AppKit
import SwiftUI

/// Small HUD message ("Copied to clipboard") that fades out on its own.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var generation = 0

    static func show(_ message: String, duration: TimeInterval = 1.4) {
        panel?.orderOut(nil)
        generation += 1
        let current = generation

        let host = NSHostingView(rootView:
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        )
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
        }
        p.orderFrontRegardless()
        panel = p

        runAfter(duration) {
            guard generation == current else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
                Task { @MainActor in p.orderOut(nil) }
            }
        }
    }
}

import AppKit
import SwiftUI

/// One shortcut for everything: select an area, then choose Screenshot, Record,
/// Copy Text or Pin from a toolbar under it.
@MainActor
final class AllInOneController {
    static let shared = AllInOneController()

    enum Choice {
        case screenshot, record, copyText, pin
    }

    /// Set by the app delegate: runs the chosen action on the selected area.
    var onChoice: ((Choice, NSScreen, CGRect) -> Void)?

    private var toolbar: NSPanel?
    private var border: NSWindow?
    private var target: (screen: NSScreen, rect: CGRect)?

    var isActive: Bool { toolbar != nil }

    func start() {
        guard !isActive else { return }
        AreaSelector.select(hint: "Drag to select an area  ·  Return: whole screen  ·  Esc: cancel") { [weak self] selection in
            guard let self, let selection else { return }
            self.present(screen: selection.0, rect: selection.1)
        }
    }

    private func present(screen: NSScreen, rect: CGRect) {
        target = (screen, rect)
        showBorder(around: rect)

        let size = NSSize(width: 560, height: 92)
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let sizeLabel = rect == screen.frame ? "Full screen" : "\(Int(rect.width)) × \(Int(rect.height))"
        panel.contentView = NSHostingView(rootView:
            AllInOneToolbar(sizeLabel: sizeLabel) { [weak self] choice in
                self?.choose(choice)
            } cancel: { [weak self] in
                self?.dismiss()
            }
            .frame(width: size.width, height: size.height)
        )

        let visible = screen.visibleFrame
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 6)
        if origin.y < visible.minY + 8 {
            origin.y = rect == screen.frame ? visible.minY + 28 : max(visible.minY + 8, rect.minY + 12)
        }
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        toolbar = panel
    }

    private func choose(_ choice: Choice) {
        guard let target else { return }
        dismiss()
        // Let the toolbar and border leave the screen before capturing.
        runAfter(0.15) { [weak self] in
            self?.onChoice?(choice, target.screen, target.rect)
        }
    }

    func dismiss() {
        toolbar?.orderOut(nil)
        toolbar = nil
        border?.orderOut(nil)
        border = nil
        target = nil
    }

    private func showBorder(around rect: CGRect) {
        let window = NSWindow(contentRect: rect.insetBy(dx: -3, dy: -3), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = SelectionBorderView()
        window.orderFrontRegardless()
        border = window
    }
}

private final class SelectionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 1.5
        NSColor(calibratedRed: 1, green: 0.81, blue: 0.1, alpha: 1).setStroke()
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
}

/// Large labeled buttons, like the capture HUD in pro screenshot tools.
@MainActor
private struct AllInOneToolbar: View {
    let sizeLabel: String
    let choose: (AllInOneController.Choice) -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HUDButton(symbol: "camera", title: "Screenshot", hint: "Return") { choose(.screenshot) }
                .keyboardShortcut(.defaultAction)
            HUDButton(symbol: "record.circle", title: "Record", tint: .red) { choose(.record) }
                .keyboardShortcut("r", modifiers: [])
            HUDButton(symbol: "text.viewfinder", title: "Copy Text") { choose(.copyText) }
                .keyboardShortcut("t", modifiers: [])
            HUDButton(symbol: "pin", title: "Pin") { choose(.pin) }
                .keyboardShortcut("p", modifiers: [])

            Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 44).padding(.horizontal, 4)

            VStack(spacing: 6) {
                Text(sizeLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Cancel (Esc)")
                .accessibilityLabel("Cancel")
            }
            .padding(.horizontal, 6)
        }
        .padding(8)
        .hudSurface()
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }
}

private struct HUDButton: View {
    let symbol: String
    let title: String
    var hint: String? = nil
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(width: 84, height: 62)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.16 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(hint.map { "\(title) (\($0))" } ?? title)
        .accessibilityLabel(title)
    }
}

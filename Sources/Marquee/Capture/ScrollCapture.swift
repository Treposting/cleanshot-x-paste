import AppKit
import ScreenCaptureKit
import SwiftUI

/// Grabs the scrolling area about ten times a second and stitches the frames, off the main thread.
@available(macOS 14.0, *)
private actor ScrollSession {
    private let filter: SCContentFilter
    private let config: SCStreamConfiguration
    private let ignoreRight: Int
    private var stitcher: ScrollStitcher?

    /// - Parameters:
    ///   - displayID: the display the area is on.
    ///   - sourceRect: the area in display-local points, top-left origin (as ScreenCaptureKit wants).
    init(displayID: CGDirectDisplayID, sourceRect: CGRect, scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayNotFound
        }
        // Marquee's own outline and control bar stay out of the frames.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int((sourceRect.width * scale).rounded())
        config.height = Int((sourceRect.height * scale).rounded())
        config.showsCursor = false
        config.capturesAudio = false
        self.config = config
        // Overlay scroll bars are about 16 pt wide; leave them out of the matching.
        ignoreRight = Int((18 * scale).rounded())
    }

    /// Takes one frame and adds it. Returns nil for the first frame.
    func step() async throws -> ScrollStitcher.Step? {
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let frame = ScrollFrame(image: image, ignoreRight: ignoreRight) else { return .lost }
        guard stitcher != nil else {
            stitcher = ScrollStitcher(first: frame)
            return nil
        }
        return stitcher?.add(frame)
    }

    var height: Int { stitcher?.height ?? 0 }

    func image() -> CGImage? { stitcher?.image() }
}

/// State shown on the control bar.
@MainActor
final class ScrollCaptureModel: ObservableObject {
    enum Status: Equatable {
        case starting, scrolling, lost, full, finishing
    }

    @Published var status: Status = .starting
    /// Captured height in points.
    @Published var height: CGFloat = 0
    @Published var autoScrolling = false
}

/// Scrolling capture: select an area, then scroll it (or let Marquee scroll it) and press Done.
/// The frames are stitched into one tall screenshot that goes to Quick Access like any other.
@MainActor
final class ScrollCaptureController {
    static let shared = ScrollCaptureController()

    /// Set by the app delegate: receives the finished PNG.
    var onFinished: ((URL) -> Void)?

    private let model = ScrollCaptureModel()
    private var outline: NSWindow?
    private var bar: NSPanel?
    private var loop: Task<Void, Never>?
    private var autoScroll: Task<Void, Never>?
    private var rect: CGRect = .zero
    private var scale: CGFloat = 2
    /// Done was pressed; the loop makes the image after its current frame.
    private var finishRequested = false

    var isActive: Bool { outline != nil }

    /// - Parameter rect: the area to capture, in global AppKit coordinates.
    func start(screen: NSScreen, rect: CGRect) {
        guard !isActive else { return }
        guard #available(macOS 14.0, *) else {
            let alert = NSAlert()
            alert.messageText = "Scrolling capture needs macOS 14 Sonoma or later"
            alert.informativeText = "Everything else in Marquee works on macOS 13."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        guard let displayID = screen.displayID, rect.width >= 40, rect.height >= 60 else { return }
        self.rect = rect.integral
        scale = screen.backingScaleFactor
        finishRequested = false
        model.status = .starting
        model.height = 0
        model.autoScrolling = false
        showOutline(on: screen)
        showBar(on: screen)

        let sourceRect = CGRect(x: self.rect.minX - screen.frame.minX, y: screen.frame.maxY - self.rect.maxY,
                                width: self.rect.width, height: self.rect.height)
        let scale = self.scale
        loop = Task { [weak self] in
            do {
                let session = try await ScrollSession(displayID: displayID, sourceRect: sourceRect, scale: scale)
                await self?.run(session)
            } catch {
                self?.close()
                self?.showPermissionAlert(error)
            }
        }
    }

    @available(macOS 14.0, *)
    private func run(_ session: ScrollSession) async {
        var stillFrames = 0
        while !Task.isCancelled, !finishRequested {
            do {
                let step = try await session.step()
                if finishRequested || Task.isCancelled { break }
                model.height = CGFloat(await session.height) / scale
                switch step {
                case nil, .added?:
                    model.status = .scrolling
                    stillFrames = 0
                case .unchanged?:
                    stillFrames += 1
                    if model.status == .lost { model.status = .scrolling }
                    // Auto-scroll keeps going until the page stops moving: that's the end.
                    if model.autoScrolling, stillFrames >= 5 {
                        await finish(session)
                        return
                    }
                case .lost?:
                    model.status = .lost
                case .full?:
                    model.status = .full
                    stopAutoScroll()
                }
            } catch {
                model.status = .lost
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        if finishRequested, !Task.isCancelled { await finish(session) }
    }

    // MARK: - Actions

    func done() {
        guard isActive, !finishRequested else { return }
        stopAutoScroll()
        finishRequested = true
        model.status = .finishing
    }

    func cancel() {
        loop?.cancel()
        close()
    }

    func toggleAutoScroll() {
        if model.autoScrolling {
            stopAutoScroll()
            return
        }
        guard Paster.isTrusted else {
            Paster.requestAccess()
            Toast.show("Allow Marquee in Accessibility to auto-scroll", duration: 3)
            return
        }
        model.autoScrolling = true
        moveCursorIntoArea()
        let step = Int32(max(40, (rect.height * 0.35).rounded()))
        autoScroll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.model.autoScrolling else { return }
                Self.postScroll(pixels: -step)
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
        }
    }

    private func stopAutoScroll() {
        model.autoScrolling = false
        autoScroll?.cancel()
        autoScroll = nil
    }

    @available(macOS 14.0, *)
    private func finish(_ session: ScrollSession) async {
        stopAutoScroll()
        let image = await session.image()
        close()
        guard let image else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee-scroll-\(UUID().uuidString).png")
        let nsImage = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale,
                                                           height: CGFloat(image.height) / scale))
        guard let data = nsImage.pngData, (try? data.write(to: url, options: .atomic)) != nil else { return }
        onFinished?(url)
    }

    private func close() {
        stopAutoScroll()
        loop = nil
        outline?.orderOut(nil)
        outline = nil
        bar?.orderOut(nil)
        bar = nil
    }

    // MARK: - Scrolling for the user

    /// Scroll events go to the window under the pointer, so it has to be over the area.
    private func moveCursorIntoArea() {
        guard !NSMouseInRect(NSEvent.mouseLocation, rect, false) else { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: primaryTop - rect.midY))
    }

    private static func postScroll(pixels: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                            wheel1: pixels, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Windows

    /// A dashed outline just outside the area. It never takes clicks or scrolls.
    private func showOutline(on screen: NSScreen) {
        let frame = rect.insetBy(dx: -3, dy: -3)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color(red: 1, green: 0.81, blue: 0.1),
                              style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        window.orderFrontRegardless()
        outline = window
    }

    /// The control bar sits below the area, or above it when there's no room.
    private func showBar(on screen: NSScreen) {
        let hosting = ClickThroughHostingView(rootView: ScrollCaptureBar(
            model: model,
            done: { [weak self] in self?.done() },
            autoScroll: { [weak self] in self?.toggleAutoScroll() },
            cancel: { [weak self] in self?.cancel() }
        ))
        // Measure before turning off sizing, or the panel ends up zero-sized.
        var size = hosting.fittingSize
        if size.width < 100 || size.height < 30 { size = NSSize(width: 520, height: 64) }
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        let visible = screen.visibleFrame
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 6)
        if origin.y < visible.minY { origin.y = min(rect.maxY + 6, visible.maxY - size.height) }
        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        bar = panel
    }

    private func showPermissionAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't capture the screen"
        alert.informativeText = """
        \(error.localizedDescription)

        Scrolling capture needs the Screen Recording permission. If it's already on in System Settings, \
        use Fix Permissions on the Permissions page, then restart Marquee.
        """
        alert.addButton(withTitle: "Open Permissions")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.shared.showMain(.permissions)
        }
    }
}

/// Buttons work on the first click without making Marquee the active app, so the app being
/// scrolled keeps focus.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// "Scroll down to capture", the captured height, Auto-scroll, Cancel and Done.
private struct ScrollCaptureBar: View {
    @ObservedObject var model: ScrollCaptureModel
    let done: @MainActor () -> Void
    let autoScroll: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    private var message: String {
        switch model.status {
        case .starting: return "Getting ready…"
        case .scrolling: return model.autoScrolling ? "Scrolling for you…" : "Scroll down to capture"
        case .lost: return "Scroll a little slower"
        case .full: return "That's the longest it can be. Press Done"
        case .finishing: return "Making the image…"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.status == .lost ? "exclamationmark.triangle.fill" : "scroll")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.status == .lost ? Color.orange : Color.primary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(message)
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(Int(model.height)) pt captured")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 210, alignment: .leading)
            Button(model.autoScrolling ? "Stop" : "Auto-scroll", action: autoScroll)
                .glassButtonStyle()
                .help("Marquee scrolls the area for you and stops at the end")
            Button("Cancel", action: cancel)
                .glassButtonStyle()
            Button("Done", action: done)
                .glassButtonStyle(prominent: true)
                .disabled(model.status == .starting || model.status == .finishing)
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassSurface(Capsule())
        .padding(8)
        .fixedSize()
    }
}

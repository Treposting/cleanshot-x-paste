import AppKit

enum CaptureMode {
    case area
    case window
    case fullscreen
    case timedFullscreen
    case text
}

/// Takes screenshots by driving Apple's own `/usr/sbin/screencapture` tool.
///
/// It gives us the native crosshair selection UI (with Space to toggle window
/// mode, Esc to cancel, Shift/Option to lock and resize) for free, and handles
/// multiple displays and Retina scaling. The Screen Recording permission prompt
/// is attributed to Marquee because we are the responsible process.
@MainActor
final class CaptureService {
    private var isCapturing = false

    func capture(_ mode: CaptureMode, completion: @escaping @MainActor (URL?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marquee-\(UUID().uuidString).png")

        var args: [String] = []
        if !Preferences.playSound || mode == .text { args.append("-x") }
        switch mode {
        case .area, .text:
            args += ["-i", "-s"]
        case .window:
            args += ["-i", "-w"]
            if !Preferences.windowShadow { args.append("-o") }
        case .fullscreen:
            args += ["-D", String(displayIndexUnderMouse())]
        case .timedFullscreen:
            args += ["-D", String(displayIndexUnderMouse()), "-T", "5"]
        }
        args.append(url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        process.terminationHandler = { _ in
            Task { @MainActor in
                self.isCapturing = false
                // The user pressed Esc if no file was written.
                completion(FileManager.default.fileExists(atPath: url.path) ? url : nil)
            }
        }
        do {
            try process.run()
        } catch {
            isCapturing = false
            NSLog("Marquee: screencapture failed: \(error)")
            completion(nil)
        }
    }

    /// `screencapture -D` uses 1-based display indices in the same order as NSScreen.screens.
    private func displayIndexUnderMouse() -> Int {
        let mouse = NSEvent.mouseLocation
        let index = NSScreen.screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        return index + 1
    }
}

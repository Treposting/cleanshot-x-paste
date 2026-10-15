import AppKit
import ScreenCaptureKit

/// One still image of a display, taken with ScreenCaptureKit. Marquee's own windows
/// (Quick Access overlays, pinned images) are left out so they never get measured.
@available(macOS 14.0, *)
enum ScreenSnapshot {
    static func capture(screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID = screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayNotFound
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.capturesAudio = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

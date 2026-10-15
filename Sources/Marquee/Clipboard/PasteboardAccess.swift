import AppKit

/// macOS 15.4 added a privacy setting for apps that read the clipboard in the background,
/// which is exactly what clipboard history does. When it's set to ask or deny, history
/// can't record copies, so Settings explains how to allow it.
enum PasteboardAccess {
    enum Status: Equatable {
        /// Marquee can read the clipboard (or this macOS has no such setting).
        case allowed
        /// macOS asks before each background read.
        case asks
        /// Not decided yet, or blocked.
        case restricted
    }

    static var status: Status {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow:
            return .allowed
        case .ask:
            return .asks
        default:
            return .restricted
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}

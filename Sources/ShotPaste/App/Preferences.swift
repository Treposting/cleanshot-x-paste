import Foundation

/// Thin wrapper around UserDefaults. Keys are shared with `@AppStorage` in SettingsView.
enum Preferences {
    enum Key: String {
        case showOverlay
        case copyAfterCapture
        case saveAfterCapture
        case playSound
        case windowShadow
        case saveFolder
        case overlayTimeout
        case historyLimit
        case autoPaste
        case monitorPaused
    }

    static var defaults: UserDefaults { .standard }

    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.showOverlay.rawValue: true,
            Key.copyAfterCapture.rawValue: true,
            Key.saveAfterCapture.rawValue: false,
            Key.playSound.rawValue: true,
            Key.windowShadow.rawValue: true,
            Key.saveFolder.rawValue: defaultSaveFolder.path,
            Key.overlayTimeout.rawValue: 0,
            Key.historyLimit.rawValue: 500,
            Key.autoPaste.rawValue: true,
            Key.monitorPaused.rawValue: false,
        ])
    }

    static var showOverlay: Bool { defaults.bool(forKey: Key.showOverlay.rawValue) }
    static var copyAfterCapture: Bool { defaults.bool(forKey: Key.copyAfterCapture.rawValue) }
    static var saveAfterCapture: Bool { defaults.bool(forKey: Key.saveAfterCapture.rawValue) }
    static var playSound: Bool { defaults.bool(forKey: Key.playSound.rawValue) }
    static var windowShadow: Bool { defaults.bool(forKey: Key.windowShadow.rawValue) }
    static var overlayTimeout: Int { defaults.integer(forKey: Key.overlayTimeout.rawValue) }
    static var historyLimit: Int { max(10, defaults.integer(forKey: Key.historyLimit.rawValue)) }
    static var autoPaste: Bool { defaults.bool(forKey: Key.autoPaste.rawValue) }

    static var monitorPaused: Bool {
        get { defaults.bool(forKey: Key.monitorPaused.rawValue) }
        set { defaults.set(newValue, forKey: Key.monitorPaused.rawValue) }
    }

    static var saveFolder: URL {
        let path = defaults.string(forKey: Key.saveFolder.rawValue) ?? defaultSaveFolder.path
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}

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
        case recordFPS
        case recordShowCursor
        case recordAudio
        case recordMicrophone
        case recordMicrophoneID
        case recordCountdownSeconds
        case measureTolerance
        case autoCheckUpdates
        case skippedVersion
    }

    static var defaults: UserDefaults { .standard }

    static var defaultSaveFolder: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// The app was called ShotPaste (bundle ID io.github.shotpaste) up to 0.2.0.
    /// Copy its settings and shortcuts over the first time Marquee runs.
    static func migrateLegacySettings() {
        let migratedKey = "migratedFromShotPaste"
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let legacy = defaults.persistentDomain(forName: "io.github.shotpaste") else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
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
            Key.recordFPS.rawValue: 30,
            Key.recordShowCursor.rawValue: true,
            Key.recordAudio.rawValue: false,
            Key.recordMicrophone.rawValue: false,
            Key.recordCountdownSeconds.rawValue: 3,
            Key.measureTolerance.rawValue: 12,
            Key.autoCheckUpdates.rawValue: true,
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

    static var recordFPS: Int { defaults.integer(forKey: Key.recordFPS.rawValue) == 60 ? 60 : 30 }
    static var recordShowCursor: Bool { defaults.bool(forKey: Key.recordShowCursor.rawValue) }
    /// Record desktop audio (what the Mac plays).
    static var recordAudio: Bool {
        get { defaults.bool(forKey: Key.recordAudio.rawValue) }
        set { defaults.set(newValue, forKey: Key.recordAudio.rawValue) }
    }
    static var recordMicrophone: Bool {
        get { defaults.bool(forKey: Key.recordMicrophone.rawValue) }
        set { defaults.set(newValue, forKey: Key.recordMicrophone.rawValue) }
    }
    /// The chosen microphone's unique ID; nil means the system default input.
    static var recordMicrophoneID: String? {
        get {
            let id = defaults.string(forKey: Key.recordMicrophoneID.rawValue)
            return id?.isEmpty == false ? id : nil
        }
        set { defaults.set(newValue, forKey: Key.recordMicrophoneID.rawValue) }
    }
    /// Seconds of 3-2-1 countdown before recording starts; 0 starts instantly.
    static var recordCountdownSeconds: Int {
        min(max(0, defaults.integer(forKey: Key.recordCountdownSeconds.rawValue)), 10)
    }

    static var measureTolerance: Int { min(max(0, defaults.integer(forKey: Key.measureTolerance.rawValue)), 64) }
    static var autoCheckUpdates: Bool { defaults.bool(forKey: Key.autoCheckUpdates.rawValue) }

    static var skippedVersion: String? {
        get { defaults.string(forKey: Key.skippedVersion.rawValue) }
        set { defaults.set(newValue, forKey: Key.skippedVersion.rawValue) }
    }

    static var monitorPaused: Bool {
        get { defaults.bool(forKey: Key.monitorPaused.rawValue) }
        set { defaults.set(newValue, forKey: Key.monitorPaused.rawValue) }
    }

    static var saveFolder: URL {
        let path = defaults.string(forKey: Key.saveFolder.rawValue) ?? defaultSaveFolder.path
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}

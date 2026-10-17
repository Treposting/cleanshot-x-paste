import AppKit

/// Apps whose copies are never saved in clipboard history: password managers and Keychain
/// (on by default) plus any apps the user adds. Checked before anything is stored.
enum IgnoredApps {
    struct App: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    static let didChange = Notification.Name("MarqueeIgnoredAppsDidChange")

    /// Password managers and secrets apps, by bundle identifier. Several have had more than
    /// one identifier over the years; all are listed.
    static let passwordManagers: [String: String] = [
        "com.apple.Passwords": "Passwords",
        "com.apple.keychainaccess": "Keychain Access",
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.agilebits.onepassword-osx": "1Password",
        "com.bitwarden.desktop": "Bitwarden",
        "com.lastpass.LastPass": "LastPass",
        "com.dashlane.Dashlane": "Dashlane",
        "com.dashlane.dashlanephonefinal": "Dashlane",
        "com.keepersecurity.passwordmanager": "Keeper",
        "com.nordsec.nordpass": "NordPass",
        "me.proton.pass.electron": "Proton Pass",
        "in.sinew.Enpass-Desktop": "Enpass",
        "org.keepassxc.keepassxc": "KeePassXC",
        "com.markmcguill.strongbox.mac": "Strongbox",
        "com.markmcguill.strongbox.mac.pro": "Strongbox",
    ]

    /// The rule itself, kept free of settings so it's easy to test.
    static func isIgnored(_ bundleID: String?, custom: [String], passwordManagers ignorePasswordManagers: Bool) -> Bool {
        guard let bundleID else { return false }
        if ignorePasswordManagers, passwordManagers[bundleID] != nil { return true }
        return custom.contains(bundleID)
    }

    // MARK: - Settings

    private static var defaults: UserDefaults { .standard }

    /// Ignore the apps in `passwordManagers`. On by default.
    static var ignorePasswordManagers: Bool {
        get { defaults.object(forKey: Preferences.Key.ignorePasswordManagers.rawValue) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Preferences.Key.ignorePasswordManagers.rawValue)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Apps the user added, by bundle identifier.
    static var custom: [String] {
        get { defaults.stringArray(forKey: Preferences.Key.ignoredApps.rawValue) ?? [] }
        set {
            defaults.set(newValue, forKey: Preferences.Key.ignoredApps.rawValue)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func isIgnored(_ bundleID: String?) -> Bool {
        isIgnored(bundleID, custom: custom, passwordManagers: ignorePasswordManagers)
    }

    static func add(_ bundleID: String) {
        guard !custom.contains(bundleID), bundleID != Bundle.main.bundleIdentifier else { return }
        custom.append(bundleID)
    }

    static func remove(_ bundleID: String) {
        custom.removeAll { $0 == bundleID }
    }

    // MARK: - Names and icons

    /// The app's name as Finder shows it, or the identifier if it isn't installed.
    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return passwordManagers[bundleID] ?? bundleID
    }

    static func icon(for bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// The password managers on this Mac, for Settings to name them.
    static func installedPasswordManagers() -> [App] {
        var seen = Set<String>()
        return passwordManagers.keys.sorted().compactMap { id in
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { return nil }
            let name = name(for: id)
            guard seen.insert(name).inserted else { return nil }
            return App(bundleID: id, name: name)
        }
    }

    /// Running apps with a Dock icon that aren't ignored yet, for the "add" menu.
    static func runningCandidates() -> [App] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> App? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, !isIgnored(id) else { return nil }
                return App(bundleID: id, name: app.localizedName ?? name(for: id))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

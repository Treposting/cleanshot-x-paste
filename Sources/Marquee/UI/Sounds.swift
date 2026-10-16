import AppKit

/// Short feedback sounds for copying and pasting, using sounds that ship with macOS.
/// Turned off with "Play sound on copy and paste" in Settings.
@MainActor
enum Sounds {
    enum Effect {
        case copy, paste

        fileprivate var name: NSSound.Name {
            switch self {
            case .copy: return NSSound.Name("Tink")
            case .paste: return NSSound.Name("Pop")
            }
        }
    }

    private static var cache: [NSSound.Name: NSSound] = [:]

    static func play(_ effect: Effect) {
        guard Preferences.copyPasteSound else { return }
        let sound: NSSound?
        if let cached = cache[effect.name] {
            sound = cached
        } else {
            sound = NSSound(named: effect.name)
            sound?.volume = 0.5
            cache[effect.name] = sound
        }
        sound?.stop()
        sound?.play()
    }
}

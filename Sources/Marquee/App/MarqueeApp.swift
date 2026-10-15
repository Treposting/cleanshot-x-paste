import AppKit

@main
@MainActor
enum MarqueeMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        // Menu-bar only app: no Dock icon, no main menu.
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

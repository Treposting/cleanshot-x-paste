import AppKit

/// Lets the Marquee window, onboarding and menus trigger the same actions as the
/// global shortcuts, and reach the shared clipboard store.
@MainActor
final class AppModel {
    static let shared = AppModel()

    private(set) var store: ClipboardStore?
    private(set) var monitor: ClipboardMonitor?
    private var performHandler: ((ShortcutAction) -> Void)?

    func configure(store: ClipboardStore, monitor: ClipboardMonitor, perform: @escaping (ShortcutAction) -> Void) {
        self.store = store
        self.monitor = monitor
        self.performHandler = perform
    }

    /// Runs an action. Capture-type actions hide the Marquee window first so it isn't
    /// in the screenshot, recording or measurement. The color picker keeps it: hiding it
    /// makes Marquee inactive, and the magnifier only gets clicks while Marquee is active.
    func perform(_ action: ShortcutAction) {
        guard action != .clipboardHistory, action != .pickColor else {
            performHandler?(action)
            return
        }
        WindowManager.shared.hideMainWindow()
        runAfter(0.25) { [weak self] in self?.performHandler?(action) }
    }
}

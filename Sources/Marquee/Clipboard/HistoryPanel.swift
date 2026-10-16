import AppKit
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus without activating Marquee,
/// so the app you were typing in stays frontmost and receives the paste.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", text = "Text", links = "Links", images = "Images", files = "Files", pinned = "Pinned"
        var id: String { rawValue }
    }

    @Published var query = "" { didSet { selection = 0 } }
    @Published var filter: Filter = .all { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var focusToken = UUID()

    let store: ClipboardStore
    private var cancellable: AnyCancellable?

    init(store: ClipboardStore) {
        self.store = store
        cancellable = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var visibleItems: [ClipItem] {
        store.items.filter { item in
            let kindMatches: Bool
            switch filter {
            case .all: kindMatches = true
            case .text: kindMatches = item.kind == .text
            case .links: kindMatches = item.kind == .link
            case .images: kindMatches = item.kind == .image
            case .files: kindMatches = item.kind == .file
            case .pinned: kindMatches = item.pinned
            }
            guard kindMatches else { return false }
            let q = query.trimmingCharacters(in: .whitespaces)
            return q.isEmpty || item.searchableText.localizedCaseInsensitiveContains(q)
        }
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selection) ? items[selection] : nil
    }

    func move(by delta: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    func reset() {
        query = ""
        filter = .all
        selection = 0
        focusToken = UUID()
    }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let model: HistoryViewModel
    private let thumbnails = ThumbnailCache()
    private var panel: KeyablePanel!
    private var keyMonitor: Any?

    private let panelHeight: CGFloat = 330

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.model = HistoryViewModel(store: store)
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(
            model: model,
            thumbnails: thumbnails,
            onPaste: { [weak self] item in self?.paste(item) },
            onTogglePin: { [weak self] item in self?.store.togglePin(item) },
            onDelete: { [weak self] item in self?.store.remove(item) }
        ))
        self.panel = panel
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: panelHeight),
                       display: true)
        model.reset()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func paste(_ item: ClipItem) {
        store.writeToPasteboard(item)
        monitor.ignoreCurrentContents()
        store.touch(item)
        hide()
        if Preferences.autoPaste && Paster.isTrusted {
            Sounds.play(.paste)
            Paster.pasteIntoFrontApp()
        } else {
            Sounds.play(.copy)
            if Preferences.autoPaste { Paster.pasteIntoFrontApp() }
        }
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 36, 76: // Return, Enter
            if let item = model.selectedItem { paste(item) }
            return true
        case 123: // ←
            model.move(by: -1)
            return true
        case 124: // →
            model.move(by: 1)
            return true
        case 51 where command: // ⌘⌫
            if let item = model.selectedItem { store.remove(item) }
            return true
        default:
            break
        }

        guard command, let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if let n = Int(chars), (1...9).contains(n) {
            let items = model.visibleItems
            if items.indices.contains(n - 1) { paste(items[n - 1]) }
            return true
        }
        if chars == "p", let item = model.selectedItem {
            store.togglePin(item)
            return true
        }
        return false
    }
}

@MainActor
final class ThumbnailCache {
    private let images = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()

    func thumbnail(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = images.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images.setObject(image, forKey: key)
        return image
    }

    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    func fileIcon(path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

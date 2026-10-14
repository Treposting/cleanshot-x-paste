import AppKit
import CryptoKit

/// Persists clipboard history to
/// ~/Library/Application Support/ShotPaste/{history.json, images/}.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let directory: URL
    let imagesDirectory: URL
    private var historyFile: URL { directory.appendingPathComponent("history.json") }
    private var saveScheduled = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = support.appendingPathComponent("ShotPaste", isDirectory: true)
        imagesDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Adding

    func addText(_ text: String, app: NSRunningApplication?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let kind: ClipItem.Kind = Self.isLink(trimmed) ? .link : .text
        insert(ClipItem(kind: kind, text: text, contentHash: Self.hash(Data(text.utf8)),
                        sourceAppName: app?.localizedName, sourceBundleID: app?.bundleIdentifier))
    }

    func addFiles(_ urls: [URL], app: NSRunningApplication?) {
        let paths = urls.map(\.path)
        insert(ClipItem(kind: .file, filePaths: paths,
                        contentHash: Self.hash(Data(paths.joined(separator: "\n").utf8)),
                        sourceAppName: app?.localizedName, sourceBundleID: app?.bundleIdentifier))
    }

    func addImage(pngData: Data, app: NSRunningApplication?) {
        let hash = Self.hash(pngData)
        if bringToFront(hash: hash) { return }
        let name = "\(UUID().uuidString).png"
        do {
            try pngData.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("ShotPaste: could not store image: \(error)")
            return
        }
        insert(ClipItem(kind: .image, imageName: name, contentHash: hash,
                        sourceAppName: app?.localizedName, sourceBundleID: app?.bundleIdentifier))
    }

    private func insert(_ item: ClipItem) {
        if bringToFront(hash: item.contentHash) { return }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    /// If the same content is already stored, move it to the front instead of duplicating.
    private func bringToFront(hash: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.contentHash == hash }) else { return false }
        var existing = items.remove(at: index)
        existing.date = Date()
        items.insert(existing, at: 0)
        scheduleSave()
        return true
    }

    // MARK: - Editing

    func touch(_ item: ClipItem) {
        _ = bringToFront(hash: item.contentHash)
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        scheduleSave()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        deleteFiles(of: item)
        scheduleSave()
    }

    func clear(keepPinned: Bool) {
        let removed = items.filter { !keepPinned || !$0.pinned }
        items.removeAll { !keepPinned || !$0.pinned }
        removed.forEach { deleteFiles(of: $0) }
        scheduleSave()
    }

    private func trim() {
        let limit = Preferences.historyLimit
        var unpinnedSeen = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.pinned {
                kept.append(item)
            } else if unpinnedSeen < limit {
                unpinnedSeen += 1
                kept.append(item)
            } else {
                deleteFiles(of: item)
            }
        }
        items = kept
    }

    private func deleteFiles(of item: ClipItem) {
        if let url = imageURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Reading back

    func imageURL(for item: ClipItem) -> URL? {
        item.imageName.map { imagesDirectory.appendingPathComponent($0) }
    }

    /// Puts the item back on the system pasteboard.
    func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .link:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let url = imageURL(for: item), let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation {
                    pb.setData(tiff, forType: .tiff)
                }
            }
        case .file:
            pb.writeObjects(item.fileURLs as [NSURL])
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: historyFile) else { return }
        do {
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            NSLog("ShotPaste: could not read history: \(error)")
        }
    }

    /// Coalesces bursts of changes into a single write.
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        runAfter(0.5) { [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            let snapshot = self.items
            let file = self.historyFile
            Task.detached(priority: .utility) {
                do {
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: file, options: .atomic)
                } catch {
                    NSLog("ShotPaste: could not save history: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }
}

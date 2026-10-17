import AppKit
import CryptoKit

/// Persists clipboard history to
/// ~/Library/Application Support/Marquee/{history.json, images/}.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var categories: [ClipCategory] = []

    let directory: URL
    let imagesDirectory: URL
    private var historyFile: URL { directory.appendingPathComponent("history.json") }
    private var categoriesFile: URL { directory.appendingPathComponent("categories.json") }
    private var saveScheduled = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = support.appendingPathComponent("Marquee", isDirectory: true)
        // The app was called ShotPaste up to 0.2.0; carry its history over once.
        let legacy = support.appendingPathComponent("ShotPaste", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: directory)
        }
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
            NSLog("Marquee: could not store image: \(error)")
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

    /// Removes every item copied from an app (after the user chooses to ignore it).
    func removeItems(fromApp bundleID: String) {
        let removed = items.filter { $0.sourceBundleID == bundleID }
        items.removeAll { $0.sourceBundleID == bundleID }
        removed.forEach { deleteFiles(of: $0) }
        scheduleSave()
    }

    /// Clears history. With `keepPinned`, pinned items and items in a category stay.
    func clear(keepPinned: Bool) {
        let removed = items.filter { !keepPinned || !$0.isKept }
        items.removeAll { !keepPinned || !$0.isKept }
        removed.forEach { deleteFiles(of: $0) }
        scheduleSave()
    }

    private func trim() {
        let limit = Preferences.historyLimit
        var unpinnedSeen = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.isKept {
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

    // MARK: - Categories

    @discardableResult
    func addCategory(name: String, tint: ClipCategory.Tint) -> ClipCategory {
        let category = ClipCategory(name: Self.cleanName(name), tint: tint)
        categories.append(category)
        saveCategories()
        return category
    }

    func updateCategory(_ id: UUID, name: String, tint: ClipCategory.Tint) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = Self.cleanName(name)
        categories[index].tint = tint
        saveCategories()
    }

    /// Deletes the category. Its items stay in history, just without a category.
    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for index in items.indices where items[index].categoryID == id {
            items[index].categoryID = nil
        }
        trim()
        saveCategories()
        scheduleSave()
    }

    /// Puts an item in a category, or takes it out with `nil`.
    func setCategory(_ id: UUID?, for item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].categoryID = id.flatMap { id in categories.contains { $0.id == id } ? id : nil }
        scheduleSave()
    }

    func category(for item: ClipItem) -> ClipCategory? {
        item.categoryID.flatMap { id in categories.first { $0.id == id } }
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(40))
    }

    private func saveCategories() {
        do {
            try JSONEncoder().encode(categories).write(to: categoriesFile, options: .atomic)
        } catch {
            NSLog("Marquee: could not save categories: \(error)")
        }
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
        if let data = try? Data(contentsOf: categoriesFile),
           let decoded = try? JSONDecoder().decode([ClipCategory].self, from: data) {
            categories = decoded
        }
        guard let data = try? Data(contentsOf: historyFile) else { return }
        do {
            items = try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            NSLog("Marquee: could not read history: \(error)")
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
                    NSLog("Marquee: could not save history: \(error)")
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

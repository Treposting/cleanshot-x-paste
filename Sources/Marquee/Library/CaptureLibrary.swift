import AppKit
import Combine

struct LibraryItem: Codable, Identifiable, Hashable {
    var id: UUID
    var fileName: String
    /// Poster frame for recordings.
    var posterName: String?
    var isVideo: Bool
    var date: Date
}

/// Keeps a copy of recent screenshots and recordings in
/// ~/Library/Application Support/Marquee/Library, so the Marquee window can show them.
@MainActor
final class CaptureLibrary: ObservableObject {
    static let shared = CaptureLibrary()
    static let limit = 300

    @Published private(set) var items: [LibraryItem] = []
    /// Bumps when a file changes in place (e.g. after annotating), so thumbnails reload.
    @Published private(set) var revision = 0

    let directory: URL
    private var indexFile: URL { directory.appendingPathComponent("library.json") }
    private var editing: [UUID: AnyCancellable] = [:]

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = support.appendingPathComponent("Marquee/Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Adding

    func add(_ capture: Capture) {
        guard Preferences.keepLibrary else { return }
        let id = UUID()
        let ext = capture.isVideo ? "mp4" : "png"
        let fileName = "\(id.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: capture.url, to: destination)
        } catch {
            NSLog("Marquee: couldn't add capture to library: \(error)")
            return
        }
        var posterName: String?
        if capture.isVideo, let png = capture.image.pngData {
            let name = "\(id.uuidString)-poster.png"
            if (try? png.write(to: directory.appendingPathComponent(name), options: .atomic)) != nil {
                posterName = name
            }
        }
        items.insert(LibraryItem(id: id, fileName: fileName, posterName: posterName, isVideo: capture.isVideo, date: capture.date), at: 0)
        trim()
        save()
    }

    // MARK: - Files

    func fileURL(for item: LibraryItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    /// The image to show for an item: the screenshot itself, or a recording's poster frame.
    func previewURL(for item: LibraryItem) -> URL? {
        if item.isVideo {
            return item.posterName.map { directory.appendingPathComponent($0) }
        }
        return fileURL(for: item)
    }

    // MARK: - Actions

    func open(_ item: LibraryItem) {
        NSWorkspace.shared.open(fileURL(for: item))
    }

    func copy(_ item: LibraryItem) {
        let url = fileURL(for: item)
        if item.isVideo {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([url as NSURL])
        } else if let image = NSImage(contentsOf: url) {
            image.copyToPasteboard()
        }
        Toast.show(item.isVideo ? "Recording copied" : "Screenshot copied")
    }

    func reveal(_ item: LibraryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: item)])
    }

    func saveToFolder(_ item: LibraryItem) {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = Capture.uniqueURL(in: folder, date: item.date, ext: item.isVideo ? "mp4" : "png")
        do {
            try FileManager.default.copyItem(at: fileURL(for: item), to: destination)
            Toast.show("Saved to \(folder.lastPathComponent)")
        } catch {
            Toast.show("Couldn't save: \(error.localizedDescription)")
        }
    }

    /// Opens the annotation editor; edits are written back into the library file.
    func annotate(_ item: LibraryItem) {
        guard !item.isVideo, let image = NSImage(contentsOf: fileURL(for: item)) else { return }
        let capture = Capture(url: fileURL(for: item), image: image)
        editing[item.id] = capture.$image.dropFirst().sink { [weak self] _ in
            self?.revision += 1
        }
        QuickAccessManager.shared.openEditor(for: capture)
    }

    func remove(_ item: LibraryItem) {
        items.removeAll { $0.id == item.id }
        deleteFiles(of: item)
        save()
    }

    func clear() {
        items.forEach { deleteFiles(of: $0) }
        items.removeAll()
        save()
    }

    // MARK: - Storage

    private func trim() {
        guard items.count > Self.limit else { return }
        let removed = items[Self.limit...]
        removed.forEach { deleteFiles(of: $0) }
        items.removeLast(items.count - Self.limit)
    }

    private func deleteFiles(of item: LibraryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        if let poster = item.posterName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(poster))
        }
        editing[item.id] = nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexFile, options: .atomic)
    }
}

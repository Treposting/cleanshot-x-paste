import AppKit

/// One screenshot that is alive in the Quick Access overlay / editor.
@MainActor
final class Capture: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let date = Date()
    @Published private(set) var image: NSImage

    init(url: URL, image: NSImage) {
        self.url = url
        self.image = image
    }

    /// Replace the image (e.g. after annotating) and keep the temp file in sync so
    /// drag & drop hands out the edited version.
    func update(image: NSImage) {
        self.image = image
        if let data = image.pngData {
            try? data.write(to: url, options: .atomic)
        }
    }

    func copyToPasteboard() {
        image.copyToPasteboard()
    }

    /// Saves into the configured screenshots folder and returns the destination.
    @discardableResult
    func save() -> URL? {
        let folder = Preferences.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var dest = folder.appendingPathComponent(Capture.fileName(for: date))
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent(Capture.fileName(for: date, suffix: " (\(n))"))
            n += 1
        }
        guard let data = image.pngData else { return nil }
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            NSLog("ShotPaste: save failed: \(error)")
            return nil
        }
    }

    static func fileName(for date: Date, suffix: String = "") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "ShotPaste \(f.string(from: date))\(suffix).png"
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Ratio between pixels and points (2 on Retina screenshots).
    var pixelScale: CGFloat {
        guard size.width > 0, let rep = representations.first, rep.pixelsWide > 0 else { return 1 }
        return max(1, CGFloat(rep.pixelsWide) / size.width)
    }

    func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = pngData { pb.setData(png, forType: .png) }
        if let tiff = tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }
}

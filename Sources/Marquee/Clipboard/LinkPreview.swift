import AppKit
import CryptoKit
import ImageIO
@preconcurrency import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

/// A copied link's page title and images, read from its Open Graph tags and favicon by
/// LinkPresentation. Cached on disk so each link is fetched once.
struct LinkPreview: Codable, Equatable {
    var title: String?
    var hasImage: Bool
    var hasIcon: Bool
    var fetched: Date

    /// Pages without a title or image keep the plain link card.
    var isEmpty: Bool { title == nil && !hasImage }
}

/// Which links may be fetched for a preview: public http(s) sites only. Local and private
/// network addresses (routers, dev servers, NAS) are never contacted.
enum LinkPreviewPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty else { return false }
        if host == "localhost" { return false }
        for suffix in [".localhost", ".local", ".internal", ".lan", ".home.arpa"] where host.hasSuffix(suffix) {
            return false
        }
        if host.contains(":") { return !isPrivateIPv6(host) }
        if let octets = ipv4(host) { return !isPrivateIPv4(octets) }
        return host.contains(".")
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }

    private static func isPrivateIPv4(_ o: [Int]) -> Bool {
        o[0] == 0 || o[0] == 10 || o[0] == 127
            || (o[0] == 169 && o[1] == 254)
            || (o[0] == 172 && (16...31).contains(o[1]))
            || (o[0] == 192 && o[1] == 168)
            || (o[0] == 100 && (64...127).contains(o[1]))
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        host == "::1" || host == "::" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80")
    }
}

/// Fetches and caches link previews in ~/Library/Caches. Only links that are on screen are
/// fetched, and only while "Show link previews" is on.
@MainActor
final class LinkPreviewStore {
    static let shared = LinkPreviewStore()
    /// Links that had nothing to show are tried again after a day.
    private static let retryEmptyAfter: TimeInterval = 24 * 60 * 60
    private static let maxEntries = 400

    private let directory: URL
    private var previews: [String: LinkPreview] = [:]
    private let images = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<LinkPreview?, Never>] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = caches.appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "Marquee")/LinkPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// What's already known about a link, without touching the network.
    func cached(_ url: URL) -> LinkPreview? {
        let key = Self.key(url)
        if let preview = previews[key] { return preview }
        guard let data = try? Data(contentsOf: file(key, "json")),
              let preview = try? JSONDecoder().decode(LinkPreview.self, from: data) else { return nil }
        previews[key] = preview
        return preview
    }

    /// The preview for a link, fetching it if needed. Nil when previews are off, the link
    /// isn't allowed, or the page has nothing to show.
    func preview(for url: URL) async -> LinkPreview? {
        guard Preferences.linkPreviews, LinkPreviewPolicy.allows(url) else { return nil }
        if let cached = cached(url),
           !cached.isEmpty || Date().timeIntervalSince(cached.fetched) < Self.retryEmptyAfter {
            return cached.isEmpty ? nil : cached
        }
        let key = Self.key(url)
        if let running = inFlight[key] { return await running.value }
        let task = Task { [weak self] () -> LinkPreview? in
            let fetched = await Self.fetch(url)
            return self?.save(fetched, key: key)
        }
        inFlight[key] = task
        let preview = await task.value
        inFlight[key] = nil
        return preview?.isEmpty == false ? preview : nil
    }

    func image(for url: URL) -> NSImage? { loadImage(Self.key(url), "jpg") }
    func icon(for url: URL) -> NSImage? { loadImage(Self.key(url), "png") }

    // MARK: - Fetching

    /// Keeps the provider alive until its callbacks finish. It's only touched to start the fetch.
    private final class ProviderBox: @unchecked Sendable {
        let provider = LPMetadataProvider()
    }

    private struct Fetched: Sendable {
        var title: String?
        var image: Data?
        var icon: Data?
    }

    /// LinkPresentation reads Open Graph tags (og:title, og:image) and the favicon.
    /// Images are shrunk off the main thread before they're cached.
    nonisolated private static func fetch(_ url: URL) async -> Fetched {
        await withCheckedContinuation { continuation in
            let box = ProviderBox()
            box.provider.timeout = 10
            box.provider.startFetchingMetadata(for: url) { metadata, error in
                guard let metadata, error == nil else {
                    continuation.resume(returning: Fetched())
                    return
                }
                let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                loadData(metadata.imageProvider) { image in
                    loadData(metadata.iconProvider) { icon in
                        _ = box
                        continuation.resume(returning: Fetched(
                            title: title?.isEmpty == false ? title : nil,
                            image: image.flatMap { shrink($0, maxPixels: 640, type: .jpeg) },
                            icon: icon.flatMap { shrink($0, maxPixels: 64, type: .png) }
                        ))
                    }
                }
            }
        }
    }

    nonisolated private static func loadData(_ provider: NSItemProvider?, _ completion: @escaping (Data?) -> Void) {
        guard let provider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            completion(nil)
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in completion(data) }
    }

    nonisolated private static func shrink(_ data: Data, maxPixels: Int, type: UTType) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    // MARK: - Cache

    private func save(_ fetched: Fetched, key: String) -> LinkPreview {
        if let image = fetched.image { try? image.write(to: file(key, "jpg"), options: .atomic) }
        if let icon = fetched.icon { try? icon.write(to: file(key, "png"), options: .atomic) }
        let preview = LinkPreview(title: fetched.title, hasImage: fetched.image != nil,
                                  hasIcon: fetched.icon != nil, fetched: Date())
        if let data = try? JSONEncoder().encode(preview) {
            try? data.write(to: file(key, "json"), options: .atomic)
        }
        previews[key] = preview
        prune()
        return preview
    }

    /// Keeps the newest entries; older ones are fetched again if they come back on screen.
    private func prune() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter({ $0.pathExtension == "json" }), entries.count > Self.maxEntries else { return }
        let oldest = entries.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }.prefix(entries.count - Self.maxEntries)
        for entry in oldest {
            let key = entry.deletingPathExtension().lastPathComponent
            for ext in ["json", "jpg", "png"] { try? fm.removeItem(at: file(key, ext)) }
            previews[key] = nil
            images.removeObject(forKey: "\(key).jpg" as NSString)
            images.removeObject(forKey: "\(key).png" as NSString)
        }
    }

    private func loadImage(_ key: String, _ ext: String) -> NSImage? {
        let name = "\(key).\(ext)" as NSString
        if let cached = images.object(forKey: name) { return cached }
        guard let image = NSImage(contentsOf: file(key, ext)) else { return nil }
        images.setObject(image, forKey: name)
        return image
    }

    private func file(_ key: String, _ ext: String) -> URL {
        directory.appendingPathComponent("\(key).\(ext)")
    }

    private static func key(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// A link card's body: the page's image, favicon and title when it has them, then the link.
/// Without a preview it's just the link, as before.
struct LinkCardContent: View {
    let url: URL
    let text: String
    @AppStorage(Preferences.Key.linkPreviews.rawValue) private var enabled = true
    @State private var preview: LinkPreview?
    @State private var image: NSImage?
    @State private var icon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
            }
            if let title = preview?.title {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(image == nil ? 5 : 2)
                }
            }
            Text(text)
                .font(.system(size: preview == nil ? 12 : 11))
                .foregroundStyle(Color.accentColor)
                .lineLimit(preview == nil ? 6 : 1)
                .truncationMode(.middle)
        }
        .task(id: "\(text)|\(enabled)") { await load() }
    }

    private func load() async {
        guard enabled else {
            preview = nil; image = nil; icon = nil
            return
        }
        let store = LinkPreviewStore.shared
        // Show what's cached right away, then fetch if needed.
        if let cached = store.cached(url), !cached.isEmpty, LinkPreviewPolicy.allows(url) {
            apply(cached)
        }
        if let fetched = await store.preview(for: url) {
            apply(fetched)
        }
    }

    private func apply(_ preview: LinkPreview) {
        self.preview = preview
        image = preview.hasImage ? LinkPreviewStore.shared.image(for: url) : nil
        icon = preview.hasIcon ? LinkPreviewStore.shared.icon(for: url) : nil
    }
}

import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// What a copied file is, for choosing between a Quick Look preview and its icon.
enum FileMedia {
    case image, video

    init?(_ url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            self = .video
        } else {
            return nil
        }
    }
}

/// Quick Look thumbnails for copied files, made off the main thread and kept in memory.
@MainActor
final class FileThumbnails {
    static let shared = FileThumbnails()
    private let cache = NSCache<NSURL, NSImage>()

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        if let cached = cached(url) { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail
        )
        let cgImage: CGImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale,
                                                           height: CGFloat(cgImage.height) / scale))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// A copied image or video shown as a preview, with a play badge on videos.
/// Falls back to the file's icon while loading or if the file is gone.
struct FilePreview: View {
    let url: URL
    let media: FileMedia
    let fallbackIcon: NSImage?
    @State private var image: NSImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if media == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.5), in: Circle())
                        .accessibilityHidden(true)
                }
            } else if let fallbackIcon {
                Image(nsImage: fallbackIcon).resizable().frame(width: 56, height: 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = FileThumbnails.shared.cached(url)
            if image == nil {
                image = await FileThumbnails.shared.thumbnail(for: url, side: 220, scale: displayScale)
            }
        }
        .accessibilityLabel(media == .video ? "Video \(url.lastPathComponent)" : "Image \(url.lastPathComponent)")
    }
}

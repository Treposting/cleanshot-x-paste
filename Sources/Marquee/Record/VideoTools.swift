import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum VideoTools {
    /// First frame of a video, for the Quick Access thumbnail.
    @MainActor
    static func thumbnail(for url: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        let cg = result.image
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Converts a video to an animated, looping GIF.
    static func exportGIF(from video: URL, to destination: URL, fps: Double = 12, maxWidth: CGFloat = 960) async throws {
        let asset = AVURLAsset(url: video)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let frameCount = max(1, Int(duration * fps))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth * 4)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let gif = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { throw GIFError.cannotCreate }

        let fileProperties = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ] as CFDictionary
        let frameProperties = [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / fps],
        ] as CFDictionary
        CGImageDestinationSetProperties(gif, fileProperties)

        var previous: CGImage?
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                previous = result.image
            }
            // Repeat the previous frame if one can't be decoded, so the count stays right.
            guard let frame = previous else { throw GIFError.noFrames }
            CGImageDestinationAddImage(gif, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(gif) else { throw GIFError.cannotFinalize }
    }

    enum GIFError: LocalizedError {
        case cannotCreate, noFrames, cannotFinalize
        var errorDescription: String? { "Could not create the GIF." }
    }
}

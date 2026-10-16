import AppKit
import XCTest
@testable import Marquee

final class FilePreviewTests: XCTestCase {
    func testMediaKindFromExtension() {
        XCTAssertEqual(FileMedia(URL(fileURLWithPath: "/tmp/a.png")), .image)
        XCTAssertEqual(FileMedia(URL(fileURLWithPath: "/tmp/a.HEIC")), .image)
        XCTAssertEqual(FileMedia(URL(fileURLWithPath: "/tmp/a.mp4")), .video)
        XCTAssertEqual(FileMedia(URL(fileURLWithPath: "/tmp/a.mov")), .video)
        XCTAssertNil(FileMedia(URL(fileURLWithPath: "/tmp/a.pdf")))
        XCTAssertNil(FileMedia(URL(fileURLWithPath: "/tmp/a.zip")))
        XCTAssertNil(FileMedia(URL(fileURLWithPath: "/tmp/folder")))
    }

    @MainActor
    func testMakesAThumbnailForAnImageFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("marquee-preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)

        let image = await FileThumbnails.shared.thumbnail(for: url, side: 220, scale: 2)
        XCTAssertNotNil(image)
        XCTAssertNotNil(FileThumbnails.shared.cached(url))
        let missing = await FileThumbnails.shared.thumbnail(for: url.appendingPathExtension("gone"), side: 220, scale: 2)
        XCTAssertNil(missing)
    }
}

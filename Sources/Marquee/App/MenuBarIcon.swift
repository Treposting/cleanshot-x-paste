import AppKit

/// The menu-bar icon chosen in Settings: one of the built-in symbols or the user's own image.
@MainActor
enum MenuBarIcon {
    struct Preset: Identifiable {
        let symbol: String
        let title: String
        var id: String { symbol }
    }

    static let defaultSymbol = "camera.viewfinder"
    /// Stored as the choice when the user's own image is used.
    static let customChoice = "custom"
    static let didChange = Notification.Name("MarqueeMenuBarIconDidChange")

    static let presets: [Preset] = [
        Preset(symbol: "camera.viewfinder", title: "Viewfinder camera"),
        Preset(symbol: "viewfinder", title: "Viewfinder"),
        Preset(symbol: "camera", title: "Camera"),
        Preset(symbol: "camera.aperture", title: "Aperture"),
        Preset(symbol: "crop", title: "Crop"),
        Preset(symbol: "rectangle.dashed", title: "Dashed rectangle"),
        Preset(symbol: "scissors", title: "Scissors"),
        Preset(symbol: "ruler", title: "Ruler"),
        Preset(symbol: "eyedropper", title: "Eyedropper"),
        Preset(symbol: "record.circle", title: "Record"),
        Preset(symbol: "dot.viewfinder", title: "Focus"),
        Preset(symbol: "scope", title: "Scope"),
        Preset(symbol: "square.dashed", title: "Dashed square"),
        Preset(symbol: "circle.dashed", title: "Dashed circle"),
        Preset(symbol: "rectangle.dashed.badge.record", title: "Record area"),
        Preset(symbol: "photo", title: "Photo"),
        Preset(symbol: "doc.on.clipboard", title: "Clipboard"),
        Preset(symbol: "paperclip", title: "Paperclip"),
        Preset(symbol: "pencil.tip", title: "Pencil"),
        Preset(symbol: "wand.and.stars", title: "Magic wand"),
        Preset(symbol: "sparkles", title: "Sparkles"),
        Preset(symbol: "bolt", title: "Bolt"),
        Preset(symbol: "star", title: "Star"),
        Preset(symbol: "m.square", title: "M"),
    ]

    /// The user's image, copied here so it survives the original being moved or deleted.
    static var customImageURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Marquee/MenuBarIcon.png")
    }

    /// The icon to show now. Falls back to the default symbol if the custom image is missing.
    static var current: NSImage? {
        if Preferences.menuBarIcon == customChoice, let image = customImage() {
            return image
        }
        let symbol = presets.contains { $0.symbol == Preferences.menuBarIcon } ? Preferences.menuBarIcon : defaultSymbol
        // A symbol missing on an older macOS would leave the menu bar item blank.
        return NSImage(systemSymbolName: symbol, accessibilityDescription: "Marquee")
            ?? NSImage(systemSymbolName: defaultSymbol, accessibilityDescription: "Marquee")
    }

    static func select(_ symbol: String) {
        Preferences.menuBarIcon = symbol
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Copies an image file as a PNG and switches to it.
    static func useCustomImage(from url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url),
              let data = pngData(of: image, maxPixels: 64) else { return false }
        do {
            try FileManager.default.createDirectory(at: customImageURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: customImageURL, options: .atomic)
        } catch {
            return false
        }
        select(customChoice)
        return true
    }

    static var hasCustomImage: Bool { FileManager.default.fileExists(atPath: customImageURL.path) }

    /// The custom image sized for the menu bar (18 pt tall). Template images take the menu
    /// bar's color, so they suit simple dark shapes on a transparent background.
    static func customImage() -> NSImage? {
        guard let image = NSImage(contentsOf: customImageURL), image.size.height > 0 else { return nil }
        let height: CGFloat = 18
        let width = min(36, max(height, image.size.width * height / image.size.height))
        image.size = NSSize(width: width, height: height)
        image.isTemplate = Preferences.menuBarIconTemplate
        image.accessibilityDescription = "Marquee"
        return image
    }

    /// Redraws the image at most `maxPixels` tall, keeping its aspect ratio.
    private static func pngData(of image: NSImage, maxPixels: CGFloat) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxPixels / image.size.height, (maxPixels * 2) / image.size.width)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

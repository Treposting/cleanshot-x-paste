import AppKit

/// A color picked from the screen, stored as sRGB components (0…1).
struct PickedColor: Codable, Identifiable, Hashable {
    var id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var date = Date()

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    private var bytes: (Int, Int, Int) {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return (byte(red), byte(green), byte(blue))
    }

    var hex: String {
        let (r, g, b) = bytes
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgb: String {
        let (r, g, b) = bytes
        return "rgb(\(r), \(g), \(b))"
    }

    var hsl: String {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        var hue = 0.0, saturation = 0.0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch maxC {
            case red: hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
            case green: hue = 60 * ((blue - red) / delta + 2)
            default: hue = 60 * ((red - green) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    var swiftUI: String {
        String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
    }

    func string(in format: ColorFormat) -> String {
        switch format {
        case .hex: return hex
        case .rgb: return rgb
        case .hsl: return hsl
        case .swiftUI: return swiftUI
        }
    }
}

enum ColorFormat: String, CaseIterable, Identifiable, Codable {
    case hex = "HEX", rgb = "RGB", hsl = "HSL", swiftUI = "SwiftUI"
    var id: String { rawValue }
}

/// Picks colors with macOS's own magnifier (NSColorSampler) and keeps a short history.
@MainActor
final class ColorPickerController: ObservableObject {
    static let shared = ColorPickerController()
    static let historyLimit = 48

    @Published private(set) var history: [PickedColor] = []
    @Published var format: ColorFormat {
        didSet { UserDefaults.standard.set(format.rawValue, forKey: Self.formatKey) }
    }

    private static let historyKey = "colorHistory"
    private static let formatKey = "colorFormat"
    private var sampler: NSColorSampler?

    private init() {
        format = ColorFormat(rawValue: UserDefaults.standard.string(forKey: Self.formatKey) ?? "") ?? .hex
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([PickedColor].self, from: data) {
            history = decoded
        }
    }

    /// Shows the magnifier; the picked color is copied in the preferred format.
    ///
    /// The magnifier follows the pointer, but clicks and Esc only reach it while Marquee is
    /// the active app. Started from the menu bar, a global shortcut, or right after the Marquee
    /// window hides (which makes Marquee inactive), they went to another app instead and the
    /// screen seemed frozen. So Marquee activates first and waits until it is active.
    func pick() {
        guard sampler == nil else { return }
        let sampler = NSColorSampler()
        self.sampler = sampler
        NSApp.activate(ignoringOtherApps: true)
        whenActive(attempts: 20) { [weak self] in self?.show(sampler) }
    }

    private func whenActive(attempts: Int, _ work: @escaping @MainActor () -> Void) {
        if NSApp.isActive || attempts <= 0 {
            work()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        runAfter(0.05) { [weak self] in self?.whenActive(attempts: attempts - 1, work) }
    }

    private func show(_ sampler: NSColorSampler) {
        sampler.show { [weak self] color in
            Task { @MainActor in
                guard let self else { return }
                self.sampler = nil
                guard let color, let picked = PickedColor(color) else { return }
                self.history.removeAll { $0.hex == picked.hex }
                self.history.insert(picked, at: 0)
                if self.history.count > Self.historyLimit { self.history.removeLast(self.history.count - Self.historyLimit) }
                self.save()
                self.copy(picked)
            }
        }
    }

    func copy(_ color: PickedColor, as format: ColorFormat? = nil) {
        let text = color.string(in: format ?? self.format)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        Sounds.play(.copy)
        Toast.show("Copied \(text)")
    }

    func remove(_ color: PickedColor) {
        history.removeAll { $0.id == color.id }
        save()
    }

    func clear() {
        history.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }
}

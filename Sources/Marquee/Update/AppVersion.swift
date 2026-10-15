import Foundation

/// A dotted version like "0.3.0" or a tag like "v1.2". Pre-release suffixes ("-beta.1")
/// are ignored for ordering; GitHub's "latest release" never returns pre-releases anyway.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    static var current: AppVersion? {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    private func part(_ i: Int) -> Int { i < parts.count ? parts[i] : 0 }

    static func == (a: AppVersion, b: AppVersion) -> Bool {
        (0..<max(a.parts.count, b.parts.count)).allSatisfy { a.part($0) == b.part($0) }
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) where a.part(i) != b.part(i) {
            return a.part(i) < b.part(i)
        }
        return false
    }
}

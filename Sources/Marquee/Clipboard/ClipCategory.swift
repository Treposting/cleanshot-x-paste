import SwiftUI

/// A user-made category for clipboard items, like a Finder tag: a name and a color.
/// Items in a category are kept until they're removed from it, like pinned items.
struct ClipCategory: Codable, Identifiable, Hashable {
    /// The palette offered when making a category, matching Finder's tag colors plus a few more.
    enum Tint: String, Codable, CaseIterable, Identifiable {
        case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        var color: Color {
            switch self {
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .mint: return .mint
            case .teal: return .teal
            case .blue: return .blue
            case .indigo: return .indigo
            case .purple: return .purple
            case .pink: return .pink
            case .brown: return .brown
            case .gray: return .gray
            }
        }
    }

    var id: UUID
    var name: String
    var tint: Tint

    init(name: String, tint: Tint) {
        self.id = UUID()
        self.name = name
        self.tint = tint
    }
}

/// What the clipboard history shows: everything, one kind of item, pinned items, or a category.
enum ClipFilter: Hashable {
    case all, text, links, images, files, pinned
    case category(UUID)

    static let kinds: [ClipFilter] = [.all, .text, .links, .images, .files, .pinned]

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .links: return "Links"
        case .images: return "Images"
        case .files: return "Files"
        case .pinned: return "Pinned"
        case .category: return "Category"
        }
    }

    var symbol: String? {
        switch self {
        case .pinned: return "pin.fill"
        default: return nil
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text
        case .links: return item.kind == .link
        case .images: return item.kind == .image
        case .files: return item.kind == .file
        case .pinned: return item.pinned
        case .category(let id): return item.categoryID == id
        }
    }
}

extension ClipboardStore {
    /// Items for a filter and search text, in history order.
    func items(matching filter: ClipFilter, query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return items.filter { filter.matches($0) && (q.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(q)) }
    }
}

/// How long ago something was copied, without seconds: "Just now", "5 min ago", "2 hr ago",
/// "Yesterday", "3 days ago", then the date.
enum CopiedAge {
    static func text(since date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3600)) hr ago"
        default:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            if days <= 1 { return "Yesterday" }
            if days < 7 { return "\(days) days ago" }
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

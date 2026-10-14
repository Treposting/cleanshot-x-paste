import Foundation
import SwiftUI

struct ClipItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case text, link, image, file

        var label: String {
            switch self {
            case .text: return "Text"
            case .link: return "Link"
            case .image: return "Image"
            case .file: return "File"
            }
        }

        var color: Color {
            switch self {
            case .text: return .blue
            case .link: return .purple
            case .image: return .orange
            case .file: return .green
            }
        }
    }

    var id: UUID
    var kind: Kind
    /// Plain text for text/link items.
    var text: String?
    /// Absolute paths for file items.
    var filePaths: [String]?
    /// File name inside the store's images directory for image items.
    var imageName: String?
    /// SHA-256 of the content, used to de-duplicate.
    var contentHash: String
    var sourceAppName: String?
    var sourceBundleID: String?
    var date: Date
    var pinned: Bool

    init(kind: Kind, text: String? = nil, filePaths: [String]? = nil, imageName: String? = nil,
         contentHash: String, sourceAppName: String?, sourceBundleID: String?) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.filePaths = filePaths
        self.imageName = imageName
        self.contentHash = contentHash
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.date = Date()
        self.pinned = false
    }

    var fileURLs: [URL] { (filePaths ?? []).map { URL(fileURLWithPath: $0) } }

    /// Text that search matches against.
    var searchableText: String {
        [text, filePaths?.joined(separator: " "), sourceAppName]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

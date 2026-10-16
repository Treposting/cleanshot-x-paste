import AppKit
import SwiftUI

/// Clipboard history in the Marquee window: browse, search, copy, pin and delete.
@MainActor
struct ClipboardBrowserView: View {
    @ObservedObject var store: ClipboardStore
    let monitor: ClipboardMonitor?

    @AppStorage(Preferences.Key.monitorPaused.rawValue) private var paused = false
    @State private var query = ""
    @State private var filter: HistoryViewModel.Filter = .all
    @State private var thumbnails = ThumbnailCache()
    @State private var confirmClear = false

    private var items: [ClipItem] {
        store.items.filter { item in
            let kindMatches: Bool
            switch filter {
            case .all: kindMatches = true
            case .text: kindMatches = item.kind == .text
            case .links: kindMatches = item.kind == .link
            case .images: kindMatches = item.kind == .image
            case .files: kindMatches = item.kind == .file
            case .pinned: kindMatches = item.pinned
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            return kindMatches && (q.isEmpty || item.searchableText.localizedCaseInsensitiveContains(q))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Clipboard").font(.system(size: 20, weight: .bold))
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: 260)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Picker("Show", selection: $filter) {
                    ForEach(HistoryViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 400)
                Menu {
                    Toggle("Record clipboard history", isOn: Binding(get: { !paused }, set: { paused = !$0 }))
                    Divider()
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Clipboard options")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if paused {
                Label("Clipboard history is paused. New copies aren't recorded.", systemImage: "pause.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(query.isEmpty ? "Copy something and it shows up here" : "No matches")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Press ⇧⌘V anywhere to open the quick clipboard panel.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(items) { item in
                            ClipCard(
                                item: item,
                                index: 99,
                                selected: false,
                                thumbnail: thumbnail(for: item),
                                appIcon: thumbnails.appIcon(bundleID: item.sourceBundleID),
                                appColor: thumbnails.appColor(bundleID: item.sourceBundleID),
                                fileIcon: item.filePaths?.first.map { thumbnails.fileIcon(path: $0) }
                            )
                            .onTapGesture(count: 2) { copy(item) }
                            .contextMenu {
                                Button("Copy") { copy(item) }
                                Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                                Divider()
                                Button("Delete", role: .destructive) { store.remove(item) }
                            }
                            .help("Double-click to copy")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { store.clear(keepPinned: true) }
        } message: {
            Text("Pinned items are kept.")
        }
    }

    private func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image, let url = store.imageURL(for: item) else { return nil }
        return thumbnails.thumbnail(for: url)
    }

    private func copy(_ item: ClipItem) {
        store.writeToPasteboard(item)
        monitor?.ignoreCurrentContents()
        store.touch(item)
        Sounds.play(.copy)
        Toast.show("Copied")
    }
}

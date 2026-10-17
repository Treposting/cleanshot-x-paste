import AppKit
import SwiftUI

/// Clipboard history in the Marquee window: browse, search, copy, pin, sort into categories, delete.
@MainActor
struct ClipboardBrowserView: View {
    @ObservedObject var store: ClipboardStore
    let monitor: ClipboardMonitor?

    @AppStorage(Preferences.Key.monitorPaused.rawValue) private var paused = false
    @State private var query = ""
    @State private var filter: ClipFilter = .all
    @State private var draft: CategoryDraft?
    @State private var thumbnails = ThumbnailCache()
    @State private var confirmClear = false

    private var items: [ClipItem] {
        if case .category(let id) = filter, !store.categories.contains(where: { $0.id == id }) {
            return store.items(matching: .all, query: query)
        }
        return store.items(matching: filter, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Clipboard").font(.system(size: 20, weight: .bold))
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: 260)
                .frame(height: 30)
                .background(Color.primary.opacity(0.07), in: Capsule())
                Spacer()
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
            .padding(.top, 16)
            .padding(.bottom, 10)

            Group {
                if draft != nil {
                    CategoryEditor(draft: $draft, store: store) { category in filter = .category(category.id) }
                } else {
                    ClipFilterBar(selection: $filter, store: store, draft: $draft)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    Text(emptyTitle)
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
                                fileIcon: item.filePaths?.first.map { thumbnails.fileIcon(path: $0) },
                                category: store.category(for: item)
                            )
                            .onTapGesture(count: 2) { copy(item) }
                            .contextMenu {
                                Button("Copy") { copy(item) }
                                Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                                CategoryMenu(item: item, store: store, draft: $draft)
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
            Text("Pinned items and items in a category are kept.")
        }
    }

    private var emptyTitle: String {
        if !query.isEmpty { return "No matches" }
        if case .category = filter { return "Nothing in this category yet" }
        return "Copy something and it shows up here"
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

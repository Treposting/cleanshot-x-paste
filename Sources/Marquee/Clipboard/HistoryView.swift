import AppKit
import SwiftUI

@MainActor
struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    let thumbnails: ThumbnailCache
    var onPaste: (ClipItem) -> Void
    var onTogglePin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void

    @FocusState var searchFocused: Bool

    var body: some View {
        let items = model.visibleItems
        VStack(alignment: .leading, spacing: 10) {
            header(count: items.count)
            if items.isEmpty {
                emptyState
            } else {
                cards(items)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear { searchFocused = true }
        .onReceive(model.$focusToken) { _ in searchFocused = true }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 280)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            Picker("Filter", selection: $model.filter) {
                ForEach(HistoryViewModel.Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 420)

            Spacer()

            Text("\(count) items  ·  ↩ paste  ·  ⌘1–9 quick paste  ·  ⌘P pin  ·  ⌘⌫ delete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image, let url = model.store.imageURL(for: item) else { return nil }
        return thumbnails.thumbnail(for: url)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No matches" }
        if model.store.items.isEmpty && PasteboardAccess.status != .allowed {
            return "macOS is limiting Marquee's clipboard access, so copies may not be recorded.\nAllow it in Settings → Clipboard."
        }
        return "Copy something and it shows up here"
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 30))
            Text(emptyMessage)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCard(
                            item: item,
                            index: index,
                            selected: index == model.selection,
                            thumbnail: thumbnail(for: item),
                            appIcon: thumbnails.appIcon(bundleID: item.sourceBundleID),
                            fileIcon: item.filePaths?.first.map { thumbnails.fileIcon(path: $0) }
                        )
                        .id(item.id)
                        .onTapGesture(count: 2) { onPaste(item) }
                        .simultaneousGesture(TapGesture().onEnded { model.selection = index })
                        .contextMenu {
                            Button("Paste") { onPaste(item) }
                            Button(item.pinned ? "Unpin" : "Pin") { onTogglePin(item) }
                            Divider()
                            Button("Delete", role: .destructive) { onDelete(item) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selection) { newValue in
                guard items.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(items[newValue].id, anchor: .center)
                }
            }
        }
    }
}

@MainActor
struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let thumbnail: NSImage?
    let appIcon: NSImage?
    let fileIcon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.kind.label).font(.system(size: 13, weight: .semibold))
                    Text(item.date, style: .relative).font(.system(size: 10)).opacity(0.85)
                }
                Spacer()
                if let appIcon {
                    Image(nsImage: appIcon).resizable().frame(width: 30, height: 30)
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(item.kind.color.gradient)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)

            HStack {
                if item.pinned {
                    Image(systemName: "pin.fill")
                }
                Text(footer).lineLimit(1)
                Spacer()
                if index < 9 {
                    Text("⌘\(index + 1)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 230, height: 236)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 12))
                .lineLimit(9)
        case .link:
            Text(item.text ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .lineLimit(6)
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case .file:
            VStack(alignment: .leading, spacing: 6) {
                if let fileIcon {
                    Image(nsImage: fileIcon).resizable().frame(width: 56, height: 56)
                }
                ForEach(item.fileURLs.prefix(4), id: \.self) { url in
                    Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                }
                if item.fileURLs.count > 4 {
                    Text("+\(item.fileURLs.count - 4) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: String {
        switch item.kind {
        case .text, .link:
            return "\(item.text?.count ?? 0) characters"
        case .image:
            return item.sourceAppName ?? "Image"
        case .file:
            let n = item.filePaths?.count ?? 0
            return n == 1 ? "1 file" : "\(n) files"
        }
    }
}

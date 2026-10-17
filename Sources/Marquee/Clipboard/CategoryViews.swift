import SwiftUI

/// A category being made or edited. `id` is nil for a new one; `assign` is an item to put
/// in the new category once it's saved (from "Add to Category → New Category…").
struct CategoryDraft: Equatable {
    var id: UUID?
    var name: String
    var tint: ClipCategory.Tint
    var assign: UUID?

    static func new(assigning item: ClipItem? = nil, existing: [ClipCategory] = []) -> CategoryDraft {
        // Start on a color that isn't used yet.
        let used = Set(existing.map(\.tint))
        let tint = ClipCategory.Tint.allCases.first { !used.contains($0) } ?? .blue
        return CategoryDraft(id: nil, name: "", tint: tint, assign: item?.id)
    }

    static func editing(_ category: ClipCategory) -> CategoryDraft {
        CategoryDraft(id: category.id, name: category.name, tint: category.tint, assign: nil)
    }
}

/// Capsule chips for the kinds of item, Pinned, and each category, with + to make a category.
/// Right-click a category to edit or delete it.
@MainActor
struct ClipFilterBar: View {
    @Binding var selection: ClipFilter
    @ObservedObject var store: ClipboardStore
    @Binding var draft: CategoryDraft?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClipFilter.kinds, id: \.self) { filter in
                    FilterChip(title: filter.title, symbol: filter.symbol, tint: nil,
                               selected: selection == filter) { selection = filter }
                }
                if !store.categories.isEmpty {
                    Divider().frame(height: 16).padding(.horizontal, 4)
                }
                ForEach(store.categories) { category in
                    FilterChip(title: category.name, symbol: nil, tint: category.tint,
                               selected: selection == .category(category.id)) {
                        selection = .category(category.id)
                    }
                    .contextMenu {
                        Button("Edit…") { draft = .editing(category) }
                        Divider()
                        Button("Delete Category", role: .destructive) { delete(category) }
                    }
                }
                Button {
                    draft = .new(existing: store.categories)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.07), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("New category")
                .accessibilityLabel("New category")
            }
            .padding(.vertical, 1)
        }
    }

    private func delete(_ category: ClipCategory) {
        if selection == .category(category.id) { selection = .all }
        if draft?.id == category.id { draft = nil }
        store.deleteCategory(category.id)
    }
}

/// One capsule in the filter bar. Categories show their color as a dot, or fill it when selected.
private struct FilterChip: View {
    let title: String
    let symbol: String?
    let tint: ClipCategory.Tint?
    let selected: Bool
    let action: @MainActor () -> Void
    @State private var hovering = false

    private var fill: Color {
        if selected { return tint?.color ?? .accentColor }
        return Color.primary.opacity(hovering ? 0.11 : 0.07)
    }

    /// Yellow, mint and other light fills need dark text.
    private var selectedText: Color {
        switch tint {
        case .yellow, .mint: return .black.opacity(0.8)
        default: return .white
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let tint, !selected {
                    Circle().fill(tint.color).frame(width: 8, height: 8)
                }
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? selectedText : Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Inline editor for a new or existing category: name, color, and Save. Shown in place of the
/// filter bar so it works inside the clipboard panel, which closes when it loses focus.
@MainActor
struct CategoryEditor: View {
    @Binding var draft: CategoryDraft?
    @ObservedObject var store: ClipboardStore
    var onSaved: (ClipCategory) -> Void = { _ in }
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let current = draft {
            HStack(spacing: 10) {
                Circle().fill(current.tint.color).frame(width: 12, height: 12)
                TextField(current.id == nil ? "New category name" : "Category name", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($nameFocused)
                    .onSubmit(save)
                    .frame(width: 180)
                HStack(spacing: 5) {
                    ForEach(ClipCategory.Tint.allCases) { tint in
                        Button {
                            draft?.tint = tint
                        } label: {
                            Circle()
                                .fill(tint.color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(current.tint == tint ? 0.9 : 0),
                                                               lineWidth: 2).padding(-3))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(tint.name)
                        .accessibilityLabel(tint.name)
                        .accessibilityAddTraits(current.tint == tint ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
                Spacer(minLength: 8)
                if let id = current.id {
                    Button("Delete", role: .destructive) {
                        draft = nil
                        store.deleteCategory(id)
                    }
                    .glassButtonStyle()
                }
                Button("Cancel") { draft = nil }
                    .glassButtonStyle()
                Button(current.id == nil ? "Create" : "Save", action: save)
                    .glassButtonStyle(prominent: true)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .onAppear { nameFocused = true }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { draft?.name ?? "" }, set: { draft?.name = $0 })
    }

    private func save() {
        guard let current = draft else { return }
        if let id = current.id {
            store.updateCategory(id, name: current.name, tint: current.tint)
        } else {
            let category = store.addCategory(name: current.name, tint: current.tint)
            if let itemID = current.assign, let item = store.items.first(where: { $0.id == itemID }) {
                store.setCategory(category.id, for: item)
            }
            onSaved(category)
        }
        draft = nil
    }
}

/// "Add to Category" submenu for an item's context menu.
@MainActor
struct CategoryMenu: View {
    let item: ClipItem
    @ObservedObject var store: ClipboardStore
    @Binding var draft: CategoryDraft?

    var body: some View {
        Menu("Add to Category") {
            ForEach(store.categories) { category in
                Button {
                    store.setCategory(category.id, for: item)
                } label: {
                    if item.categoryID == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
            if !store.categories.isEmpty { Divider() }
            Button("New Category…") { draft = .new(assigning: item, existing: store.categories) }
        }
        if item.categoryID != nil {
            Button("Remove from Category") { store.setCategory(nil, for: item) }
        }
    }
}

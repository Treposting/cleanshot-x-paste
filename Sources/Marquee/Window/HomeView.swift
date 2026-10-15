import AppKit
import SwiftUI

extension ShortcutAction {
    var symbol: String {
        switch self {
        case .allInOne: return "square.grid.2x2"
        case .captureArea: return "rectangle.dashed"
        case .captureWindow: return "macwindow"
        case .captureFullscreen: return "display"
        case .captureTimed: return "timer"
        case .captureText: return "text.viewfinder"
        case .recordArea: return "record.circle"
        case .recordScreen: return "video.circle"
        case .measure: return "ruler"
        case .pickColor: return "eyedropper"
        case .clipboardHistory: return "list.clipboard"
        }
    }

    var subtitle: String {
        switch self {
        case .allInOne: return "Select an area, then choose what to do"
        case .captureArea: return "Drag over any part of the screen"
        case .captureWindow: return "Click a window to capture it"
        case .captureFullscreen: return "The display under the pointer"
        case .captureTimed: return "Full screen after 5 seconds"
        case .captureText: return "Select text anywhere and copy it"
        case .recordArea: return "Video of an area, with audio"
        case .recordScreen: return "Video of the whole display"
        case .measure: return "Distances and sizes on screen"
        case .pickColor: return "Copy any color on screen"
        case .clipboardHistory: return "Everything you've copied"
        }
    }

    /// Short name for tiles ("Area" rather than "Capture Area").
    var tileTitle: String {
        switch self {
        case .allInOne: return "All-in-One"
        case .captureArea: return "Area"
        case .captureWindow: return "Window"
        case .captureFullscreen: return "Full Screen"
        case .captureTimed: return "Self-Timer"
        case .captureText: return "Copy Text"
        case .recordArea: return "Record Area"
        case .recordScreen: return "Record Screen"
        case .measure: return "Measure"
        case .pickColor: return "Color Picker"
        case .clipboardHistory: return "Clipboard"
        }
    }
}

@MainActor
struct HomeView: View {
    @ObservedObject var navigation: MainNavigation
    @ObservedObject var library = CaptureLibrary.shared
    @StateObject private var permissions = PermissionsModel()
    @State private var shortcutsVersion = 0

    private struct ActionGroup: Identifiable {
        let title: String
        let actions: [ShortcutAction]
        var id: String { title }
    }

    private let groups: [ActionGroup] = [
        ActionGroup(title: "Capture", actions: [.allInOne, .captureArea, .captureWindow, .captureFullscreen, .captureTimed, .captureText]),
        ActionGroup(title: "Record", actions: [.recordArea, .recordScreen]),
        ActionGroup(title: "Tools", actions: [.measure, .pickColor, .clipboardHistory]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if !permissions.screenRecording {
                    PermissionBanner {
                        navigation.section = .permissions
                    }
                }

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(group.actions) { action in
                                ActionTile(action: action, version: shortcutsVersion)
                            }
                        }
                    }
                }

                if !library.items.isEmpty {
                    recent
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.didChange)) { _ in
            shortcutsVersion += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Marquee").font(.system(size: 26, weight: .bold))
                Text("Capture, record, measure, and keep everything you copy.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent captures")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All") { navigation.section = .library }
                    .buttonStyle(.link)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(library.items.prefix(8)) { item in
                        LibraryThumbnail(item: item, revision: library.revision)
                            .frame(width: 168, height: 105)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onTapGesture(count: 2) { library.open(item) }
                            .contextMenu { LibraryItemMenu(item: item) }
                            .help(item.date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
    }
}

private struct ActionTile: View {
    let action: ShortcutAction
    let version: Int
    @State private var hovering = false

    var body: some View {
        Button {
            AppModel.shared.perform(action)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(action == .recordArea || action == .recordScreen ? Color.red : Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    if let combo = ShortcutStore.combo(for: action) {
                        Text(combo.displayString)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.tileTitle).font(.system(size: 14, weight: .semibold))
                    Text(action.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.16 : 0.08))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(action.title)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
        .id(version)
    }
}

private struct PermissionBanner: View {
    let fix: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording isn't allowed yet").font(.system(size: 13, weight: .semibold))
                Text("Screenshots of other apps, recordings and Measure need it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fix…", action: fix).glassButtonStyle(prominent: true)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

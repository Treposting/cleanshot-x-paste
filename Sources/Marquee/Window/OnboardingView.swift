import AppKit
import SwiftUI

/// First-launch walkthrough: welcome → permissions → shortcuts → where Marquee lives.
@MainActor
struct OnboardingView: View {
    let finish: (_ openApp: Bool) -> Void

    @StateObject private var permissions = PermissionsModel()
    @State private var page = 0
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    switch page {
                    case 0: welcome
                    case 1: permissionsPage
                    case 2: shortcuts
                    default: done
                    }
                }
                .id(page)
                .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 44)
            .padding(.top, 48)

            footer
        }
        .frame(width: 680, height: 600)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.9), value: page)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = forward ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func go(_ delta: Int) {
        forward = delta > 0
        page = min(max(0, page + delta), pageCount - 1)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Welcome to Marquee").font(.system(size: 30, weight: .bold))
                Text("Screenshots, recordings, measuring, colors and clipboard history, all one shortcut away.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(symbol: "square.grid.2x2", title: "All-in-One", detail: "Select an area, then screenshot, record, copy its text or pin it.")
                FeatureRow(symbol: "record.circle", title: "Record with audio", detail: "Your microphone, your Mac's sound, or both.")
                FeatureRow(symbol: "ruler", title: "Measure and pick colors", detail: "Pixel-perfect sizes, distances and any color on screen.")
                FeatureRow(symbol: "list.clipboard", title: "Clipboard history", detail: "Everything you copy, searchable, a ⇧⌘V away.")
            }
            .frame(maxWidth: 460)
            .padding(.top, 6)
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Allow what Marquee needs", subtitle: "Screen Recording is the only one required. You can change these later in the Marquee window.")
            PermissionsList(model: permissions)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageTitle(title: "Pick your shortcuts", subtitle: "All-in-One does every capture from one shortcut. Add others only if you want them; you can change all of them later in Settings \u{2192} Shortcuts.")
            VStack(spacing: 6) {
                ForEach([ShortcutAction.allInOne, .captureArea, .recordArea, .measure, .pickColor, .clipboardHistory]) { action in
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 15))
                            .frame(width: 26)
                            .foregroundStyle(Color.accentColor)
                        Text(action.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        ShortcutRecorder(action: action)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.035), in: Page.tile)
                }
            }
            LaunchAtLoginToggle()
                .padding(.top, 4)
        }
    }

    private var done: some View {
        VStack(spacing: 22) {
            MenuBarIllustration()
                .padding(.top, 20)
            VStack(spacing: 8) {
                Text("Marquee lives in your menu bar").font(.system(size: 26, weight: .bold))
                Text("Click the icon for quick actions, or use a shortcut from anywhere. Open the Marquee window to browse your library, clipboard and colors, or to change settings.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(page + 1) of \(pageCount)")
            Spacer()
            if page > 0 && page < pageCount - 1 {
                Button("Back") { go(-1) }
                    .glassButtonStyle()
                    .controlSize(.large)
            }
            if page == pageCount - 1 {
                Button("Done") { finish(false) }
                    .glassButtonStyle()
                    .controlSize(.large)
                Button("Open Marquee") { finish(true) }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(page == 0 ? "Get Started" : "Continue") { go(1) }
                    .glassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }
}

private struct PageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .bold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: Page.tile)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

/// A small drawing of the menu bar with Marquee's icon highlighted.
private struct MenuBarIllustration: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75")
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6)))
            Text("Wed 9:41").font(.system(size: 13, weight: .medium))
        }
        .font(.system(size: 14))
        .padding(.horizontal, 18)
        .frame(height: 40)
        .glassSurface(Capsule())
        .accessibilityHidden(true)
    }
}

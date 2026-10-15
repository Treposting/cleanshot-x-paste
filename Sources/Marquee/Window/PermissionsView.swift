import AppKit
import AVFoundation
import SwiftUI

/// Live status of the macOS permissions Marquee uses.
@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var screenRecording = false
    @Published private(set) var microphone: AVAuthorizationStatus = .notDetermined
    @Published private(set) var accessibility = false
    @Published private(set) var clipboard: PasteboardAccess.Status = .allowed

    init() { refresh() }

    func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibility = AXIsProcessTrusted()
        clipboard = PasteboardAccess.status
    }

    var allRequiredGranted: Bool { screenRecording }

    func requestScreenRecording() {
        // Shows the system prompt the first time; afterwards macOS only allows changing it in Settings.
        if !CGRequestScreenCaptureAccess() {
            Self.openPrivacyPane("Privacy_ScreenCapture")
        }
        refresh()
    }

    func requestMicrophone() {
        switch microphone {
        case .notDetermined:
            Task {
                _ = await MicrophoneCapture.requestAccess()
                refresh()
            }
        default:
            Self.openPrivacyPane("Privacy_Microphone")
        }
    }

    func requestAccessibility() {
        Paster.requestAccess()
        refresh()
    }

    /// macOS keeps permission entries from earlier builds. When those were signed differently
    /// (ad-hoc builds before releases had a stable certificate), the switch in System Settings
    /// is on but doesn't apply to this build. Removing Marquee's entries lets macOS ask again.
    func repair() {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.treposting.marquee"
        var services: [String] = []
        if !screenRecording { services.append("ScreenCapture") }
        if !accessibility { services.append("Accessibility") }
        if microphone == .denied { services.append("Microphone") }
        for service in services {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", service, bundleID]
            try? task.run()
            task.waitUntilExit()
        }
        if !screenRecording { _ = CGRequestScreenCaptureAccess() }
        if !accessibility { Paster.requestAccess() }
        refresh()
    }

    /// Screen Recording only takes effect after Marquee restarts.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Rows for each permission with its status and a button to fix it.
@MainActor
struct PermissionsList: View {
    @ObservedObject var model: PermissionsModel
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            PermissionRow(
                symbol: "rectangle.dashed.badge.record",
                title: "Screen Recording",
                detail: "Needed for screenshots of other apps, screen recording and Measure. After allowing it, quit and reopen Marquee.",
                state: model.screenRecording ? .granted : .needed,
                buttonTitle: "Allow…",
                action: { model.requestScreenRecording() }
            )
            PermissionRow(
                symbol: "mic",
                title: "Microphone",
                detail: "Only used when you turn on a microphone in the recording toolbar.",
                state: model.microphone == .authorized ? .granted : (model.microphone == .notDetermined ? .optional : .blocked),
                buttonTitle: model.microphone == .notDetermined ? "Allow…" : "Open Settings",
                action: { model.requestMicrophone() }
            )
            PermissionRow(
                symbol: "accessibility",
                title: "Accessibility",
                detail: "Lets Marquee paste clipboard history straight into the app you're using. Without it, items are copied and you press ⌘V.",
                state: model.accessibility ? .granted : .optional,
                buttonTitle: "Allow…",
                action: { model.requestAccessibility() }
            )
            PermissionRow(
                symbol: "doc.on.clipboard",
                title: "Clipboard access",
                detail: "Clipboard history reads what you copy. If macOS asks or blocks this, choose Always Allow for Marquee in Privacy & Security.",
                state: model.clipboard == .allowed ? .granted : .needed,
                buttonTitle: "Open Settings",
                action: { PasteboardAccess.openPrivacySettings() }
            )
            if !model.screenRecording || !model.accessibility {
                RepairCard(model: model)
            }
        }
        .onReceive(poll) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

/// Help for the common case: the switch is on in System Settings, but Marquee still asks.
@MainActor
private struct RepairCard: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Already allowed, but still shown as missing?")
                    .font(.system(size: 13, weight: .semibold))
                Text("macOS may be holding an entry from an older version of Marquee. Fix Permissions removes it and asks again: turn Marquee on, then restart it. Screen Recording always needs a restart.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(spacing: 6) {
                Button("Fix Permissions") { model.repair() }
                    .glassButtonStyle(prominent: true)
                Button("Restart Marquee") { PermissionsModel.relaunch() }
                    .glassButtonStyle()
            }
            .controlSize(.regular)
            .fixedSize()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.25)))
    }
}

private struct PermissionRow: View {
    enum Status { case granted, needed, optional, blocked }

    let symbol: String
    let title: String
    let detail: String
    let state: Status
    let buttonTitle: String
    let action: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    StatusPill(state: state)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if state != .granted {
                Button(buttonTitle, action: action)
                    .glassButtonStyle(prominent: state == .needed)
                    .controlSize(.regular)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Allowed")
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct StatusPill: View {
    let state: PermissionRow.Status

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var label: String {
        switch state {
        case .granted: return "Allowed"
        case .needed: return "Needed"
        case .optional: return "Optional"
        case .blocked: return "Blocked"
        }
    }

    private var color: Color {
        switch state {
        case .granted: return .green
        case .needed: return .orange
        case .optional: return .secondary
        case .blocked: return .red
        }
    }
}

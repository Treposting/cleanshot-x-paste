import AppKit
import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    var body: some View {
        TabView {
            CaptureSettings().tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            RecordingSettings().tabItem { Label("Recording", systemImage: "record.circle") }
            ClipboardSettings().tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}

@MainActor
private struct CaptureSettings: View {
    @AppStorage(Preferences.Key.showOverlay.rawValue) private var showOverlay = true
    @AppStorage(Preferences.Key.copyAfterCapture.rawValue) private var copyAfterCapture = true
    @AppStorage(Preferences.Key.saveAfterCapture.rawValue) private var saveAfterCapture = false
    @AppStorage(Preferences.Key.playSound.rawValue) private var playSound = true
    @AppStorage(Preferences.Key.windowShadow.rawValue) private var windowShadow = true
    @AppStorage(Preferences.Key.overlayTimeout.rawValue) private var overlayTimeout = 0
    @AppStorage(Preferences.Key.saveFolder.rawValue) private var saveFolder = Preferences.defaultSaveFolder.path

    var body: some View {
        Form {
            Section("After capture") {
                Toggle("Show Quick Access overlay", isOn: $showOverlay)
                Picker("Hide overlay after", selection: $overlayTimeout) {
                    Text("Never").tag(0)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                }
                .disabled(!showOverlay)
                Toggle("Copy to clipboard", isOn: $copyAfterCapture)
                Toggle("Save to folder", isOn: $saveAfterCapture)
            }
            Section("General") {
                Toggle("Play shutter sound", isOn: $playSound)
                Toggle("Include window shadow", isOn: $windowShadow)
                HStack {
                    Text("Save to")
                    Spacer()
                    Text((saveFolder as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
                LaunchAtLoginToggle()
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: saveFolder)
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}

@MainActor
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Marquee: launch at login failed: \(error)")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
    }
}

@MainActor
private struct ClipboardSettings: View {
    @AppStorage(Preferences.Key.historyLimit.rawValue) private var historyLimit = 500
    @AppStorage(Preferences.Key.autoPaste.rawValue) private var autoPaste = true
    @AppStorage(Preferences.Key.monitorPaused.rawValue) private var paused = false
    @State private var trusted = Paster.isTrusted

    var body: some View {
        Form {
            Section("History") {
                Toggle("Record clipboard history", isOn: Binding(get: { !paused }, set: { paused = !$0 }))
                Picker("Keep", selection: $historyLimit) {
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("1,000 items").tag(1000)
                    Text("5,000 items").tag(5000)
                }
                Text("Pinned items are never removed. Items marked as concealed by password managers are never recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pasting") {
                Toggle("Paste directly into the active app", isOn: $autoPaste)
                HStack {
                    Text(trusted ? "Accessibility access granted" : "Needs Accessibility access")
                        .foregroundStyle(trusted ? Color.secondary : Color.orange)
                    Spacer()
                    if !trusted {
                        Button("Grant…") {
                            Paster.requestAccess()
                            trusted = Paster.isTrusted
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = Paster.isTrusted }
    }
}

@MainActor
private struct RecordingSettings: View {
    @AppStorage(Preferences.Key.recordFPS.rawValue) private var fps = 30
    @AppStorage(Preferences.Key.recordShowCursor.rawValue) private var showCursor = true
    @AppStorage(Preferences.Key.recordAudio.rawValue) private var recordAudio = false

    var body: some View {
        Form {
            Section("Video") {
                Picker("Frame rate", selection: $fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Toggle("Show mouse cursor", isOn: $showCursor)
                Toggle("Record computer audio", isOn: $recordAudio)
            }
            Text("Recordings are saved as H.264 MP4. Use \u{201C}Save as GIF\u{201D} in the overlay to export a GIF. Click the red stop button in the menu bar (or press the record shortcut again) to finish.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct ShortcutsSettings: View {
    var body: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        ShortcutRecorder(action: action)
                    }
                }
            }
            HStack {
                Text("Click a shortcut and press new keys. \u{232B} removes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { ShortcutStore.resetAll() }
            }
        }
        .formStyle(.grouped)
    }
}

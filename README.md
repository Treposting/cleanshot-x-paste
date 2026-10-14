# ShotPaste

A free, open-source macOS menu-bar app that combines two things:

- **Screenshots & screen recording like CleanShot X**: area/window/fullscreen capture, MP4 recording with GIF export, a Quick Access overlay, an annotation editor, pin-to-screen and OCR.
- **Clipboard history like Paste**: everything you copy, searchable in a bottom panel, one keystroke to paste it back.

This is a clean-room reimplementation built only on public Apple APIs. It contains no code or assets from CleanShot X or Paste. See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for how those apps work and how each feature maps to macOS APIs.

## Features

| | |
|---|---|
| **Capture area / window / fullscreen** | Native crosshair UI. Space toggles window mode, Esc cancels. Fullscreen captures the display under the mouse. |
| **Self-timer** | Fullscreen capture after 5 s. |
| **Screen recording** | Record an area or the whole screen to MP4 (H.264, 30/60 fps, optional computer audio and cursor). A red stop button with a timer sits in the menu bar while recording. |
| **GIF export** | One click in the overlay turns a recording into a looping GIF. |
| **Capture text (OCR)** | Select an area and the recognized text goes straight to your clipboard (Apple Vision, runs on device). |
| **Quick Access overlay** | A thumbnail in the corner after every capture or recording: copy, save, annotate, pin, open, or **drag it straight into Slack, Mail, Finder…** |
| **Annotate** | Arrow, rectangle, ellipse, pen, highlighter, text, numbered steps, and pixelate (to hide secrets). Includes undo/redo, copy and save. |
| **Pin to screen** | Keep a screenshot floating above everything. Drag to move, scroll to fade, double-click or Esc to close. |
| **Clipboard history** | Text, links, images and files, with source-app icons. Search, filters, pinning and de-duplication. Persists across restarts. |
| **Paste directly** | Pick an item and it's pasted into the app you were in. |
| **Privacy** | Skips anything password managers mark as concealed or transient ([nspasteboard.org](http://nspasteboard.org)). History can be paused. Nothing leaves your Mac. |

## Shortcuts

All shortcuts can be changed in **Settings → Shortcuts**. Click a shortcut and press new keys. ⌫ removes it, and ↺ restores the default. These are the defaults:

| Action | Default |
|---|---|
| Capture area | ⌥⇧⌘4 |
| Capture window | ⌥⇧⌘5 |
| Capture fullscreen | ⌥⇧⌘3 |
| Capture fullscreen in 5 s | none |
| Capture text (OCR) | ⌥⇧⌘2 |
| Record area (press again to stop) | ⌥⇧⌘6 |
| Record screen (press again to stop) | ⌥⇧⌘7 |
| Clipboard history | ⇧⌘V |

In the history panel:

- ← → to select
- ↩ to paste
- ⌘1–⌘9 to quick-paste
- ⌘P to pin
- ⌘⌫ to delete
- Esc to close
- Typing searches

## Install

1. Download the latest `ShotPaste-x.y.z.dmg` from [Releases](../../releases). For untagged builds, use the `ShotPaste-dmg` artifact of any [Actions run](../../actions).
2. Open the DMG and drag **ShotPaste** into **Applications**.
3. The app isn't notarized by Apple, so the first launch needs one of these:
   - **right-click → Open**, or
   - run `xattr -dr com.apple.quarantine /Applications/ShotPaste.app`.

The DMG is universal: it runs on Apple Silicon and Intel Macs with macOS 13 or later.

## Build from source

Requires macOS 13+ and Xcode 15+ (or the Swift 5.9+ command-line tools).

```sh
make run        # builds build/ShotPaste.app and opens it
make install    # copies it to /Applications
make dmg        # universal build → build/ShotPaste-<version>.dmg
```

Or open `Package.swift` in Xcode and press Run.

### Publishing a release

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, then push a tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

CI builds the DMG and attaches it to a new GitHub Release.

### Permissions

macOS asks for two permissions the first time you use these features:

- **Screen Recording** (listed as *Screen & System Audio Recording*). Needed for screenshots of other apps and for video recording. Grant it, then quit and reopen ShotPaste.
- **Accessibility.** Only needed for "paste directly" (ShotPaste presses ⌘V for you). Without it, items are copied and you press ⌘V yourself.

The build script signs ad hoc, which changes the signature on every build, so macOS may ask again after a rebuild. To avoid that, sign with a stable identity: `SIGN_IDENTITY="Your Cert" make app`.

## Project layout

```
Sources/ShotPaste/
  App/        entry point, menu bar, global hotkeys, preferences
  Capture/    screencapture driver, Quick Access overlay, pinned windows, OCR
  Record/     ScreenCaptureKit recorder, MP4 writer, area selector, GIF export
  Annotate/   annotation model, renderer, editor window
  Clipboard/  pasteboard monitor, persistent store, history panel, auto-paste
  UI/         toast HUD, settings
```

## Roadmap

- [x] Screen recording (MP4 + GIF) via ScreenCaptureKit
- [x] Customizable shortcuts
- [x] DMG installer
- [ ] Microphone audio and webcam overlay in recordings
- [ ] Scrolling capture
- [ ] Notarized releases
- [ ] Custom pinboards and rich text (RTF/HTML) in history
- [ ] Background/padding "beautify" for screenshots
- [ ] Exclude specific apps from clipboard history

## License

MIT

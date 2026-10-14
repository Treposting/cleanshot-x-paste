# ShotPaste

A free, open-source macOS menu-bar app that combines two things:

- **Screenshots like CleanShot X**: area/window/fullscreen capture, a Quick Access overlay, an annotation editor, pin-to-screen and OCR.
- **Clipboard history like Paste**: everything you copy, searchable in a bottom panel, one keystroke to paste it back.

This is a clean-room reimplementation built only on public Apple APIs. It contains no code or assets from CleanShot X or Paste. See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for how those apps work and how each feature maps to macOS APIs.

## Features

| | |
|---|---|
| **Capture area / window / fullscreen** | Native crosshair UI. Space toggles window mode, Esc cancels. Fullscreen captures the display under the mouse. |
| **Self-timer** | Fullscreen capture after 5 s. |
| **Capture text (OCR)** | Select an area and the recognized text goes straight to your clipboard (Apple Vision, runs on device). |
| **Quick Access overlay** | A thumbnail in the corner after every capture: copy, save, annotate, pin, or **drag it straight into Slack, Mail, Finder…** |
| **Annotate** | Arrow, rectangle, ellipse, pen, highlighter, text, numbered steps, and pixelate (to hide secrets). Includes undo/redo, copy and save. |
| **Pin to screen** | Keep a screenshot floating above everything. Drag to move, scroll to fade, double-click or Esc to close. |
| **Clipboard history** | Text, links, images and files, with source-app icons. Search, filters, pinning and de-duplication. Persists across restarts. |
| **Paste directly** | Pick an item and it's pasted into the app you were in. |
| **Privacy** | Skips anything password managers mark as concealed or transient ([nspasteboard.org](http://nspasteboard.org)). History can be paused. Nothing leaves your Mac. |

## Shortcuts

| Action | Shortcut |
|---|---|
| Capture area | ⌥⇧⌘4 |
| Capture window | ⌥⇧⌘5 |
| Capture fullscreen | ⌥⇧⌘3 |
| Capture text (OCR) | ⌥⇧⌘2 |
| Clipboard history | ⇧⌘V |

In the history panel:

- ← → to select
- ↩ to paste
- ⌘1–⌘9 to quick-paste
- ⌘P to pin
- ⌘⌫ to delete
- Esc to close
- Typing searches

## Build & run

Requires macOS 13+ and Xcode 15+ (or the Swift 5.9+ command-line tools).

```sh
make run        # builds build/ShotPaste.app and opens it
make install    # copies it to /Applications
```

Or open `Package.swift` in Xcode and press Run.

Every push is also built by GitHub Actions. You can download `ShotPaste.zip` from the workflow run's artifacts.

### Permissions

macOS asks for two permissions the first time you use these features:

- **Screen Recording.** Needed to capture other apps' windows. Grant it, then quit and reopen ShotPaste.
- **Accessibility.** Only needed for "paste directly" (ShotPaste presses ⌘V for you). Without it, items are copied and you press ⌘V yourself.

The build script signs ad hoc, which changes the signature on every build, so macOS may ask again after a rebuild. To avoid that, sign with a stable identity: `SIGN_IDENTITY="Your Cert" make app`.

## Project layout

```
Sources/ShotPaste/
  App/        entry point, menu bar, global hotkeys, preferences
  Capture/    screencapture driver, Quick Access overlay, pinned windows, OCR
  Annotate/   annotation model, renderer, editor window
  Clipboard/  pasteboard monitor, persistent store, history panel, auto-paste
  UI/         toast HUD, settings
```

## Roadmap

- [ ] Screen recording (video / GIF) via ScreenCaptureKit
- [ ] Scrolling capture
- [ ] Customizable shortcuts
- [ ] Custom pinboards and rich text (RTF/HTML) in history
- [ ] Background/padding "beautify" for screenshots
- [ ] Exclude specific apps from clipboard history

## License

MIT

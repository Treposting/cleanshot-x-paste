# Changelog

All notable changes to Marquee. Versions follow [semantic versioning](https://semver.org).

## Unreleased

### Fixed
- The All-in-One toolbar didn't appear in 0.5.2, so only the selection showed.

### Added
- All-in-One toolbar: **Color** (C) picks a color, and a gear (,) opens Settings.

## 0.5.2 — 2026-10-15

### Fixed
- All-in-One could crash as soon as you started dragging a selection.

### Changed
- **All-in-One toolbar** redesigned as a Liquid Glass bar that follows light and dark mode, with Screenshot as the default action and key hints on every button.
- **Shortcuts** are grouped into Capture, Record, Tools and Clipboard. Only All-in-One (⌥⇧⌘A) and Clipboard History (⇧⌘V) are set by default; add the others you want in Settings or during onboarding.

## 0.5.1 — 2026-10-15

### Changed
- **All-in-One** shows its toolbar right away and works on the whole screen until you select an area. The selection stays editable: drag elsewhere for a new one, drag inside to move it, drag a handle to resize, arrow keys to nudge, ⌫ to go back to the whole screen.
- **Dark-mode app icon**: a graphite tile with yellow marks on macOS 26 and later, instead of a darkened yellow tile. The website logo follows dark mode too.

## 0.5.0 — 2026-10-15

### Added
- **Marquee window** with a sidebar: Home (every action as a button, recent captures), Library (all screenshots and recordings), Clipboard (searchable history grid), Colors, Permissions and Settings. Marquee shows in the Dock while it's open.
- **Onboarding** on first launch: welcome, permissions, key shortcuts and launch at login.
- **All-in-One** (⌥⇧⌘A): select an area, then Screenshot, Record, Copy Text or Pin from one toolbar.
- **Color picker** (⌥⇧⌘C): copy any on-screen color as HEX, RGB, HSL or SwiftUI, with a history of 48 colors.
- Main menu with standard Edit commands, so ⌘C/⌘V work in text fields.

### Changed
- The menu bar menu is shorter: Open Marquee, the main actions, Settings, updates and Quit. Pause and clear history moved to the Clipboard page.

## 0.4.1 — 2026-10-15

### Added
- **Liquid Glass** on macOS 26 and 27: Quick Access overlay, recording toolbar and countdown, clipboard history panel, toasts and the annotation editor's floating toolbar. Builds now use the macOS 26 SDK, so standard windows and controls get the new look too. macOS 13–15 keep the previous materials.
- Settings → Clipboard warns when macOS limits background clipboard access (macOS 15.4+) and explains how to allow it.

### Changed
- VoiceOver: labels for icon-only buttons and color swatches; toasts are announced.
- Reduce Motion: no pulsing record dot, and a simple fade for the countdown.

## 0.4.0 — 2026-10-15

### Added
- **Measure** (⌥⇧⌘M, macOS 14+): point anywhere to see distances to the nearest edges, drag to snap to an element's exact size, Space to keep measurements on screen, ⇧ for pixels, ⌘C to copy, ⌘S to capture the screen with measurements.
- **Microphone recording**: pick any input (built-in, USB, Bluetooth) on the new recording toolbar, with a live level meter. Microphone and desktop audio can be recorded together and are mixed into one soundtrack.
- **Recording toolbar**: appears under the selected area with microphone, desktop audio and Record; a 3-2-1 countdown; then a timer, level meter, Stop and Discard while recording.
- **Start options**: record instantly, or after a 3, 5 or 10 second countdown (3, 2, 1, Go).
- **Menu-bar timer**: a blinking red dot and the elapsed time while recording (12s → 4:05 → 1:04:05).
- **In-app updates**: Marquee checks GitHub for new releases, downloads and verifies them, and installs on restart. "Check for Updates…" is in the menu bar and Settings.
- Unit tests, run in CI on every push.
- Optional stable code signing for releases, so permissions survive updates ([docs/SIGNING.md](docs/SIGNING.md)).

## 0.3.0 — 2026-10-15

### Changed
- **ShotPaste is now Marquee.** New bundle ID; clipboard history, settings and shortcuts move over automatically on first launch.
- New logo and app icon, and a redesigned website.
- Clipboard "Link" items are teal instead of purple.

## 0.2.0 — 2026-10-14

### Added
- Screen recording to MP4 (area or full screen, 30/60 fps, optional computer audio and cursor), with GIF export.
- Customizable global shortcuts.
- Universal DMG and one-click GitHub releases.

## 0.1.0 — 2026-10-14

### Added
- Screenshots (area, window, full screen, self-timer), Quick Access overlay, annotation editor, pin to screen, OCR.
- Clipboard history with search, filters, pinning and direct paste.

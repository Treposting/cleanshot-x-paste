# Changelog

All notable changes to Marquee. Versions follow [semantic versioning](https://semver.org).

## Unreleased

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

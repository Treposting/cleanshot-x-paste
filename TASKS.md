# Tasks

Status as of v0.5.6 (2026-10-16). Project context and conventions are in [CLAUDE.md](CLAUDE.md); release history is in [CHANGELOG.md](CHANGELOG.md).

## Done

**Capture**
- [x] Area, window, full screen, timed (5 s) and OCR capture through `/usr/sbin/screencapture`
- [x] Quick Access overlay: copy, save, annotate, pin, drag out
- [x] Annotation editor: arrows, shapes, pen, highlight, text, numbered steps, pixelate
- [x] Pin screenshots above all windows
- [x] All-in-One (⌥⇧⌘A): toolbar first; editable selection (redraw, move, resize, nudge, ⌫ for whole screen); Screenshot ▾ / Record ▾ with Selected Area, Full Screen, Window; Copy (⌘C/⌃C), Copy Text, Pin, Color, Settings; keys ↩ F W R ⇧F ⇧W T P C ,
- [x] WindowPicker: hover-highlight a window and click to record it
- [x] Capture library (last 300 captures) in the Marquee window

**Record**
- [x] Area / full screen / window to MP4 (H.264, 30/60 fps), optional cursor
- [x] Microphone (any input, live level meter) and desktop audio, mixed into one track
- [x] Recording toolbar; instant start or 3/5/10 s countdown; blinking menu-bar timer; GIF export

**Tools**
- [x] Measure (macOS 14+): distances, snap to element, keep, copy, capture; points/pixels
- [x] Color picker: HEX / RGB / HSL / SwiftUI, 48-color history

**Clipboard**
- [x] History of text, links, images, files with source app; search, filters, pins, direct paste; skips concealed/transient (password) items; pause
- [x] ⇧⌘V panel and a full Clipboard page in the Marquee window

**App**
- [x] Marquee window: Home, Library, Clipboard, Colors, Permissions, Settings; shows in the Dock while open
- [x] Onboarding (welcome, permissions, record shortcuts, launch at login)
- [x] Trimmed menu-bar menu; standard main menu (Edit commands work in text fields)
- [x] Shortcuts grouped by category; only All-in-One and Clipboard History have defaults
- [x] Liquid Glass on macOS 26/27 with fallbacks; light and dark Icon Composer app icon
- [x] In-app updates from GitHub Releases (verified signature, swap on restart)
- [x] Stable self-signed release signing (from 0.5.5) so permissions survive updates; Permissions page with Fix Permissions (tccutil reset) and Restart Marquee
- [x] Release workflow, universal DMG + zip, CI with tests

**Site and docs**
- [x] Landing page (ruler-yellow design) with the 24-second demo pinned in the hero
- [x] README, CHANGELOG, HOW-IT-WORKS, SIGNING docs

## Needs checking on a real Mac

Built and passing CI, but not yet tried by hand:

- [ ] All-in-One: no crash when dragging; toolbar visible; ▾ menus open in the non-activating panel; ⌘C copies the area; F/W/⇧F/⇧W
- [ ] Recording a window with WindowPicker (highlight follows the pointer; multi-display)
- [ ] Permissions persist from 0.5.5 → 0.5.6 → next release
- [ ] Fix Permissions / Restart Marquee on the Permissions page

## Next up

1. **Fix two compiler warnings** (small, also prepares for Swift 6)
   - `Window/LibraryView.swift` `LibraryThumbnail.thumbnail(at:)`: returns `NSImage` from `Task.detached`, but `NSImage` is only `Sendable` from macOS 14. Return a `CGImage` (or `Data`) from the detached task and build the `NSImage` on the main actor.
   - `Record/AreaSelector.swift`: `static let recordHint` is main-actor isolated but used as a default argument. Mark it `nonisolated static let` (it's a constant string).
2. **Custom domain**: point marquee.nahid.bd at GitHub Pages: add `site/CNAME` containing `marquee.nahid.bd`, update links in README / site / `video/demo.html` if the canonical URL changes. Needs a DNS CNAME `marquee → treposting.github.io` at the domain provider.
3. **Social versions of the demo**: square (1080×1080) and vertical (1080×1920) renders. Make `video/demo.html` size-aware or add a layout per format.

## Backlog

- [ ] Measure guides with arrow-key nudging; measuring across multiple displays (see docs/plans/MEASURE.md)
- [ ] Webcam overlay in recordings
- [ ] Scrolling capture
- [ ] Rich text (RTF/HTML) in clipboard history
- [ ] Exclude specific apps from clipboard history
- [ ] Notarized releases (needs an Apple Developer ID, $99/year; removes the right-click → Open step)
- [ ] Windows version: proposed as a separate native C#/.NET app built in phases (capture + clipboard first). Not started; waiting on a go-ahead.

## Notes

- The release signing certificate (`marquee-signing.p12` and its password) lives with the maintainer and in the repo secrets. Losing it means users re-grant permissions once.
- Releases are triggered from Actions, never by pushing tags.

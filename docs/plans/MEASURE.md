# Plan: Measure (PixelSnap-style screen ruler)

Status: **planning**. Nothing here is built yet.

## Goal

Add a measuring mode to Marquee that designers and front-end developers can use to check sizes, spacing and alignment of anything on screen, without opening a design tool. It should feel like the rest of Marquee: one shortcut, instant, keyboard-driven, and it hands results to the clipboard or to the Quick Access overlay.

## What PixelSnap does (publicly described behavior)

From the PixelSnap website, changelog and reviews:

- **Find dimensions.** Point at the screen and it shows the distance from the cursor to the nearest edges in every direction.
- **Snap to objects.** Drag an area around an element and it shrinks to that element's exact bounds and shows its size. You can measure several elements at once.
- **Guides.** Add horizontal and vertical guides to check alignment. It shows the distance between guides, and arrow keys nudge a guide.
- **Hold and copy.** Keep measurements on screen, copy the numbers, or export the screen with the measurements drawn on it.

We reimplement this behavior from scratch on public Apple APIs, the same way the rest of Marquee was built. No code or assets come from PixelSnap.

## User experience

| Action | Default | Behavior |
|---|---|---|
| Start measuring | <kbd>⌥</kbd><kbd>⇧</kbd><kbd>⌘</kbd><kbd>M</kbd> (customizable) | The screen freezes and a crosshair appears |
| Move the pointer | | Lines run from the cursor to the nearest edge left, right, up and down. Labels show both distances, e.g. `24` and `116`, and the span, e.g. `140 × 48` |
| Drag a rectangle | | It snaps to the bounds of the element inside it and shows `W × H` |
| <kbd>Space</kbd> | | Hold the current measurement on screen and start another |
| Click a ruler edge | | Add a guide. Drag to move it, arrow keys nudge 1 pt, <kbd>⇧</kbd> + arrow keys nudge 10 pt |
| <kbd>⌘</kbd><kbd>C</kbd> | | Copy the last measurement as text, e.g. `140 × 48` |
| <kbd>⌘</kbd><kbd>S</kbd> | | Capture the screen with measurements drawn on it, then open the Quick Access overlay (copy, save, annotate, pin) |
| <kbd>⇧</kbd> | | Switch between points and pixels |
| <kbd>Esc</kbd> | | Leave measure mode |

Defaults: values in points (what designers use; pixels on Retina are ×2), yellow lines and labels to match the brand, and an edge tolerance that ignores anti-aliasing.

## How it works

### 1. Freeze the screen

When measure mode starts, grab one still image per display. Measuring a frozen image keeps numbers stable while videos play or menus close, and means our overlay never measures itself.

- macOS 14+: `SCScreenshotManager.captureImage(contentFilter:configuration:)` from ScreenCaptureKit.
- macOS 13: a one-frame `SCStream` with the same filter. We already use `SCStream` for recording.
- Exclude Marquee's own windows through `SCContentFilter(display:excludingApplications:…)`, as the recorder does.
- Capture at native resolution (`backingScaleFactor`), so 1 pt = 2 px on Retina.

This needs the same Screen Recording permission Marquee already asks for.

### 2. Read pixels quickly

Copy each `CGImage` into a tightly packed RGBA8 buffer once (`vImage` / `CGContext`). Pixel lookups are then a plain array read. A 5K display is about 59 MB at 4 bytes per pixel, held only while measuring and freed on exit.

### 3. Edge finding (the core algorithm)

**Hover distances.** From the cursor pixel, walk left, right, up and down until a pixel differs from the start color by more than the tolerance:

```
diff(a, b) = max(|aR - bR|, |aG - bG|, |aB - bB|)
edge when diff > tolerance  (default 12 of 255)
```

That's O(width + height) per mouse move, which is trivial even at 120 Hz. Optionally require 2 consecutive differing pixels, so a single anti-aliased pixel doesn't stop the walk.

**Snap to element.** Given a dragged rectangle:
1. Take the background color as the most common color along the rectangle's border.
2. Find the first and last rows and columns that contain a pixel differing from that background by more than the tolerance.
3. The bounding box of those rows and columns is the element. If nothing differs, keep the rectangle as drawn.

That's O(w × h) once per drag, under a millisecond for typical UI elements. A later version can split one drag into several elements with connected-component labeling.

**Guides.** Guides snap to the nearest edge within 4 pt, using the same edge search.

All of this lives in pure Swift functions with no AppKit, so it can be unit tested on synthetic images.

### 4. Overlay

- One borderless, full-screen `NSPanel` per display at `.screenSaver` level, showing the frozen image with Core Animation layers on top: `CAShapeLayer` for lines and `CATextLayer` for labels. Layers keep it smooth at 120 Hz.
- Convert between AppKit global coordinates (origin bottom-left, in points) and image pixels (origin top-left) in one place.
- On multiple displays, each panel measures its own display's snapshot.

### 5. Hooking into existing code

| Existing piece | Change |
|---|---|
| `ShortcutAction` (`App/Shortcuts.swift`) | Add `.measure` with default ⌥⇧⌘M; it shows up in Settings → Shortcuts automatically |
| `AppDelegate.perform(_:)` and menu | Add a "Measure" menu item and action |
| `Preferences` + `SettingsView` | New "Measure" tab: units, tolerance, line color, hold-to-measure vs toggle |
| `QuickAccessManager` | ⌘S renders the frozen image + overlay into a `Capture` and shows it, so copy, save, annotate and pin work for free |
| Website and README | Add "Measure" to the verb list and features once it ships |

### New files

```
Sources/Marquee/Measure/
├── MeasureController.swift   Session lifecycle: freeze, show panels, keys, exit
├── ScreenSnapshot.swift      ScreenCaptureKit still capture → RGBA buffer
├── EdgeFinder.swift          Pure algorithms: hover distances, snap-to-bounds, guide snapping
├── MeasureOverlayView.swift  Layer-based drawing of lines, labels, guides
└── Measurement.swift         Value types: distances, rectangles, guides, units
Tests/MarqueeTests/
└── EdgeFinderTests.swift     Synthetic images: solid boxes, anti-aliased edges, gradients, shadows
```

Adding the test target also gives CI a `swift test` step.

## Milestones

1. **Hover distances.** Freeze, edge finding, the overlay with distance lines and labels, ⌘C, Esc. *The core of the feature; ship it behind the menu item first.*
2. **Snap to element.** Drag to snap, `W × H` label, Space to hold measurements.
3. **Export.** ⌘S to Quick Access, points and pixels toggle.
4. **Guides.** Add from the ruler edges, snapping, arrow-key nudging, distance between guides.
5. **Settings and polish.** Measure tab, multi-display testing, tests in CI, website and README.

Each milestone is one pull request and leaves the app shippable.

## Edge cases to test

- Retina and non-Retina displays side by side; scaled display modes, where 1 pt isn't an integer number of pixels.
- Anti-aliased text and rounded corners, which the tolerance and the two-pixel rule should handle.
- Gradients and drop shadows. Add an "ignore shadows" option if the default tolerance isn't enough.
- Protected content (DRM video, secure input), which captures as black and will measure as one big box.
- Full-screen apps and Spaces: the panels need `.fullScreenAuxiliary` and `.canJoinAllSpaces`, as the overlay has today.

## Decisions to make before building

1. **Toggle or hold.** Should the shortcut toggle measure mode, or measure only while the keys are held? PixelSnap toggles. *Recommendation: toggle, with hold as a setting.*
2. **Frozen or live.** A frozen screen is stable and simpler. A live screen follows scrolling. *Recommendation: frozen for v1.*
3. **Default units.** *Recommendation: points.*
4. **Default shortcut.** ⌥⇧⌘M, following the existing ⌥⇧⌘ family.

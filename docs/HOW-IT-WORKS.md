# How CleanShot X and Paste work (and how ShotPaste does it)

This project is a **clean-room reimplementation**. We did not decompile, disassemble, or copy code or assets from either app. Their EULAs prohibit reverse engineering the binaries, and none of it is needed. Both apps are built on public macOS APIs, and their behavior can be seen from the outside and in their docs and reviews. This file records that behavior and the API each feature maps to.

## CleanShot X: observed behavior

- **Menu-bar app** with global shortcuts. Users often remap the system ⇧⌘3/4/5 to it.
- **Capture modes:** area, window, fullscreen, previous area, self-timer, scrolling capture, screen recording (video/GIF), and text capture (OCR).
- **Quick Access Overlay:** after a capture, a thumbnail appears in a screen corner. Hover actions are copy, save, annotate (pencil), pin, and close. The thumbnail can be dragged into any app. Overlays stack when you take several captures.
- **Annotation editor:** arrows, shapes, text, highlighter, numbered "counter" steps, blur/pixelate, crop, and backgrounds.
- **Pin screenshots:** a borderless always-on-top window you can move, resize, and fade.
- **Cloud upload:** shareable links.

### How it maps to macOS APIs

| Feature | API | ShotPaste |
|---|---|---|
| Global shortcuts | Carbon `RegisterEventHotKey`. Needs no permission and swallows the key event. | `App/HotKeyCenter.swift` |
| Area/window/fullscreen capture | `ScreenCaptureKit` (`SCScreenshotManager`) or `CGWindowListCreateImage`, plus a custom selection overlay. The simpler route: Apple's `/usr/sbin/screencapture -i` provides the same crosshair UI. | `Capture/CaptureService.swift` uses `screencapture` |
| Permission | Screen Recording (TCC), prompted on first capture | automatic |
| Quick Access overlay | `NSPanel` with `.nonactivatingPanel`, `.floating` level, `.canJoinAllSpaces`. Drag-out via `NSItemProvider` file URL. | `Capture/QuickAccessOverlay.swift` |
| Annotation | Custom drawing canvas; export by rendering shapes over the bitmap | SwiftUI `Canvas` + `ImageRenderer` (`Annotate/`) |
| Pixelate | Core Image `CIPixellate`, clipped to the selected rect | `AnnotationRenderer.pixelate` |
| Pin | Borderless floating `NSPanel` with an `NSImageView` | `Capture/PinnedImageWindow.swift` |
| OCR | Vision `VNRecognizeTextRequest` | `Capture/TextRecognizer.swift` |
| Screen recording | `ScreenCaptureKit` `SCStream` → `AVAssetWriter` | roadmap |
| Scrolling capture | Repeated captures while scrolling, stitched by matching overlapping rows | roadmap |

## Paste: observed behavior

- Runs in the background and records everything you copy: text, rich text, images, files, and links. Each entry shows the app it came from.
- **⇧⌘V** opens a full-width panel along the bottom of the screen with a horizontal row of cards. You can search, filter by type, and organize items into pinboards.
- Pressing Enter or double-clicking **pastes into the app you were just in**. The panel doesn't steal focus from that app.
- Skips passwords from password managers.

### How it maps to macOS APIs

| Feature | API | ShotPaste |
|---|---|---|
| Detect clipboard changes | macOS has **no** change notification. Clipboard managers poll `NSPasteboard.general.changeCount` (every ~0.5 s) and read the new contents when it changes. | `Clipboard/ClipboardMonitor.swift` |
| Source app | `NSWorkspace.shared.frontmostApplication` at the time of the change | same |
| Privacy | The [nspasteboard.org](http://nspasteboard.org) convention: apps add `org.nspasteboard.ConcealedType` / `TransientType` markers, and clipboard managers skip those entries | same |
| Storage | Local database plus image files | JSON + PNG files in `~/Library/Application Support/ShotPaste` (`ClipboardStore.swift`) |
| Panel that doesn't steal focus | Borderless `NSPanel` with `.nonactivatingPanel` and `canBecomeKey = true`. It gets keyboard input while the other app stays active. | `Clipboard/HistoryPanel.swift` |
| Paste into the other app | Write the item to `NSPasteboard`, hide the panel, then post a synthetic ⌘V with `CGEvent`. Needs the **Accessibility** permission. | `Clipboard/Paster.swift` |
| Avoid re-recording our own paste | After writing, store the new `changeCount` as "seen" | `ClipboardMonitor.ignoreCurrentContents()` |

## Why the two fit together

A screenshot copied by the capture side lands on the pasteboard. The history side then records it like any other copy, so every screenshot you took is also one ⇧⌘V away.

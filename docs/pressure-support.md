# Pressure and tilt: evidence and limits

**Styleus provides basic mouse drawing with pressure activation. It does not deliver pressure-sensitive ink or tilt to other Mac apps.** Pencil force decides when to press/release a mouse button; it does not change the receiving application's stroke width or opacity.

## Implemented behavior

Trackpad mode requires both firm pressure and movement before holding the left button. Drawing mode lets light contact position the pointer without ink; crossing the threshold begins a stroke. Easing or lifting ends it. The adjustable threshold and release hysteresis are covered by shared tests. Basic pressure-activated strokes have been physically tested in Zotero.

The iPad meter reads local gesture state. Optional pressure/contact metadata sent to the Mac only drives Styleus's own cursor indicator. Other Mac apps receive ordinary mouse actions, not this metadata. Displaying numeric pressure in Styleus does not establish target-app pressure support.

## Zotero

Inspection of Zotero 10.0.6's reader implementation found a fixed width per ink annotation and XY-only paths, with no pressure/tilt reads for that path. The public reader code also exposes [ink handling](https://github.com/zotero/reader/blob/master/src/pdf/pdf-view.js) and [rendering](https://github.com/zotero/reader/blob/master/src/pdf/lib/render.js). These links follow a moving branch; behavior in another release needs new verification.

Ordinary mouse-based placement and separate pressure-activated strokes passed physical testing. Sending pressure values alone cannot add variable-width ink to a renderer that ignores them. Receiving-app support would require a separate integration. Zotero's [PDF reader documentation](https://www.zotero.org/support/pdf_reader) describes its annotation tools.

## Notability experiment

Notability's [native Apple Pencil documentation](https://support.gingerlabs.com/en-us/articles/16300204-writing-with-apple-pencil) describes stylus behavior on supported platforms. It does not establish a remote macOS stylus input API. The existence of Apple's public [tablet event fields](https://developer.apple.com/documentation/coregraphics/cgeventfield) likewise does not establish that Notability accepts synthetic pressure input.

The Mac companion contains an opt-in **Experimental Notability pressure test**, implemented in `Mac/PressureProbe.swift`. It requires Accessibility approval, a disposable blank note, a selected target rectangle and a second explicit confirmation. It stops remote control and posts two equal-speed strokes: one with constant pressure and one with varied pressure/tilt. It aborts when the target app loses focus or permission changes, and releases on cancellation, sleep, lock or normal quit.

This uses public event fields and a synthetic identifier, not a registered tablet driver. **The experiment has not been run to establish Notability pressure support.** It may be ignored or treated as ordinary mouse input. A passing experiment would require visible or target-side evidence that pressure changes affect the receiving app, with equal-speed control strokes to distinguish pressure from velocity effects.

No virtual HID driver, privileged component, paid dependency or receiving-app modification is included. Further integration should identify a supported target-app interface and test it before claiming compatibility.

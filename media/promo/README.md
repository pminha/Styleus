# Styleus product film

A 30-second, 1920 × 1080, 60 fps illustrated product advertisement. The hardware drawings use thin rounded bezels, a shallow laptop base, and restrained tablet proportions and shadows so the Pencil interaction stays central.

- **Watch:** [`styleus-promo.mp4`](styleus-promo.mp4)
- **Poster:** [`styleus-promo-poster.png`](styleus-promo-poster.png)
- **Caption sidecar:** [`styleus-promo.srt`](styleus-promo.srt)
- **Source:** [`render.swift`](render.swift), [`sound.py`](sound.py), [`render.sh`](render.sh)

The visuals are original vector-style motion graphics, not footage or a screen recording. A small **Illustrated demo** label remains visible. The generic Mac workspace and paper contain no personal information or third-party app branding. Pencil contact and the corresponding Mac cursor, drag, and annotation share one animation timeline. The iPad drawing region and Mac annotation region have matching aspect ratios.

## Storyboard

| Time | Action | Message |
| --- | --- | --- |
| 0–3.4 s | Two devices appear, with the Pencil on the iPad. | Your Pencil. Your Mac. |
| 3.4–9.4 s | Light contact moves the Mac pointer. Lift and reposition leave it still. A short tap selects a note. | Point. Tap. Go. |
| 9.4–15.1 s | Firmer pressure activates dragging. The left pressure rail turns orange; the Mac card follows. Easing and lifting release it. | Press. Move. Release. |
| 15.1–22.4 s | Two separate pressure-activated strokes annotate a generic paper. The lift between strokes draws no connecting line. | Make your mark. |
| 22.4–26.1 s | Two finger-contact markers slide together and the Mac document scrolls. | Two fingers. Keep the flow. |
| 26.1–30 s | A quiet end card presents the project and free build option. | Build it yourself. Free and open source. |

The drawing scene is explicitly labeled **basic mouse-based annotation**. It makes no claim of variable-width pressure ink, universal drawing-app integration, measured latency, Pencil hover, or identical behavior to Apple's trackpad.

## Reproduce

Requirements: macOS with Swift command-line tools, Python 3, and FFmpeg with `libx264` and AAC encoding available on `PATH`.

From the repository root:

```sh
zsh media/promo/render.sh
```

The script compiles the native CoreGraphics/CoreText renderer into `build/promo/`, synthesizes a quiet original ambient score, renders all 1,800 frames, encodes the MP4, and writes the poster. The two final app-icon masters in `media/branding/` appear on the end card when present; the renderer can also run without them. It uses relative paths. It neither reads device/account details nor requires a network connection.

To export a single native 1080p frame after compiling:

```sh
build/promo/render --icons --still 17.3 build/promo/annotation-preview.png
```

The final MP4 uses H.264 with `yuv420p`, AAC stereo audio, and fast-start metadata for common browser and video-player compatibility. Playback is 30 seconds at 60 fps. Frame rendering is deterministic; encoded bytes may vary by FFmpeg version.

## Credits and licensing

Visuals, animation, code, and synthesized audio: **Styleus contributors**. Licensed under the repository's MIT License. No stock footage, recorded speech, external music samples, Apple logos, or third-party screenshots are included. Typography uses the macOS system font available to the renderer. Apple Pencil, iPad, Mac, and MacBook are product names belonging to Apple; the film does not claim endorsement.

## Validation

The exported movie was fully decoded without errors. Six decoded key frames covering every scene were visually inspected, including Pencil contact, pressure dragging, separate annotation strokes, two-finger markers, and the end card. The final file reports exactly 30 seconds, 1,800 H.264 frames at 60 fps, 1920 × 1080 pixels, `yuv420p`, and stereo 48 kHz AAC audio. Metadata contains the title, contributor credit, and illustrated-demo description; no account, device, or private path information is included. This verifies the rendered film, not measured physical-device performance.

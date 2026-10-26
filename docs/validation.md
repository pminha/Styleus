# Validation and compatibility

This report distinguishes automated checks from physical observations. It excludes account, device identity, signing-profile and development-session diagnostics. Build and test logs are local ignored files.

## Automated validation

The native iPad app, generic iPad simulator target and native Mac companion have built successfully in the recorded [build environment](environment.md). The simulator build was compiled only; no simulator execution is claimed.

The shared Swift suite currently contains **121 tests**, covering:

- Relative anchoring, stable taps, tap/double-tap/hold recognition, pressure activation and hysteresis.
- Absolute aspect-fit mapping, display/region coordinates, negative display origins, invalid coordinates, separate strokes and margin handling.
- Mode/cancellation releases, stale samples, session/sequence/geometry rejection, expiring leases and clean reconnects.
- Two-finger recognition, palm/finger-change handling, fractional scrolling, speed-dependent gain, momentum, phase handling and independent direction settings.
- Exclusive scroll/pinch arbitration, ratio preservation, disabled-mode scrolling equivalence, malformed zoom rejection, native phase encoding, zoom/drag exclusion and terminal-event release.
- Core Graphics event construction, keyboard modifiers, click counts and pressure/status presentation. Event-encoding tests do not post global input.
- Framing, random pairing credentials, route-selection policy and a real authenticated localhost TLS exchange. Wrong-key authentication is rejected.
- Connection headings, retained error details, permission guidance and clearing old failure messages.

Run `zsh scripts/test.sh` to reproduce the host suite. Configuration-helper tests and clean source-build checks are recorded separately in the source-release check below. Test success is not proof of compatibility with every Mac app, network or device.

## Physical observations

Development testing on a first-generation 11-inch iPad Pro with Apple Pencil 2 (without hover) and an Apple silicon Mac established:

| Area | Evidence and limits |
| --- | --- |
| Native installation | Both apps launch as native apps after the owner's signing, trust and permission approvals. |
| Wired control | Pointer control worked with iPad Wi-Fi disabled, and after a normal app-icon launch with Xcode closed. A clean Mac or fresh reboot without development services prepared remains untested. |
| Pencil gestures | Left/double/right click, pressure drag/release and stable cursor position during taps passed. |
| Mac modifiers | Command-click, Shift-click, Control-click and Option pressure-drag worked in Finder. Other apps and mid-drag modifier changes need separate physical checks. |
| Experimental zoom | The direct native backend passed its controlled Mac/WebKit diagnostic. The user confirmed physical iPad pinch zoom and separate two-finger scrolling on a browser page; app/version and broader interruption checks remain unrecorded. |
| Scrolling | Two-finger scrolling, independent direction switches, palm/finger-change handling, smooth glide and one-finger touch-to-stop passed. Current scrolling feel was accepted; no measured equivalence to Apple's response curve is claimed. |
| Basic drawing | Zotero region placement, light positioning without ink and separate pressure-activated mouse strokes passed. Receiving-app pressure-dependent ink width and tilt are not implemented. |
| Interruption | Mode switching and rotation released pressure input. Cable-removal release and clean reconnect were verified on an earlier input revision; repeat on each release. |
| Feedback | Actual UIKit meter rendering was inspected in light and dark appearances. The latest Minimal edge app installed and launched; complete layout/popover and lifecycle acceptance remain separate physical checks. |
| Wi-Fi | Authenticated control worked, but intermittent skipping was reported. Wi-Fi responsiveness remains an unresolved limitation. |

These checks occurred across development revisions; they are not a full acceptance pass for every later revision. Use the [hardware checklist](hardware-checklist.md) for release verification.

## Remaining limits

- Multiple displays, display changes, every background/lock/sleep path, all supported OS versions and Intel Macs require additional physical testing.
- The selected deployment targets do not by themselves prove behavior on the oldest supported OS.
- Wired networking depends on the interface exposed by the trusted device connection. No driver or raw-USB implementation is bundled.
- Communication round-trip measurements are not Pencil-to-screen latency. No controlled end-to-end latency claim is made.
- The optional cursor overlay can lag. It is disabled by default.
- The Notability pressure experiment has not established receiving-app pressure/tilt support.
- Renewal after an actual seven-day expiry still needs a separate data/pairing persistence check. Keep the same team and bundle identifiers and avoid deleting the app.

## Source-release check

A clean source copy without local signing configuration passed all three compile checks with the final app-icon catalogs: the Mac companion using local ad-hoc signing, the unsigned iPad device target and the unsigned generic simulator target. Xcode's iOS simulator runtime was installed to satisfy the icon compiler's dependency. The unchanged shared core previously passed all **93 Swift tests** from a clean source copy. **14 Python setup-helper tests** pass, covering generic defaults, private-file permissions, stable identities, repeated imports, conflicting/custom signing rejection, installer usage and target-specific icon resource membership. These are compile checks; no interactive simulator session or physical-device execution is claimed for the artwork update.

Independent inspection of all **106 public files**, including the final artwork and promotional movie, found no personal identifiers, local signing configuration, actual credentials, private paths, real device identifiers, private build/diagnostic artifacts or signing material. Remaining UUIDs, loopback addresses and team-like strings are synthetic test fixtures or placeholders. PNG metadata contains only dimensions and color information; movie metadata contains generic project credits and encoder information. Relative documentation links resolve. The current private signing identity and app identifiers were also verified to resolve unchanged for both targets in Debug and Release; these local values are excluded from the public source.

The matching source ZIP contains exactly those 106 files, with fixed timestamps, generic filenames and no identifying comments or owner metadata. Archive contents were compared byte-for-byte against the public source after the final artwork revision.

Both native icon catalogs contain ten correctly sized PNGs. All iPad icons are opaque; Mac icons preserve transparency around the laptop silhouette. The original vector artwork was inspected at 256 pixels and 32 pixels. The 30-second illustrated promo was fully decoded and its six scenes visually inspected: 1,800 H.264 frames at 1920 × 1080 and 60 fps, with stereo AAC audio. It is an animation, not a recording or latency measurement.

No distribution-signed binary is included. Physical first-time installation on another person's hardware and renewal after actual expiry remain separate acceptance checks.

## Direct native pinch update

The shared suite passes **121 Swift tests**, including 28 new zoom recognition, native encoding and receiver-state tests. All **14 setup-helper tests** pass. The current source passes unsigned Mac, physical-iPad-target and generic iPad-simulator compilation; these checks do not establish simulator interaction or physical pinch behavior.

The direct encoder constructs native magnification through Core Graphics setters and verifies AppKit phase/fractional-value readback locally. This is distinct from the earlier Hammerspoon delivery experiment. On 2026-10-26 both apps were signed, installed and launched; the Mac retained Accessibility approval. The direct native diagnostic received began/changed/ended magnification and WebKit changed from 1.0× to 1.9183×. Its 32 posted events appeared as 29 received events, including three combined changed increments; total changed magnification was preserved. This validates the controlled Mac receiving view. The user then confirmed that physical iPad pinch zoom and scrolling work separately on a browser page. The browser name/version was not recorded; other target apps, perceived response and remaining interruption cases still need separate checks. No Hammerspoon code, executable, helper or runtime dependency is included. The experimental setting defaults to off. See [the research record](native-pinch-research.md) and [hardware checklist](hardware-checklist.md).

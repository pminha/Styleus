# Styleus

Use an iPad and Apple Pencil as a trackpad or annotation tablet for your Mac.

Styleus runs as two native apps: one on the iPad, one on the Mac. Move and click with the Pencil, scroll with two fingers, and connect over USB-C or local Wi-Fi.

I built it for two things: replacing everyday trackpad use with my iPad and Pencil, and making it easier to read and annotate papers in Zotero on my Mac. Trackpad mode handles pointing, clicking, dragging and scrolling; Drawing tablet mode lets me write directly over a selected area of the PDF.

You build both apps yourself with Xcode. A free Apple Account is enough for personal installation, but **the iPad app needs to be re-signed and reinstalled every seven days**. There is no App Store download. [Build instructions](SETUP.md) · [Renewal instructions](SETUP.md#6-renew-the-ipad-app-every-seven-days)

## Using it

### Trackpad

Slide the Pencil to move the pointer. Lift and reposition it when you run out of room. Small movements during a tap are ignored so the pointer stays on the thing you're clicking.

| Action | Gesture |
| --- | --- |
| Left click | Tap and lift. |
| Double click | Tap twice quickly. |
| Right click | Hold still for half a second, then lift. |
| Drag | Press more firmly while moving. Ease pressure or lift to release. |
| Scroll | Slide two fingers together, vertically or horizontally. |
| Stop scrolling after a flick | Touch down with a finger or the Pencil. |
| Zoom, when enabled | Spread two fingers to zoom in; pinch to zoom out. |

Hold Command, Shift, Option or Control on the **Mac keyboard** to use it with a Pencil click or drag. Settings has separate pointer and scrolling speeds, a pressure threshold, and a direction switch for each scrolling axis.

One finger does not move or click the pointer. Pencil contact takes priority over finger gestures; lift the Pencil and any resting fingers before starting a new scroll or pinch.

### Paper annotation

Choose **Drawing tablet** on the iPad, then select a display or rectangular region in the Mac companion. The iPad's drawing area maps to that target with the same aspect ratio.

Open a PDF or note on the Mac and select its pen tool. Light Pencil contact positions the pointer; pressing starts a stroke. Ease pressure or lift to stop. Look at the Mac while writing—the canvas is not mirrored onto the iPad.

**Drawing uses mouse emulation. Pressure starts and stops strokes; it does not control ink width or send tilt to the drawing app.** Basic annotation has been tested in Zotero. Notability and other drawing apps still need their own compatibility checks.

### Pinch zoom

Turn on **Settings → Pinch to zoom → Experimental pinch zoom**. It is off by default and available in both modes. A gesture stays with the action it starts: lift both fingers before switching between scrolling and zooming.

Zoom is built into Styleus, with no separate helper to install. It uses undocumented macOS event fields, so support can vary by app or change after an OS update. Chromium-based browsers may need a larger initial pinch before zoom starts. [Implementation and test results](docs/native-pinch-research.md)

## Build and install

You'll need:

- An iPad with a compatible Apple Pencil. Hover is not required.
- A Mac with Xcode and Python 3.
- A free Apple Account for signing your own copy.
- A USB data cable for device setup and wired use.

Pressure dragging and annotation require a pressure-sensitive Pencil. Apple Pencil (USB-C) lacks pressure sensitivity, so it cannot use those features in the current implementation. See [Apple’s Pencil comparison](https://www.apple.com/apple-pencil/). Only Apple Pencil 2 has been physically tested with Styleus.

The deployment targets are **iPadOS 17+ and macOS 14+**. Xcode must also support the iPad's installed OS and may require a newer macOS. Development testing has used a 2018 11-inch iPad Pro, Apple Pencil 2 and an Apple silicon Mac; the minimum OS versions and Intel Macs have not been physically tested.

Clone the repository, or use GitHub's **Code → Download ZIP**:

```sh
git clone https://github.com/pminha/Styleus.git
cd Styleus
open Styleus.xcodeproj
```

Follow [SETUP.md](SETUP.md) to select your Personal Team for both targets, save your signing settings in the ignored `Config/Local.xcconfig`, and prepare the iPad. It also covers the required Xcode components and permission prompts.

Once signing is configured:

```sh
zsh scripts/build.sh
open "dist/Styleus Mac.app"
xcrun devicectl list devices
zsh scripts/install-ipad.sh 'YOUR_DEVICE_IDENTIFIER_OR_NAME'
```

The build script checks all three targets, but its iPad builds are unsigned. The install script builds and signs the app for the device you specify. Quit the Mac companion from its menu-bar menu before replacing it.

Allow **Accessibility** for the Mac app and **Local Network** access on both devices. Pair using the Mac's QR code, or enter its text code on the iPad, then tap **Connect**. QR scanning also needs Camera permission. Keep pairing codes private.

### Free signing and renewal

Apple's free Personal Team provisioning lasts seven days. After expiry, rebuild and reinstall using Xcode or the install command above. Keep the same Apple Account, bundle identifiers and local signing configuration, and leave the existing iPad app installed. You do not need to rebuild the Mac app each week. [Apple's Personal Team rules](https://developer.apple.com/help/account/basics/about-your-developer-account/)

When updating Styleus itself, update **both apps** from the same source version and reconnect.

## Connection

**USB-C / wired is the default** and has been more consistent in testing. Wi-Fi is selectable in Settings, but intermittent skipping has been reported. Wired mode never switches to Wi-Fi automatically.

Cable mode uses the network interface exposed by a trusted USB connection. It has worked with iPad Wi-Fi disabled and after launching Styleus without Xcode open. First-time wired use on a clean Mac without device preparation has not been verified.

Pairing and control stay on the local connection, with authentication and encryption. There is no Styleus account service or cloud relay. Disconnecting releases held input; reconnecting requires an explicit tap and starts with no active drag or stroke. Tap **ⓘ** beside the connection status for error details.

## Development and testing

The apps use SwiftUI, UIKit, AppKit and Network.framework, with no external Swift packages. Shared input logic lives in `Shared/`; platform code is in `iPad/` and `Mac/`.

```sh
zsh scripts/test.sh
python3 -m unittest discover -s scripts/tests -v
zsh scripts/build.sh --check-only
```

GitHub Actions runs the Swift and setup-helper tests on pushes to `main` and pull requests. These checks do not build or sign the native apps, or test physical input.

The last validation passed **121 Swift tests**, **14 setup-helper tests**, and all three build targets. Physical testing has covered Pencil clicks and dragging, modifier keys, two-finger scrolling, Zotero annotation, and basic browser pinch zoom. That is not a compatibility guarantee for every app or device. See the [validation record](docs/validation.md) and [hardware checklist](docs/hardware-checklist.md).

After adding Swift files, run `python3 scripts/generate_project.py` to update the Xcode project. Keep local signing settings, device logs and pairing material out of commits. [Source-release notes](docs/source-release.md)

## License

[MIT](LICENSE) · Styleus contributors. See [third-party notices](THIRD_PARTY_NOTICES.md) for the Apple-sourced gesture field definitions.

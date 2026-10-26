# Build, install and use Styleus for free

You build **both native apps on your own Mac**. The iPad app is installed directly through Xcode using your free Apple Account's Personal Team. A paid developer membership, TestFlight and App Store purchase are not needed.

The first setup takes several steps. Afterward, the Mac app opens normally and the iPad app opens from its icon. Free iPad signing needs renewal every seven days.

## 1. Prepare the tools and devices

You need:

- A Mac running **macOS 14 or later**, with Xcode installed and opened at least once to finish its setup.
- An iPad running **iPadOS 17 or later**, plus a compatible Apple Pencil. Hover support is not required.
- A free Apple Account signed in under **Xcode → Settings → Accounts**.
- A USB data cable for initial device preparation and wired use. Charging-only cables will not work.
- Python 3 for the small project/signing configuration helpers. No third-party Python or Swift package is needed.

Pressure dragging and annotation require a pressure-sensitive Pencil. Apple Pencil (USB-C) lacks pressure sensitivity, so it cannot use those features in the current implementation. See [Apple’s Pencil comparison](https://www.apple.com/apple-pencil/). Only Apple Pencil 2 has been physically tested with Styleus.

Use an Xcode version that supports your iPad's installed OS. Xcode itself may require a newer macOS than Styleus's minimum runtime version. If Xcode explicitly reports that the device OS is unsupported, update Xcode; lowering the project's deployment target does not add device support. An iPad simulator can compile and exercise some UI, but cannot validate physical Pencil input or the wired connection.

Install the matching **iOS simulator runtime** under **Xcode → Settings → Components** as well. Xcode's icon compiler can require this component even when building for a physical iPad. If a build reports “No available simulator runtimes,” install the iOS component and retry. On Apple silicon, `xcodebuild -downloadPlatform iOS -architectureVariant arm64` installs the smaller Apple-silicon variant. This is a free, multi-gigabyte Xcode download. See [Apple's component instructions](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

Download the repository with **Code → Download ZIP**, or clone it if you use Git. Unzip it into a folder you plan to keep, then open `Styleus.xcodeproj`. When a command below is needed, open Terminal in this project folder.

Connect and unlock the iPad:

1. Approve **Trust This Computer** on the iPad if prompted.
2. Open **Xcode → Window → Devices and Simulators**, select your iPad, and let pairing and device preparation finish.
3. Enable **iPad Settings → Privacy & Security → Developer Mode** when Xcode requests it. Restart the iPad, unlock it and confirm enabling Developer Mode after restart.

These are Apple's approvals; Styleus does not bypass them. See [Apple's physical-device instructions](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) and [Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## 2. Configure your own signing

The repository has generic identifiers and no development team. **Use your own Personal Team and stable, unique bundle identifiers.** A bundle identifier is the app's identity on your device; changing it creates a different installation.

The recommended first-time route is Xcode:

1. Select the blue **Styleus** project in the navigator, then select the **StyleusPad** target.
2. Open **Signing & Capabilities**, select **All** configurations if that selector is shown, enable **Automatically manage signing**, and choose your **Personal Team**.
3. Set a unique bundle identifier, for example `local.youruniquealias.styleus.ipad`. Replace `youruniquealias` with a value of your own; do not use this example unchanged. Keep the same identifier for future renewals.
4. Repeat for **StyleusMac**, using the same Personal Team and a second identifier such as `local.youruniquealias.styleus.mac`.
5. Save the project, then run:

   ```sh
   python3 scripts/configure-signing.py --import-xcode
   ```

This saves your choices in **`Config/Local.xcconfig`**, which Git ignores, and restores the checked-in project to generic settings. Reopen the project in Xcode after the helper finishes. Do not publish this local file or your Xcode user data. Keep a private copy so future rebuilds use the same identities.

The import helper requires matching Debug and Release signing choices. If it reports a mismatch, open the target's **Build Settings**, choose **All** and **Combined**, and set **Development Team** and **Product Bundle Identifier** consistently for both configurations before retrying.

If you already know your ten-character Team ID, you can configure both targets directly instead:

```sh
python3 scripts/configure-signing.py --team YOURTEAMID --bundle-prefix local.youruniquealias.styleus
```

Use your real Team ID and a prefix of your own. The helper sets the `.ipad` and `.mac` identifiers in the ignored local file. Xcode must still have your account signed in and able to create an Apple Development signing certificate. Neither workflow enrolls you in a paid program. If macOS asks to allow signing with your Apple Development key, approve only the key belonging to the account you selected.

## 3. Build and run the Mac companion

Quit any running copy of Styleus using **Quit Styleus** in its menu-bar menu. Closing its window leaves the companion running.

From Terminal in the project folder:

```sh
zsh scripts/build.sh
```

This builds the Mac app and compiles unsigned iPad device and simulator variants. Logs are saved under `build/`. On success, open **`dist/Styleus Mac.app`** in Finder. Keep this folder in a stable location and always open this copy. It avoids confusion between the installed companion and temporary Xcode build copies.

Alternatively, choose the **StyleusMac** scheme and **My Mac** destination in Xcode, then Run. Use the script's stable `dist/` copy for everyday use and give Accessibility permission to that final copy.

In the companion, choose **Open Accessibility Settings**. Under **System Settings → Privacy & Security → Accessibility**, add and enable the exact app you built. This authorizes pointer movement, clicks, drags and scrolling. Styleus does not need Screen Recording or Input Monitoring permission. [Apple's Accessibility guide](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)

If the apps connect but input remains blocked:

1. Quit Styleus from its menu-bar menu.
2. Remove an obsolete Styleus entry from Accessibility using **−**.
3. Use **+** to add the current `dist/Styleus Mac.app`, then enable it.
4. Open that same app again and reconnect.

Reusing the same signing identity and app location helps keep permission consistent, but macOS can request approval again after a signing change. If Styleus requests access to its existing pairing item in Keychain, approve only the app you just built. Do not grant permissions to unrelated downloaded binaries.

## 4. Build and install the iPad app

For the first installation, use Xcode so any account or device issue is visible:

1. Select the **StyleusPad** scheme and your **physical iPad** as the run destination.
2. Confirm **Signing & Capabilities** shows your Personal Team and no unresolved signing error.
3. Click **Run**. Allow Xcode to register the app/device and create a free development provisioning profile if requested.
4. If iPadOS reports **Untrusted Developer**, open **Settings → General → VPN & Device Management**, select the developer identity matching your own Apple Account, and trust it. Then reopen Styleus. Follow any additional verification steps iPadOS shows.
5. Confirm the Styleus icon opens the app normally. You can stop the Xcode debugger and use the icon for everyday launches.

The unsigned iPad product from `scripts/build.sh` is a compile check and cannot be installed. Physical installation needs the signing configuration and approvals above.

After that first setup, the helper can build, sign, install and launch the current source:

```sh
xcrun devicectl list devices
zsh scripts/install-ipad.sh 'YOUR_DEVICE_IDENTIFIER_OR_NAME'
```

Replace the quoted argument with your iPad's identifier or name from the device list. Keep it connected and unlocked. The device identifier is usually less ambiguous than a name. If the script cannot prepare or sign the app, open Xcode and resolve the reported issue there rather than repeatedly retrying.

## 5. Pair and connect

1. Connect the unlocked iPad to the Mac with a **USB data cable**. USB-C / wired is the default. The trusted cable connection must expose a wired network interface; charging alone is insufficient. Alternatively, choose **Settings → Connection → Connect using → Wi-Fi** and put both devices on the same local Wi-Fi network.
2. On the Mac, choose **Pair iPad**. Approve Local Network access when prompted. The Mac shows a private QR code and starts listening.
3. On the iPad, choose **Pair Mac → Scan Mac QR Code**. Grant Camera permission to scan, or enter the long text code instead.
4. Scan your Mac's code. Treat it like a password and keep it out of screenshots, issue reports and Git commits.
5. Tap **Connect** and approve the iPad's **Local Network** prompt. If the permission prompt interrupted the first attempt, tap Connect again afterward.
6. Confirm both apps show connected and that the Mac reports Accessibility enabled.

The connection status is beside **Styleus** on the iPad. Tap **ⓘ** for the complete message, relevant checks and connection/timing details. Opening details releases active input. Disconnect stays visible while connecting or connected.

Change the connection under **Settings → Connection**. Changing it disconnects safely; tap Connect again. Wired mode never falls back silently to Wi-Fi. It uses the public IP interface exposed by a trusted USB link, not a driver or raw-USB helper. Public networking APIs classify compatible Ethernet and USB network paths together as wired.

**Wired operation has been tested on development hardware, including with iPad Wi-Fi disabled. A clean Mac without Xcode/device preparation has not yet been validated for plug-and-play USB operation.** Wi-Fi remains available, but network conditions can affect responsiveness. Networks with client isolation may block discovery.

Permissions are under **iPad Settings → Privacy & Security → Local Network / Camera** and **Mac System Settings → Privacy & Security → Local Network / Accessibility**. Camera permission is only for QR scanning; text pairing works without it. Only Accessibility authorizes Mac input control. [Apple's local-network privacy notes](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

Pairing uses an encrypted, authenticated local connection, with its random secret stored in each app's local Keychain. There is no account service or cloud relay. **Forget Pairing** removes the local secret; forget on both devices to remove the relationship entirely. **Replace Pairing** on the Mac revokes the old pairing and generates a new code.

After an interruption, start the Mac listener if necessary and tap **Connect** again. Reconnect always begins with released input; old gestures do not resume. The displayed round-trip value is a recent communication measurement, not total Pencil-to-screen latency.

## 6. Renew the iPad app every seven days

Apple's free Personal Team provisioning expires **seven days after issuance**. When it expires, the iPad app may stop opening until it is re-signed and installed again. This source distribution does not remove that requirement. [Apple's current free-account rules](https://developer.apple.com/help/account/basics/about-your-developer-account/)

To renew:

1. Keep the existing app on the iPad. **Do not delete it as a routine renewal step.**
2. Connect and unlock the iPad. Open the same source folder with the same `Config/Local.xcconfig`.
3. Keep the **same Apple Account, Personal Team and iPad bundle identifier**.
4. Select **StyleusPad** and your physical iPad in Xcode, then Run to build and reinstall. Alternatively, run:

   ```sh
   zsh scripts/install-ipad.sh 'YOUR_DEVICE_IDENTIFIER_OR_NAME'
   ```

5. Open Styleus from its icon and reconnect. If signing fails, check Xcode's account status and Signing & Capabilities. You do not need to purchase a membership.

An in-place reinstall normally retains app settings and pairing. Changing identifiers or signing teams can create a separate app or make old Keychain items inaccessible; pair again if required. Do not keep generating fresh identifiers to work around renewal errors.

Apple currently limits Personal Teams to **10 App IDs, 3 registered devices and 3 installed apps per device**. App ID/device registrations also expire after seven days. These are Apple limits and may change; check the linked page when troubleshooting. This weekly provisioning step applies to the iPad installation; you do not need to repeat the Mac installation as part of it.

## 7. Navigate and annotate

Choose **Trackpad** from the mode menu for everyday pointer use:

| Action | Gesture |
| --- | --- |
| Pointer movement | Slide the Pencil lightly, then lift to reposition. |
| Left click | Tap briefly and lift. Small tap wobble does not move the cursor. |
| Double click | Tap twice quickly in approximately the same place. |
| Right click | Hold still for at least half a second, then lift. |
| Drag | Press more firmly while moving. Ease pressure or lift to release. |
| Modified click/drag | Hold a modifier key on the **Mac keyboard** until the Pencil gesture finishes. |

Use **two fingers together on the main surface** to scroll in either mode. Flick for a glide; a new finger or Pencil contact stops it. One finger does not move or click the pointer and cannot start scrolling. Pencil contact takes priority: after using the Pencil, lift it and all resting fingers before starting a new two-finger scroll. Three or more fingers cancel scrolling until all lift.

Under **Settings → Scrolling**, adjust scrolling speed independently of Pencil sensitivity, and reverse vertical or horizontal scrolling separately. With vertical reversal off, pulling down reveals text above. With horizontal reversal off, pulling right reveals content to the left. The setting descriptions explain the reversed choices. Changing scroll settings stops any ongoing glide.

Under **Settings**, adjust pointer sensitivity and **Pressure needed**. The left-edge meter is outside the movement area: it fills upward with pressure, marks the activation threshold and turns orange during a drag or stroke. The release threshold is slightly lower than the activation threshold to avoid repeated starts/stops from tiny changes. No drag stays locked across Pencil lifts. The meter reports local input, not acknowledgment from the Mac app.

For basic paper annotation:

1. Open a disposable PDF on the Mac and select the annotation app's ink/pen tool.
2. In Styleus on the Mac, select a display, or choose **Select Region on Display** and drag around the canvas using the Mac's own trackpad. Region selection stops control; reconnect afterward.
3. Bring the annotation app to the front and choose **Drawing tablet** on the iPad.
4. Look at the Mac while writing. Light Pencil contact positions the pointer; firmer pressure draws. Ease pressure or lift to end each stroke.

The outlined active area preserves the target's aspect ratio. Gray margins are inactive; entering one ends the stroke and requires lifting before another stroke. Re-select a custom region if the Mac canvas moves. Zotero basic mouse annotation has been physically tested. Test other apps on a disposable document before relying on them.

Pressure changes mouse-button activation, **not ink width or tilt in Zotero, Notability or other drawing apps**. This is basic mouse drawing rather than universal tablet-driver support. Use the [hardware checklist](docs/hardware-checklist.md) to test your setup.

## Troubleshooting and updates

- **Connected but no pointer:** check the Mac's Accessibility status and approve the exact current app copy, as described above.
- **Wired discovery fails:** check the selected connection, data cable, device trust, unlocked iPad and Local Network permission. A cable does not guarantee the OS exposed the required network interface.
- **Wi-Fi discovery fails:** check both devices are on the same local network, with Local Network permission and no client isolation. No cleartext or internet fallback is used.
- **Input seems stuck:** tap **Disconnect** on the iPad or **Disconnect and stop** in the Mac menu bar. After an abnormal Mac process termination, a physical trackpad click may be needed; a killed process cannot run a release handler.
- **Version mismatch:** update both apps from the same source version. Quit the Mac companion from its menu-bar menu before rebuilding/reopening it; closing its window is insufficient.
- **Updating source:** keep your ignored local signing configuration private, build both apps and install the iPad update in place. If new source files were added manually, run `python3 scripts/generate_project.py` before building.

Run the automated checks from the project folder:

```sh
zsh scripts/test.sh
python3 -m unittest discover -s scripts/tests -v
```

The Swift suite checks the core and transport. The Python suite checks public project generation, private signing preservation and helper argument handling without installing apps. Build/test success does not replace physical verification of Pencil input, app compatibility or responsiveness. See [validation](docs/validation.md) for the evidence and limitations.

# Hardware acceptance checklist

Use disposable files, a blank test note or a harmless window. Run this checklist on each release and record your own results locally; do not publish device identifiers, pairing codes, account details or personal documents. Earlier observations are summarized in [validation](validation.md); blank boxes below require a new run.

## Installation and connection

- [ ] Build the Mac and iPad apps using your own free signing configuration; launch from their icons after quitting Xcode.
- [ ] Approve Mac Accessibility and local-network access; approve iPad camera only if using QR scanning.
- [ ] Pair by QR and separately try the text fallback. Only the intended paired iPad should control the Mac.
- [ ] Replace pairing on the Mac. The old credential must fail; scan the new credential to reconnect.
- [ ] Connect over USB-C / wired with iPad Wi-Fi disabled. Repeat after restarting the Mac and iPad without opening Xcode. Record any developer preparation that was required.
- [ ] Select Wi-Fi in Settings, connect on the same local network, then switch back to wired. Each change releases input and requires explicit Connect.
- [ ] Try the wrong connection type or stop the Mac listener. Tap the info icon and confirm the full error and relevant next steps are readable. Reconnect successfully; old error guidance must clear.

## Trackpad and pressure

- [ ] Slide the Pencil lightly; lift, reposition far away and resume. There is no jump or extra click after movement.
- [ ] Tap a small target, double-tap it, then hold still for at least half a second and lift. Expect left click, double click and right click with no cursor wobble.
- [ ] Compare movement sensitivity settings; deliberate movement remains controllable and tapping stays stable.
- [ ] Press more firmly while moving a harmless window. Ease pressure and then try lifting to release. Neither release adds a click.
- [ ] Change Pressure needed; verify the meter's activation mark and the effort needed for a drag change together.
- [ ] Hold Mac Command and tap to add a selection; Shift-tap a range; Control-tap for a menu; Option-drag a disposable file to copy it. Release modifiers and check ordinary input again.
- [ ] Rest a palm before, during and after Pencil movement. It must not move, click or scroll. Lift all resting fingers before intentionally scrolling.

## Two-finger scrolling

- [ ] Slide two fingers vertically/horizontally in both modes. The pointer stays still; one finger alone does not scroll.
- [ ] Lift/re-add a finger without jumps. A third finger cancels until all fingers lift.
- [ ] Compare slow slides and fast swipes, then different Scrolling speed settings.
- [ ] Flip each reversal setting independently. With reversal off, pulling down reveals text above and pulling right reveals content to the left.
- [ ] Flick and lift for a smooth glide. Touch with one finger or the Pencil to stop. Pause before lifting and verify no large residual glide.
- [ ] Change mode, rotate or disconnect during scrolling. No old scroll delta or momentum resumes.
- [ ] If another mouse utility is installed, compare delivered behavior with it running. The optional Test Scrolling window records only its own disposable test page.

## Absolute mapping and drawing

- [ ] Select each display, including one left/above the main display if available. Check active-area corners and center.
- [ ] Select a custom region using the Mac trackpad and check placement. Re-select when the target app's canvas moves.
- [ ] Draw circles and squares in landscape and portrait. Aspect ratio must be preserved.
- [ ] Move lightly without ink; press for a stroke; ease or lift to end. Start elsewhere. No connecting line may appear.
- [ ] Leave an active drawing area while drawing and re-enter without lifting. Drawing stays blocked until a fresh contact.
- [ ] Test each receiving app on disposable content. Ordinary mouse drawing does not prove pressure-sensitive ink or tilt support.

## Layout and interruptions

- [ ] In landscape, the vertical meter is outside the movement area, status/info sit beside Styleus and Disconnect stays visible. In portrait, controls remain reachable.
- [ ] Open Settings and the connection info popup during a harmless pressure drag. Held input releases; continued contact does not restart until a new contact.
- [ ] Switch modes or rotate during a pressure stroke. It stops and requires lifting before further input.
- [ ] Unplug the cable during a drag; after one second move the Mac trackpad without clicking. The window stays put. Reconnect explicitly; the old drag never resumes.
- [ ] Background or lock the iPad, open Control Center, lock/sleep the Mac, quit the companion normally, or remove a target display during input. Verify release and clean reconnect.
- [ ] If enabling the optional Mac cursor ring, check no focus change/click interception, proper hiding and placement across displays/full-screen apps. Default Off leaves only the local iPad feedback.
- [ ] Renew the iPad app after actual provisioning expiry using the same team and identifiers. Verify preferences and pairing, or record any necessary re-pairing.

Process termination by the OS cannot execute a cleanup handler. If a process crash leaves a button logically held, use the physical Mac mouse/trackpad to click and release. The watchdog covers network stalls while the companion is running.

## Experimental pinch zoom

These checks are pending for the direct Styleus implementation. Keep Hammerspoon closed; it is not a dependency. Use a disposable document or test page.

- [ ] Update both native apps and reconnect. Confirm an older peer is rejected with an app-version message.
- [ ] With Experimental pinch zoom off, verify the accepted two-finger scroll and glide behavior is unchanged.
- [ ] Enable Settings → Pinch to zoom → Experimental pinch zoom. Spread and contract two fingers in both input modes. The target should zoom without moving the pointer or scrolling at the same time.
- [ ] Slide two fingers together to scroll, then vary their spacing after scrolling starts. The gesture must remain scrolling until both fingers lift. Repeat starting with pinch: it must stay zoom until lift.
- [ ] Check small and large pinches in each intended Mac app. Chromium-based browsers may need a larger initial span change; record app/version and perceived response rather than assuming universal support.
- [ ] Lift and replace one finger during zoom. No jump or resumed gesture should occur until both fingers have lifted.
- [ ] Rest a palm during Pencil use, then lift the Pencil with the palm still down. No zoom should start. Lift the entire hand before a new finger gesture.
- [ ] Start zoom, then touch with the Pencil, add a third finger, rotate, switch modes or change the setting. Zoom must stop, and fresh contact must be required.
- [ ] Disconnect/unplug or background during zoom, reconnect explicitly, and verify no old zoom resumes. Switch the foreground Mac app during a pinch; continued movement must not zoom the newly focused app.
- [ ] Run Test Pinch Zoom… on the Mac only in its disposable test window. Confirm the native receiver reports magnification events and changing page scale. This Mac-only check does not replace physical iPad testing.

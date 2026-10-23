# Native pinch zoom feasibility

Research date: 2026-10-23. This investigation follows the decision to investigate smooth zoom before considering a keyboard-shortcut fallback. Initial public-API research was followed by an authorized, isolated Hammerspoon experiment. Hammerspoon's Accessibility permission was manually approved by the user. Production Styleus input behavior and signing remain unchanged; no driver, browser extension or shortcut fallback was added.

## Finding

An isolated experiment delivered phased native magnification events through Hammerspoon's undocumented event-construction route on macOS 26.5.2. A custom AppKit receiver, a standard `WKWebView` and a disposable page in Arc responded to those events. This establishes a viable experimental Mac output path for those test conditions; it does not establish physical iPad pinch behavior, visual smoothness, latency or compatibility with every app.

The public AppKit/Core Graphics APIs inspected here still do not provide a supported magnification-event constructor. A virtual HID device is a separate, entitlement-gated architecture, and creating a generic touchpad does not establish that macOS will recognize native pinch gestures from it. Supported continuous zoom APIs also exist **inside an app that owns its content**. The user chose to keep the experiment only for now. Production pinch integration is deferred, and Styleus has no added Hammerspoon runtime dependency.

## iPad recognition and existing input safety

UIKit's [`UIPinchGestureRecognizer`](https://developer.apple.com/documentation/uikit/handling-pinch-gestures) tracks changes in the distance between two fingers. Its [`scale`](https://developer.apple.com/documentation/uikit/uipinchgesturerecognizer/scale) is relative to the gesture's starting distance, rather than an incremental change on each callback. A custom recognizer can use the same distance ratio while sharing the app's existing direct-touch tracking.

Any integration must arbitrate between scrolling and pinching before sending input, retain stable finger identities, and prevent a single movement from both scrolling and zooming. Pencil contact, resting palms, cancellation, rotation, additional fingers and reconnection must retain the current suppression and release rules. Fresh contact must cancel scrolling momentum. These are implementation requirements; they have not yet been tested for a new pinch recognizer.

## System-wide output routes

| Route | Evidence | Consequence for Styleus |
| --- | --- | --- |
| Public AppKit/Core Graphics magnification event | AppKit exposes a read-only magnification value and responder methods; the inspected SDK has no public magnification `CGEventType`, field or constructor. | No supported system-wide construction route identified. |
| CoreHID / `IOHIDUserDevice` | Virtual device creation requires an entitlement. HID reports describe contacts; macOS must still interpret those contacts as trackpad gestures. | Separate authorization and compatibility investigation, beyond the current free-signing workflow. |
| HIDDriverKit event service | Public API dispatches digitizer touch data, within a DriverKit extension. | Requires a driver architecture and its signing/activation requirements; native pinch compatibility remains unproven. |
| Undocumented serialized gesture events | Hammerspoon constructed events that were delivered and changed magnification in isolated AppKit, WebKit and Arc tests. | Experimentally viable for those cases, with OS/app compatibility and licensing limits; not a supported public-API solution or a physically tested Styleus feature. |

### AppKit and Core Graphics

[`NSEvent.magnification`](https://developer.apple.com/documentation/appkit/nsevent/magnification) describes a received gesture. [`NSResponder.magnify(with:)`](https://developer.apple.com/documentation/appkit/nsresponder/magnify(with:)) handles it within a receiving app. Apple's [trackpad-event guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html) describes delivery through the receiving app's responder chain; it does not provide an external gesture-injection API.

[`CGEvent`](https://developer.apple.com/documentation/coregraphics/cgevent) supports public keyboard, mouse and scroll construction/posting. The installed macOS 26.5 SDK's `CGEvent.h`, `CGEventTypes.h` and `NSEvent.h` were inspected. Magnification is read-only in `NSEvent.h`, and there is no public Core Graphics magnification event declaration. This is an inspection finding, rather than proof that no undocumented system mechanism exists.

**Initial local runtime probe:** on macOS 26.5.2, an Objective-C scratch program called the public `NSEvent` custom-event factory with `NSEventTypeMagnify`. The factory rejected it with `Invalid parameter not satisfying: _NSEventMask64FromType(type) & WeirdMask`. No events were posted by that probe. This is consistent with the documented purpose of [`otherEvent(...)`](https://developer.apple.com/documentation/appkit/nsevent/otherevent(with:location:modifierflags:timestamp:windownumber:context:subtype:data1:data2:)): creating custom events, rather than constructing magnification gestures. Undocumented construction was tested separately afterward, through Hammerspoon as described below.

### Virtual HID and DriverKit

Apple's [`HIDVirtualDevice`](https://developer.apple.com/documentation/corehid/hidvirtualdevice) and [virtual-device tutorial](https://developer.apple.com/documentation/corehid/creatingvirtualdevices) describe emulating a device and sending HID reports. The installed CoreHID Swift interface makes this API available from macOS 15; Styleus currently supports macOS 14. An optional implementation would need an availability check or a separate compatibility decision.

The installed public `IOHIDUserDevice.h` explicitly requires `com.apple.developer.hid.virtual.device` for `IOHIDUserDeviceCreateWithProperties`. The requirement is also enforced in Apple's open-source [`IOHIDResourceDeviceUserClient::initWithTask`](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDResourceUserClient.cpp): the developer entitlement, or Apple's separate privileged entitlement, must be present. A plain root process does not satisfy the entitlement check shown in that implementation. This source is evidence of the published implementation, not a guarantee about every macOS release.

Apple documents the [virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device). Its separate [DriverKit virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.driverkit.family.hid.virtual.device) requires an entitlement request. The naming and availability of a capability in documentation should not be treated as approval to use it.

DriverKit also provides [`dispatchDigitizerTouchEvent`](https://developer.apple.com/documentation/hiddriverkit/iouserhideventservice/dispatchdigitizertouchevent). This is a driver event-service method, not an ordinary unentitled app-level replacement for `CGEvent`. Apple's [DriverKit entitlement process](https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development) requires matching entitlements and provisioning; the containing app activates the extension. [System Extensions and DriverKit](https://developer.apple.com/system-extensions/) are also covered by Apple's entitlement request process.

No virtual device or driver was created, signed or installed during this investigation. No entitlement was requested, and System Integrity Protection was not changed. This route is outside the currently documented zero-cost Personal Team workflow. Distribution normally entails appropriate developer-program signing and Apple approval; paid membership alone would not establish approval or gesture compatibility. Apple's [membership details](https://developer.apple.com/programs/whats-included/) and [managed-capability process](https://developer.apple.com/help/account/capabilities/capability-requests) describe those account resources.

Crucially, a standards-based touchpad descriptor is not proof of native Mac gesture support. A [hardware developer's report on Apple's forums](https://developer.apple.com/forums/thread/768586) describes HID digitizer contacts arriving on macOS 14.7 without producing pointer movement or gestures, including with a custom `dispatchDigitizerTouchEvent` service. This is a developer's report, not an Apple compatibility guarantee or a result reproduced on the current Mac. The established [Karabiner virtual HID project](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) implements keyboard and mouse output; it does not provide an existing native-pinch backend to adopt.

### Undocumented gesture serialization

Hammerspoon's [`newGesture` implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap_event.m) delegates to [`TouchEvents.c`](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/TouchEvents.c). That code assembles serialized event bytes, undocumented numeric fields and IOHID structures, then reconstructs a `CGEvent`. Calling public serialization functions around a private payload does not make the payload a documented API.

Licensing needs component-level review: Hammerspoon's repository has a general [MIT license](https://github.com/Hammerspoon/hammerspoon/blob/master/LICENSE), while `TouchEvents.c` itself carries a 2010 Calf Trail copyright and an all-rights-reserved header, without an explicit license grant in that file. Its [`eventtap.lua` wrapper](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/eventtap.lua) identifies `newGesture` as using Calf Trail's external Touch library and includes a GPL version 2-or-later notice for that library. The originating [Calf Trail Touch project](https://github.com/calftrail/Touch) also describes reverse-engineering work and GPLv2 licensing. No separate permission for the copy was established by this review; no conclusion that the repository-wide MIT license replaces the component notice should be assumed.

Hammerspoon's [open compatibility issue](https://github.com/Hammerspoon/hammerspoon/issues/2902) reports the gesture working in Safari while failing in Chrome and Illustrator, without an established correction in the discussion. The local Arc experiment below provides narrower, current evidence that a full changed-phase sequence can work after Chromium's zoom threshold is crossed. Neither the historical report nor one successful browser test establishes universal compatibility.

Hammerspoon was run as a separate application for the authorized experiment. Its third-party gesture implementation was not copied into Styleus or compiled into either native app. An optional external adapter would require a separate scope decision and preservation of the dependency's component notices; no such adapter has been integrated.

## Isolated native event experiment

The following tests ran on macOS 26.5.2 with Hammerspoon 1.1.1 after the user manually granted its Accessibility permission. The scratch timers were retained until their callbacks completed. Synthetic events were tagged to distinguish them from physical trackpad input; no account, device or process identifiers are needed to reproduce the findings. Scratch programs, local pages and CSV captures remain in ignored build output.

| Test | Observed result | Established scope |
| --- | --- | --- |
| Pair posted directly to the disposable receiver process | No receiver rows. | The targeted posting path did not deliver the tested pair under these conditions. |
| Pair posted through the session event stream | Receiver recorded `began` with zero magnification, then `ended` with `0.125`. | The session path delivered native magnify events to the receiver. |
| Phased continuous sequence | Receiver recorded 32 tagged magnify events: one began, 30 changed and one ended. The custom receiver's final cumulative scale was approximately `1.0`. | Fractional changes and phase boundaries were delivered; the increase/decrease sequence returned to its starting scale. |
| Cancellation | Receiver recorded a cancelled magnify phase. | Cancellation survived the tested event-construction and posting path. |
| Standard WebKit view | With `allowsMagnification` enabled, 31 observations progressed from `1.0` through `1.253409879` to `1.046524970`. | Built-in WebKit magnification responded without a custom magnify handler or calls to `setMagnification`. |
| Arc disposable local page | A larger monotonic sequence produced native Ctrl-wheel and viewport resize events; `visualViewport.scale` progressed from `1.0` to `1.298405886`. | The tested Arc page performed proportional visual zoom after the native threshold was crossed. |

Hammerspoon's [`post` implementation](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/eventtap/libeventtap_event.m) uses different paths for a specified application and the session stream. It returns the event rather than a delivery acknowledgment; the receiving application and page telemetry supplied the evidence above. Its [`timer` implementation](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/timer/libtimer.m) stops a timer when its Lua object is garbage-collected, which is why callback retention was part of the experiment.

The continuous test used Hammerspoon's gesture constructor for fractional magnification and the undocumented gesture-phase field `0x84` for began, changed, ended and cancelled values (`1`, `2`, `4`, `8`). The phase values correspond to public `CGGesturePhase` constants, but using them with this undocumented magnification field is experimental behavior derived from the [external constructor's implementation](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/eventtap/TouchEvents.c). Hammerspoon's named scroll-phase property is a different field and was not treated as an equivalent.

### Chromium threshold and page handling

The first small Arc sequence generated Ctrl-wheel events but did not change viewport scale. Chromium's [native pinch handler](https://github.com/chromium/chromium/blob/main/content/browser/renderer_host/render_widget_host_view_mac.mm) accumulates scale from `1.0` and disables zoom until that product is below `0.667` or above `1.5`. Its ordinary [AppKit entry point](https://github.com/chromium/chromium/blob/main/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm) does not mark an event as internally injected, so the threshold applies. The [event builder](https://github.com/chromium/chromium/blob/main/components/input/web_input_event_builders_mac.mm) converts each AppKit magnification to an incremental factor by adding `1.0`.

The follow-up Arc sequence sent 30 incremental magnifications of `0.022` and crossed the threshold. The viewport then changed proportionally. The initial threshold consumes part of the input before zoom becomes active, so total sent scale must not be equated with final viewport scale.

Chromium deliberately offers [cancellable Ctrl-wheel events before applying pinch zoom](https://chromium.googlesource.com/chromium/src/+/HEAD/content/browser/renderer_host/input/README.md). The disposable page's recorder used a passive listener and never called `preventDefault`. Browser or page behavior may still affect real websites; this local result is not a guarantee for all sites or Chromium versions.

### Limits of the experiment

- No physical iPad pinch input, gesture arbitration or end-to-end network behavior was tested.
- Telemetry shows changing native scale values; visible smoothness, anchor behavior and latency were not measured.
- Safari was attempted, but its telemetry was not isolated well enough to claim a pass or failure.
- Zotero, Notability and the ChatGPT Mac app were not validated with this experimental native output path.
- No driver, privileged helper, security relaxation, production input handler or shortcut fallback was added.

## Narrower smooth-zoom integrations

### App-owned WebKit content

[`WKWebView.setMagnification(_:centeredAt:)`](https://developer.apple.com/documentation/webkit/wkwebview/setmagnification(_:centeredat:)) is a public API for visual magnification around a specified point in a web view the app owns. This is a credible small experiment for proving continuous pinch transport and rendering in a controlled native Mac window. It does not let Styleus reach into Safari, Zotero, ChatGPT or arbitrary third-party windows. A successful local WebKit test would establish only this app-owned route.

AppKit's [`NSScrollView.setMagnification(_:centeredAt:)`](https://developer.apple.com/documentation/appkit/nsscrollview/setmagnification(_:centeredat:)) offers a similar supported route for an app's own document view. Neither API gives Styleus ownership of another process's view.

**Initial app-owned API probe:** on macOS 26.5.2, an invisible scratch `WKWebView` loaded generic local HTML with no network content. Calls centered at `(400, 300)` requested magnifications `1.000`, `1.013`, `1.027`, `1.041`, `1.068`, `1.040` and `1.020`; property readback matched each value within `0.00001`. This confirmed that the public app-owned API accepts small proportional increases and decreases. That initial probe posted no global input. The later event-delivery experiment above additionally exercised WebKit's built-in response to native magnify events; neither probe establishes physical iPad behavior or perceptual smoothness.

### Browser extension

A browser extension can use documented native messaging to exchange authenticated local commands with a companion: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) and [Safari app/extension messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension). This adds an extension, permissions and browser-specific setup.

[`chrome.tabs.setZoom`](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-setZoom) accepts a numeric factor, but its page/layout zoom is not equivalent to native trackpad visual magnification. WebKit's [tab zoom factor](https://developer.apple.com/documentation/webkit/wkwebextensiontab/zoomfactor(for:)) likewise defaults to page zoom. Arbitrary numeric values do not by themselves establish smooth animation.

A more relevant browser-specific experiment is Chrome's documented [`debugger` extension API](https://developer.chrome.com/docs/extensions/reference/api/debugger) with the **experimental** DevTools [`Input.synthesizePinchGesture`](https://chromedevtools.github.io/devtools-protocol/tot/Input/#method-synthesizePinchGesture) or [`Emulation.setPageScaleFactor`](https://chromedevtools.github.io/devtools-protocol/tot/Emulation/#method-setPageScaleFactor). This targets a browser page, requires the powerful debugger permission, and must be tested for live finger tracking, anchor behavior and page compatibility. Repeated generated gestures are not known to feel like one continuous native pinch. An unpacked local prototype can avoid store publication, but no extension was installed or authorized here.

Synthetic JavaScript wheel/gesture events are not a substitute for native input: [UI Events distinguishes untrusted script-generated events](https://w3c.github.io/uievents/#trusted-events). CSS zoom or transforms alter page presentation and should not be represented as system magnification.

### Zotero

Zotero's own [`pdf.js` viewer source](https://github.com/zotero/pdf.js/blob/master/web/app.js) has a pinch path that applies a scale factor and origin through `PDFViewerApplication.updateZoom`. The [reader wrapper](https://github.com/zotero/reader/blob/master/src/pdf/pdf-view.js) reaches that viewer internally, while exposing ordinary zoom-in/out/reset operations. An authenticated Zotero plugin could therefore be investigated as a route to proportional PDF zoom.

This is an inference from source code, not a stable external API or an implemented integration. The documented [reader plugin event handlers](https://www.zotero.org/support/dev/zotero_7_for_developers#custom_reader_event_handlers) do not establish a public continuous-zoom bridge. A proof would require a plugin, supported-version checks, a disposable PDF, cancellation tests and physical verification. It would apply to Zotero's reader rather than all Mac apps.

### Other applications

Electron exposes [zoom-factor and visual-zoom APIs](https://www.electronjs.org/docs/latest/api/web-contents) to the application owning its `webContents`; these do not grant another app external control. There is no basis for assuming an arbitrary Mac app is Electron-based. No supported external magnification integration for the installed ChatGPT Mac app was identified; a browser route would concern the ChatGPT website instead.

No documented external zoom API for Notability was identified. Its [current desktop support information](https://support.gingerlabs.com/en-us/articles/16634098-notability-for-windows-and-mac) describes multiple distribution paths; compatibility must be checked for the actual app version, rather than inferred from another desktop edition.

## Decision and conditions for future work

1. **Current decision: keep the experiment only.** Production pinch integration is deferred. No Hammerspoon dependency or external helper was added to Styleus, and existing Pencil and scrolling behavior remain unchanged.
2. If the work is revisited, obtain agreement on the external dependency and undocumented event route before integration. Then implement and test physical two-finger recognition, scroll/pinch arbitration, palm rejection, session expiry, cancellation, focus changes and disconnect behavior. Use disposable content in each target app and verify the actual perceived zoom, rather than reporting only emitted values. Keep third-party constructor code outside the native app source.
3. Validate Zotero and the user's other actual target apps individually. Consider browser- or reader-specific APIs only if the experimental native path fails a target's required behavior, with the additional setup and compatibility scope explained first.
4. Treat virtual-HID/DriverKit work as a separate proposed scope with entitlement, signing and compatibility questions resolved before implementation. Do not enroll, pay, weaken system security or add a privileged helper to the current free app implicitly.

The research establishes concrete platform boundaries and testable experiments. It does not establish universal pinch compatibility, low latency, or a completed zoom feature.

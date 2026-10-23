# Native pinch zoom feasibility

Research date: 2026-10-23. This investigation follows the decision to investigate smooth zoom before considering a keyboard-shortcut fallback. It makes no change to Styleus input behavior, signing, system security, browser configuration or installed extensions.

## Finding

Recognizing a two-finger pinch on the iPad is straightforward. Delivering the equivalent of a native Mac trackpad magnification gesture to an arbitrary Mac app is the unresolved part. The public AppKit/Core Graphics APIs inspected here do not provide a supported magnification-event constructor. A virtual HID device is a separate, entitlement-gated architecture, and creating a generic touchpad does not establish that macOS will recognize native pinch gestures from it.

There are supported continuous zoom APIs **inside an app that owns its content**. Browser-specific integrations may also offer a useful proof of concept. These have narrower compatibility and different setup requirements than system-wide trackpad emulation. No smooth zoom integration has been physically verified in Styleus, and no shortcut fallback has been implemented.

## iPad recognition and existing input safety

UIKit's [`UIPinchGestureRecognizer`](https://developer.apple.com/documentation/uikit/handling-pinch-gestures) tracks changes in the distance between two fingers. Its [`scale`](https://developer.apple.com/documentation/uikit/uipinchgesturerecognizer/scale) is relative to the gesture's starting distance, rather than an incremental change on each callback. A custom recognizer can use the same distance ratio while sharing the app's existing direct-touch tracking.

Any integration must arbitrate between scrolling and pinching before sending input, retain stable finger identities, and prevent a single movement from both scrolling and zooming. Pencil contact, resting palms, cancellation, rotation, additional fingers and reconnection must retain the current suppression and release rules. Fresh contact must cancel scrolling momentum. These are implementation requirements; they have not yet been tested for a new pinch recognizer.

## System-wide output routes

| Route | Evidence | Consequence for Styleus |
| --- | --- | --- |
| Public AppKit/Core Graphics magnification event | AppKit exposes a read-only magnification value and responder methods; the inspected SDK has no public magnification `CGEventType`, field or constructor. | No supported system-wide construction route identified. |
| CoreHID / `IOHIDUserDevice` | Virtual device creation requires an entitlement. HID reports describe contacts; macOS must still interpret those contacts as trackpad gestures. | Separate authorization and compatibility investigation, beyond the current free-signing workflow. |
| HIDDriverKit event service | Public API dispatches digitizer touch data, within a DriverKit extension. | Requires a driver architecture and its signing/activation requirements; native pinch compatibility remains unproven. |
| Undocumented serialized gesture events | An established open-source tool constructs private event payloads manually. | A possible unsupported experiment, with OS/app compatibility and licensing concerns; not a supported public-API solution. |

### AppKit and Core Graphics

[`NSEvent.magnification`](https://developer.apple.com/documentation/appkit/nsevent/magnification) describes a received gesture. [`NSResponder.magnify(with:)`](https://developer.apple.com/documentation/appkit/nsresponder/magnify(with:)) handles it within a receiving app. Apple's [trackpad-event guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html) describes delivery through the receiving app's responder chain; it does not provide an external gesture-injection API.

[`CGEvent`](https://developer.apple.com/documentation/coregraphics/cgevent) supports public keyboard, mouse and scroll construction/posting. The installed macOS 26.5 SDK's `CGEvent.h`, `CGEventTypes.h` and `NSEvent.h` were inspected. Magnification is read-only in `NSEvent.h`, and there is no public Core Graphics magnification event declaration. This is an inspection finding, rather than proof that no undocumented system mechanism exists.

**Local runtime probe:** on macOS 26.5.2, an Objective-C scratch program called the public `NSEvent` custom-event factory with `NSEventTypeMagnify`. The factory rejected it with `Invalid parameter not satisfying: _NSEventMask64FromType(type) & WeirdMask`. No events were posted. This is consistent with the documented purpose of [`otherEvent(...)`](https://developer.apple.com/documentation/appkit/nsevent/otherevent(with:location:modifierflags:timestamp:windownumber:context:subtype:data1:data2:)): creating custom events, rather than constructing magnification gestures. No undocumented numeric fields or private constructors were tested.

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

Hammerspoon's [open compatibility issue](https://github.com/Hammerspoon/hammerspoon/issues/2902) reports the gesture working in Safari while failing in Chrome and Illustrator. That historical report is not a current compatibility test, but it prevents a universal-support claim. No third-party code was downloaded into Styleus, compiled, run or incorporated.

## Narrower smooth-zoom integrations

### App-owned WebKit content

[`WKWebView.setMagnification(_:centeredAt:)`](https://developer.apple.com/documentation/webkit/wkwebview/setmagnification(_:centeredat:)) is a public API for visual magnification around a specified point in a web view the app owns. This is a credible small experiment for proving continuous pinch transport and rendering in a controlled native Mac window. It does not let Styleus reach into Safari, Zotero, ChatGPT or arbitrary third-party windows. A successful local WebKit test would establish only this app-owned route.

AppKit's [`NSScrollView.setMagnification(_:centeredAt:)`](https://developer.apple.com/documentation/appkit/nsscrollview/setmagnification(_:centeredat:)) offers a similar supported route for an app's own document view. Neither API gives Styleus ownership of another process's view.

**Local runtime probe:** on macOS 26.5.2, an invisible scratch `WKWebView` loaded generic local HTML with no network content. Calls centered at `(400, 300)` requested magnifications `1.000`, `1.013`, `1.027`, `1.041`, `1.068`, `1.040` and `1.020`; property readback matched each value within `0.00001`. This confirms that the public app-owned API accepts small proportional increases and decreases. It does not verify visible anchor behavior, animation smoothness, finger-to-screen latency, external-app control or a physical iPad gesture. No global input events were posted and no other apps were controlled.

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

## Recommended next scope

1. The public WebKit magnification/readback proof has passed in an isolated local view. Any next app-owned prototype must additionally validate visible anchor behavior, continuous physical finger input, cancellation and rendering; the existing proof does not establish those results or external-app support.
2. If zooming ordinary websites is the priority, review a browser-specific proof using documented browser control. Explain and obtain the extension/debugger approval before installation, then test continuous physical input. Do not call layout zoom or isolated scripted pinches native system-wide support.
3. If Zotero is the priority, investigate a version-guarded reader plugin using a disposable document. Keep internal API dependence explicit.
4. Treat virtual-HID/DriverKit work as a separate proposed scope with entitlement, signing and compatibility questions resolved before implementation. Do not enroll, pay, weaken system security or add a privileged helper to the current free app implicitly.

The research establishes concrete platform boundaries and testable experiments. It does not establish universal pinch compatibility, low latency, or a completed zoom feature.

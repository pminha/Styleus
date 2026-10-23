# Design decisions

Styleus provides general Mac navigation and basic annotation through two native Swift apps. This document records product decisions without personal development-session history.

## Input

- UIKit captures Pencil contacts and coalesced samples; SwiftUI presents controls.
- Trackpad movement is relative. Lifting after movement and repositioning do not jump or click. A tap is a left click, two quick taps a double click, and a stationary long press followed by lift a right click.
- Small tap wobble is suppressed. Deliberate movement beyond the tap allowance resumes relative movement without replaying suppressed travel.
- Firmer moving contact starts a left-button drag. Easing pressure or lifting releases it. No right-button drag or persistent drag lock is provided.
- Two fingers scroll in either mode; fingers do not move or click the pointer. Pencil activity takes priority, and resting fingers must lift before another scroll gesture can start.
- Scrolling includes momentum, independent axis reversal and adjustable speed. Its response is custom tuning, not a reproduction of Apple's private trackpad algorithm.

## Drawing

- Absolute positioning maps the fitted active area to a selected Mac display or rectangular region. Aspect ratio is preserved.
- Light contact positions without ink; pressure activation begins basic mouse drawing. Easing pressure or lifting ends the stroke.
- A new stroke begins at its new location with no connecting line. Leaving an inactive margin or interrupting input requires a fresh contact before resuming.
- Pressure activation and the local pressure meter do not establish pressure-sensitive ink in another application. See [pressure support](pressure-support.md).

## Layout

The Minimal edge layout puts a vertical pressure meter outside the movement area on the left, connection status and an information button beside Styleus, and transport selection in Settings. Disconnect remains visible. The mode picker is a menu. The header wraps controls when width is limited. Opening Settings or connection details resets active contact.

The local meter reads current gesture state directly. The optional Mac cursor overlay defaults Off because a separately composited window can trail the cursor.

## Trust and safety

- One explicitly approved pairing is remembered in each device's Keychain. QR scanning has a text fallback.
- USB-C / wired is the default; Wi-Fi remains selectable. There is no silent transport fallback.
- Local sessions are authenticated and encrypted. No relay, public control server, incoming internet port mapping or shared embedded secret is used.
- Reconnection is explicit. Mode changes, rotation, cancellation, backgrounding, disconnects and stale input release held state and prevent replay.
- macOS Accessibility, local-network access and optional camera access require the device owner's approval.

## Source distribution

Styleus is distributed as MIT-licensed source. Users build both apps and sign the iPad app with their own free Personal Team. Personal signing configuration stays in ignored local files. App Store, TestFlight and paid Developer ID distribution are not part of this workflow. Free iPad development provisioning must be renewed after seven days.

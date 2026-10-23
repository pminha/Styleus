---
status: accepted
---

# Add explicit wired transport using the existing authenticated connection

Wired transport is the default because Wi-Fi responsiveness varied during development testing; Wi-Fi remains selectable. Use the public wired IP interface exposed by the trusted USB connection, with the existing TLS pairing and input safety rules; selecting wired transport must never fall back to Wi-Fi automatically. This replaces the Wi-Fi-only restriction in ADR 0001 while preserving its authentication decision.

Network.framework identifies wired interfaces rather than a particular USB connector, so the app says “USB-C / wired.” Apple describes USB virtual networking for development devices in [its developer-support explanation](https://developer.apple.com/forums/thread/737875); that alone does not prove arbitrary app connectivity or low latency. The hardware checklist must establish the route with Wi-Fi disabled, verify cable-removal release, and compare responsiveness. A raw-USB multiplexer, driver, or privileged helper would be a separate scope decision if this public path proves insufficient.

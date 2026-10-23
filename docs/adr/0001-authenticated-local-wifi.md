---
status: accepted
---

# Authenticate local Wi-Fi connections with an out-of-band pairing secret

The initial design uses Network.framework TLS-PSK over TCP, restricted to local Wi-Fi, with a high-entropy random secret transferred by a Mac-displayed QR code or long text code and stored in each device's Keychain. QR/text pairing, a single remembered pair, explicit reconnection and authenticated TLS 1.2 keep enrollment small without trusting discovery names or unauthenticated first contact. The tradeoff is TLS 1.2 without the forward-secrecy guarantees of a certificate-based modern TLS design; a future change to pinned device certificates would require revisiting identity enrollment and persistence.

The original Wi-Fi-only restriction is replaced by [ADR 0002](0002-selectable-wired-transport.md); the authentication and pairing decisions remain in force.

Apple documents the TLS-PSK limitations and recommends Network.framework for new companion networking in [TN3213](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework). Bonjour advertises identity and availability only; it must never carry the secret. Pair replacement revokes the previous credential, and reconnecting never resumes prior held input.

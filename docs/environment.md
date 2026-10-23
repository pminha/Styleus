# Build requirements

Styleus has two native app targets and a host-based Swift test package. There are no third-party runtime dependencies, drivers, privileged helpers, or required cloud services.

| Requirement | Details |
| --- | --- |
| Mac | macOS 14 or later; a macOS version compatible with your chosen Xcode is also required for building. |
| iPad | iPadOS 17 or later and a compatible Apple Pencil. Hover is not required. |
| Xcode | Full Xcode with iOS and macOS SDKs; command-line tools alone cannot build the iPad app. Use a version that can prepare your iPad's installed OS. |
| Apple Account | A free account for Personal Team development signing. Paid enrollment is not required for building on your own devices. |
| Python | Python 3 for the optional project/signing helpers and build-configuration tests. |
| Cable | A USB data cable for device preparation and installation; charging-only cables cannot provide the wired connection. |
| Network | A working trusted wired network link or local Wi-Fi. No cloud relay. |

The source has been compiled with Xcode 26.6 and Swift 6.3.3, using SDK 26.5. This is a recorded build environment, not a requirement to use exactly that release or a claim that every older Xcode works. The deployment minimums come from the APIs used in the apps; they are not the SDK version.

A simulator runtime is optional for compilation and host tests, but required to launch an iPad simulator. A simulator cannot establish physical Pencil pressure behavior, palm handling, or cable connectivity.

Use [SETUP](../SETUP.md) for signing, building both apps, permissions, installation and seven-day renewal. A clean Mac/iPad with no prior developer preparation remains an important wired-connection compatibility check; a USB cable alone does not guarantee the required network interface exists.

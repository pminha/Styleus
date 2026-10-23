# Styleus app icons

The two icons share one geometric mark: a Pencil running from a broad, rounded lower-left pointer nib to a rounded upper-right cap. The cursor's small stem meets the barrel at a stepped join, separated by a constant-width off-white stroke. A thin portrait tablet outline distinguishes the iPad app; a thin 16:10 screen and single low-profile base distinguish the Mac companion.

- `styleus-ipad.svg`: editable iPad artwork, with an opaque square background for the system's icon mask.
- `styleus-mac.svg`: editable Mac artwork, with transparent space around the laptop silhouette.
- `styleus-ipad-1024.png` and `styleus-mac-1024.png`: PNG masters used by the native asset catalogs.

Artwork uses only warm off-white (`#F3F2ED`) and near-black (`#20211F`), with antialiased edges. The nib and small stepped join were inspired by the user's Pencil reference; the thin device silhouettes and complete icon compositions are original vector geometry written for Styleus and rendered locally with CoreGraphics. No raster artwork was edited to create these final assets. The SVG and PNG versions are emitted from the same geometric description in `scripts/render_branding.swift`.

Regenerate the artwork and native asset catalogs on macOS:

```sh
swift scripts/render_branding.swift
swift scripts/generate_icons.swift
```

No image service, credentials, paid dependency, or external package is required. The artwork is included under the repository's MIT license.

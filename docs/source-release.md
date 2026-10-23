# Publishing the source

Styleus uses the [MIT License](../LICENSE), with the copyright notice attributed to Styleus contributors. The intended free distribution workflow is source code that each person builds and signs on their own Mac and iPad. This is not an App Store, TestFlight or notarized binary release.

## Files that belong in the repository

Include app/shared/test source, property lists, native icon asset catalogs, the generic Xcode project and shared schemes, `Config/Signing.xcconfig`, build/configuration helpers, public documentation and final artwork under `media/`. The public project must contain only generic signing defaults and references to local variables. The included promotional movie is an original illustrated demo, not a capture of private documents or device screens; its editable rendering source and license information are included.

Keep these local:

- `Config/Local.xcconfig`: each developer's signing team and stable app identifiers.
- `build/`, `dist/`, `tmp/`, `output/`, Xcode user state and `.DS_Store`.
- Provisioning profiles, signing keys/certificates, device/account logs and pairing codes/QR images.
- Personal documents, screenshots, conversations and diagnostic captures.

`.gitignore` excludes these paths and common signing artifacts. It does not remove anything already committed, and force-adding ignored files overrides it. Review the staged file list and diff before the first commit and every release. Never upload the entire development folder as an unfiltered archive.

## Before publishing

1. Run the setup-helper tests and shared Swift tests described in [SETUP](../SETUP.md).
2. Build a clean source copy without `Config/Local.xcconfig`; verify the generic Mac build and unsigned iPad device/simulator builds. This checks portability without publishing anyone's signing details.
3. Follow the Personal Team setup on the destination machine. Verify both native apps and the hardware checklist; compilation alone cannot establish device trust, free renewal, USB networking or Pencil behavior.
4. Check that documentation links resolve and no personal paths, account/team identifiers, actual device identifiers or credentials appear in the source or archive.
5. Review your Git author name/email and GitHub account visibility before making a public commit. These are publication metadata separate from the app's source files; a GitHub profile may itself identify its owner.

No remote repository, paid enrollment, account invitation or publication is required to prepare and build the project locally.

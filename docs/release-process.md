# Release and update process

OrbitSim uses Sparkle 2.10.0 for signed update checks in Release builds. Debug builds do not start the updater. The appcast URL is `https://michaeldadi.github.io/orbitsim/appcast.xml`; publication requires GitHub Pages to serve this repository's `docs/` directory.

The Sparkle EdDSA public key is in `Info.plist`. Its private counterpart is stored only in the macOS login Keychain under account `io.github.michaeldadi.orbitsim`. Do not export it into the repository or CI logs. The app also requires Apple Developer ID signing and notarization. Sparkle verifies the archive before extraction and requires a signed feed.

## Release gate

1. Verify every supported individual feature row in the [matrix](feature-matrix.md). An incomplete or blocked Pro row prevents a full-parity release.
2. Run Swift tests, a Release Xcode build, fixture and device integration tests, license checks, and performance benchmarks against the recorded baseline.
3. Archive with Xcode Release configuration and the personal Developer ID identity. Verify the app and embedded frameworks with `codesign --verify --deep --strict`.
4. Zip the archive, submit it to `xcrun notarytool`, staple the accepted ticket to the app, and recreate the zip. Verify with Gatekeeper.
5. Put the notarized zip and release notes in a local archive folder. Run Sparkle's `generate_appcast --account io.github.michaeldadi.orbitsim --download-url-prefix <GitHub-release-download-base> <archive-folder>`. It signs the archive entry and feed. Validate the XML and download URLs.
6. **Human review:** inspect the exact signed zip, checks, release notes, appcast diff, and rollback candidate. Then publish the GitHub Release and update `docs/appcast.xml` in a reviewed commit.
7. On a separate Mac or clean user account, install version N, let Sparkle update to N+1, and test recovery using a higher-version build of the last known-good source. Mark automatic updates operational only after this drill passes.

An SDK compatibility failure may open a redacted issue and a proposed pull request. It does not authorize automatic code publication. Sparkle delivers a reviewed release after the release gate passes.

References: [Sparkle setup](https://sparkle-project.org/documentation/), [Sparkle publishing](https://sparkle-project.org/documentation/publishing/), and [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

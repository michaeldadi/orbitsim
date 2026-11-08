# OrbitSim agent guidance

- Work in this repository, not in the Foresight monorepo.
- Keep all implementation code, icons, copy, and assets independently authored. Store observations of RocketSim and any permission evidence outside this public repository.
- Treat `docs/feature-matrix.md` as the completion contract. Mark a row verified only after its acceptance test passes on a supported target.
- Keep target IDs explicit. Do not use `simctl booted` or pick the first target for an action.
- Use public Apple APIs and `simctl`/`devicectl` first. Isolate any non-public Simulator adapter and review distribution terms before shipping it.
- Do not embed secrets, signing keys, patient data, or captured network bodies in the repository. Sparkle’s private EdDSA key belongs in the macOS Keychain.
- Run `swift test` and the Xcode app build after code changes. Use `xcodebuild -quiet` for routine checks.
- The `.xcproj` JSON file is the source of truth for the Xcode project. Do not regenerate it with XcodeGen.
- A release requires human review of the archive, notarization, signed appcast, and compatibility results. Never auto-publish a code fix solely because an SDK smoke test fails.

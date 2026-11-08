---
name: orbitsim
description: Use OrbitSim's macOS CLI to inspect and control a specifically chosen iOS Simulator or paired device during local app development.
---

# OrbitSim

Use this skill when a user asks for local Simulator or device actions through OrbitSim. Read the installed CLI's `orbitsim help` and `orbitsim version` first; the public repository is still under development, and the [feature matrix](../../docs/feature-matrix.md) distinguishes working commands from incomplete workflows.

## Target selection

Run `orbitsim targets --json` and use the exact target ID supplied or selected by the user. If the request does not identify one and several eligible targets exist, ask which device to use. Every mutating command takes `--target <id>`; never substitute an arbitrary booted target or a first-match result. Confirm the target is booted or connected before acting.

## Current commands

- Capture a PNG: `orbitsim screenshot --target <id> --output <new-file.png>`. Simulator output also accepts `--type jpeg|tiff|bmp|gif` with a matching file extension. The CLI refuses to overwrite an existing file. On a multi-screen Simulator, inspect `orbitsim displays --target <id> --json` and pass the intended `--display <screen-id>`.
- Record a bounded Simulator clip: `orbitsim record --target <id> --output <new-file.mp4> --seconds <1-120> [--display <screen-id>]`.
- Inspect a visible Simulator: `orbitsim elements --target <id> --json`. The JSON includes screen-coordinate frames when macOS Accessibility provides them. Text values are omitted unless the user requests them and `--include-text` is passed. The current list can include Device Hub controls, so check identifiers carefully.
- Press an identified control: `orbitsim interact --target <id> --element <accessibility-id> --action press`.
- Set an editable field: `orbitsim interact --target <id> --element <accessibility-id> --action type --text <value>`. The text appears in the shell command line; use this only for non-sensitive test input.
- Wait for a control: `orbitsim wait --target <id> --element <accessibility-id> --seconds <0.1-60>`.
- Use `orbitsim help` for lifecycle, links, location, appearance, privacy, push, status bar, media, builds, and diagnostics.

`orbitsim builds` reads current Xcode manifests without writing a cache. Pass `--history` to update and read the local SQLite history; use `--history-file <path>` when a task calls for an isolated cache.

`elements`, `interact`, and `wait` currently depend on a visible, uniquely matched Simulator in Xcode Device Hub and macOS Accessibility permission for the caller. They do not provide headless control. If the matching window or permission is absent, report that condition; do not fall back to another target.

Captures and element text can contain private data. Keep test artifacts in the location the user requested, avoid printing screen contents in logs, and request `--include-text` only when the task calls for reading it. The paired-device PNG and host-window preview have local proofs; physical recording, network, camera, and full RocketSim Pro parity remain incomplete.

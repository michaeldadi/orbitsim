---
name: orbitsim
description: Use OrbitSim's macOS CLI to inspect and control a specifically chosen iOS Simulator or paired device during local app development.
---

# OrbitSim

Use this skill when a user asks for local Simulator or device actions through OrbitSim. Read the installed CLI's `orbitsim help` and `orbitsim version` first; the public repository is still under development, and the [feature matrix](../../docs/feature-matrix.md) distinguishes working commands from incomplete workflows.

## Target selection

Run `orbitsim targets --json` and use the exact target ID supplied or selected by the user. If the request does not identify one and several eligible targets exist, ask which device to use. Every mutating command takes `--target <id>`; never substitute an arbitrary booted target or a first-match result. Confirm the target is booted or connected before acting.

## Current commands

- Capture a PNG: `orbitsim screenshot --target <id> --output <new-file.png>`. The CLI refuses to overwrite an existing file.
- Record a bounded Simulator clip: `orbitsim record --target <id> --output <new-file.mp4> --seconds <1-120>`.
- Inspect a visible Simulator: `orbitsim elements --target <id> --json`. Text values are omitted unless the user requests them and `--include-text` is passed.
- Press an identified control: `orbitsim interact --target <id> --element <accessibility-id> --action press`.
- Wait for a control: `orbitsim wait --target <id> --element <accessibility-id> --seconds <0.1-60>`.
- Use `orbitsim help` for lifecycle, links, location, appearance, privacy, push, status bar, media, builds, and diagnostics.

`elements`, `interact`, and `wait` currently depend on a visible, uniquely matched Simulator in Xcode Device Hub and macOS Accessibility permission for the caller. They do not provide headless control. If the matching window or permission is absent, report that condition; do not fall back to another target.

Captures and element text can contain private data. Keep test artifacts in the location the user requested, avoid printing screen contents in logs, and request `--include-text` only when the task calls for reading it. Do not claim physical-device, network, camera, or full RocketSim Pro parity based on a successful Simulator command.

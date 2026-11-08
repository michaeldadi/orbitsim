# Feature matrix

Baseline: RocketSim 16.8.0 installed on macOS 27.2; public documentation reviewed 2026-11-07. OrbitSim targets macOS 27 and Xcode 27.2. Status is **verified** only after a repeatable working test on a supported target; **incomplete** means absent, partial, or not tested; **blocked** means a confirmed dependency prevents equivalent behavior. `S` = Simulator, `P` = paired physical device.

| ID | Individual workflow | Target | OrbitSim path / dependency | Acceptance test | Status |
| --- | --- | --- | --- | --- | --- |
| F01 | Target discovery and explicit selection | S/P | `simctl`/`devicectl`, registry | Discover one booted S and one paired P; require ID for actions | verified (CLI; app starts with no selection) |
| F01b | Concurrent target focus | S/P | registry and window tracker | Distinguish two booted Simulators and focused device | incomplete |
| F02 | Context-aware side window | S/P | AppKit window tracking | Window follows focused Simulator/device through move, resize, disconnect | incomplete |
| F03 | Menu bar and settings | macOS | SwiftUI/AppKit | Open, refresh, configure, and quit with VoiceOver | incomplete (shell built) |
| F04 | CLI install and version matching | macOS | app bundled CLI and symlink | Upgrade app; `orbitsim version` and schema match | incomplete |
| F05 | Simulator PNG screenshot | S | `simctl io screenshot` | Capture selected booted S, inspect dimensions, preserve existing file | verified (CLI) |
| F05c | Live Simulator window preview | S | ScreenCaptureKit window stream | Explicitly select one visible window, preview live frames, stop cleanly, handle permission denial | incomplete (private stream proof received 146 frames in 3 seconds; app permission and UI stream unverified) |
| F05b | Other screenshot formats and devices | S/P | `simctl io`/`devicectl capture`, Image I/O | Capture P and JPEG, alternate displays, rotation | incomplete (Simulator JPEG 1206×2622 verified; other formats and physical device pending) |
| F06 | Floating capture thumbnail and drag/copy | S/P | AppKit pasteboard and drag | Capture then drag and copy to Finder and editor | incomplete |
| F07 | Bounded MP4 recording | S | `simctl io recordVideo` | Record selected S; finalize valid video after SIGINT | verified (CLI, 2-second request yielded 1.58-second playable track) |
| F07b | Interactive MP4 recording | S/P | capture session and controls | Start/stop on demand, physical device, graceful disconnect | incomplete |
| F08 | GIF recording | S/P | capture pipeline and Image I/O | Export animated GIF with expected frame timing | incomplete |
| F09 | Eligible 120 FPS capture | S | source timing and encoder | Measure sustained 120 FPS on eligible target | incomplete |
| F10 | Simulator and device audio | S/P | capture source / AVFoundation | Record and play synced system audio | incomplete |
| F11 | Microphone voiceover | S/P | AVFoundation permission and mix | Record mic + screen audio without drift | incomplete |
| F12 | Touch indicators and pinch gestures | S/P | event capture / compositor | Show single/multi-touch positions in export | incomplete |
| F13 | Bezel, Duo fold, frame color | S/P | original device assets / compositor | Match geometry and fold state at supported sizes | incomplete |
| F14 | Background, ratio, shadow, metadata | S/P | Core Image/Metal, Image I/O | Export each variant from one source capture | incomplete |
| F15 | Nondestructive post editor and trim | S/P | edit manifest, AVFoundation | Reopen and re-export source without quality loss | incomplete |
| F16 | App Store Connect optimized export | S/P | App Store media rules | Validate dimensions, codec, and upload acceptance | incomplete |
| F17 | Design image overlay and wipe | S/P | transparent AppKit overlay | Align reference across window moves and zoom | incomplete |
| F18 | Grid, rulers, distances | S/P | AppKit overlay, point conversion | Verify distances at physical/point/pixel scale | incomplete |
| F19 | Magnifier and color picker | S/P | capture sample / AppKit | Copy sampled value in supported code formats | incomplete |
| F20 | Slow animations | S | Simulator control proof | Enable, disable, restore state on exit | incomplete |
| F21 | Simulator boot/shutdown | S | `simctl` | Boot and shut down specific disposable target | incomplete (boot verified via `simctl`, not CLI) |
| F22 | App install, launch, terminate, uninstall | S/P | `simctl`/`devicectl` | Lifecycle fixture app on both target types | incomplete (Simulator install and launch verified on OrbitFixture; other actions and physical device pending) |
| F23 | Recent builds and relaunch | S/P | DerivedData index, lifecycle adapter | Select right app from two Xcode projects | incomplete |
| F24 | Deep and Universal Links | S/P | `simctl openurl`/`devicectl` | Open fixture link with chooser and fallback | incomplete (Simulator custom URL verified after Open prompt; Universal Link and physical device pending) |
| F25 | Simulated push notification | S | `simctl push` | Deliver valid payload; reject invalid payload | incomplete (adapter and invalid-payload test) |
| F26 | Fixed location | S | `simctl location` | Set valid coordinates then clear | verified (CLI) |
| F26b | Routes and time zone | S/P | `simctl location`/device tools | Drive route and restore prior state | incomplete |
| F27 | Status bar time and battery | S | `simctl status_bar` | Set then clear time and battery | verified (CLI) |
| F27b | Status bar network and carrier | S | `simctl status_bar` | Set then clear all supported fields | incomplete |
| F28 | Light and dark appearance | S | `simctl ui` | Toggle then restore appearance | verified (CLI) |
| F28b | Accessibility environment | S | platform controls | Toggle and restore text size, contrast, VoiceOver | incomplete |
| F29 | Privacy permissions | S | `simctl privacy` | Grant/revoke/reset each supported service on fixture | incomplete (subset adapter built) |
| F30 | Pasteboard, keychain, user defaults | S | `simctl` and debug bridge | Read/change/restorable state for fixture app | incomplete |
| F31 | Shake and memory warning | S | proven Simulator control path | Trigger fixture handlers without UI focus ambiguity | incomplete |
| F32 | Camera injection | S | AVFoundation plus Simulator input proof | Scan live QR in fixture app, multiple runtimes | incomplete |
| F33 | Network request monitor | S | opt-in debug-only URLSession bridge | Capture method, URL, timing, status, body policy | incomplete |
| F34 | Network filters, cURL, insights | S | indexed event store | Search session, export redacted cURL and trend | incomplete |
| F35 | Speed throttle and airplane mode | S | Network Extension or debug transport | Show per-app latency/loss and restoration | incomplete |
| F36 | Basic build log statistics | macOS | Xcode `LogStoreManifest.plist` reader | Parse scheme, duration, status, errors, warnings and p75/p95 from fixture and real log | verified (CLI and fixture test; native view built) |
| F36b | Full build insights and trends | macOS | activity-log parser / SQLite | Classify clean/incremental, plot history, show step-level timing | incomplete |
| F37 | Accessibility tree and element highlight | S | Device Hub Accessibility bridge | Read identifiers, frames, labels; highlight visible controls | incomplete (CLI read six fixture identifiers; frame/highlight pending) |
| F38 | VoiceOver Navigator and audit | S | accessibility test runner | Navigate fixture, export actionable findings | incomplete |
| F39 | Agent elements/interact/wait | S | Device Hub Accessibility bridge and future local socket | Semantic tap/type/wait with stale-target and timeout behavior | incomplete (CLI elements, press and wait verified on fixture; type, gesture, stale-target and IPC pending) |
| F40 | Agent screenshots/recording/doctor | S | CLI and app IPC | Stable machine-readable schema and errors | incomplete (CLI screenshot/doctor partial) |
| F41 | Browser preview and remote control | S | local HTTP/WebSocket with token | Localhost default; explicit time-limited LAN sharing | incomplete |
| F42 | Physical-device live preview | P | USB stream / ScreenCaptureKit proof | Preview at physical, point, pixel, fit scales | incomplete |
| F43 | Physical-device capture with audio | P | `devicectl`/capture pipeline | Screenshot, MP4/GIF/audio and clean disconnect | incomplete |
| F44 | Physical location and time zone | P | `devicectl` capability probe | Set/restore on paired iPhone running iOS 27 | incomplete |
| F45 | Local retention, redaction, migrations | macOS | SQLite WAL, file store | Bounded queue, redacted export, migration recovery | incomplete |
| F46 | Signed automatic updates and rollback | macOS | Developer ID, notarization, Sparkle 2.10.0 | Install two signed versions and recovery build | incomplete (framework integrated; feed and drill pending) |
| F47 | Xcode/macOS compatibility detection | macOS | scheduled `xcode-27` smoke workflow | Detect new SDK break and open redacted issue | incomplete (first hosted smoke passed; failure issue path untested) |

The installed app showed Pro-gated settings in this environment. Rows sourced from public RocketSim documentation are a feature inventory, not a claim that Pro behavior was exercised locally. Where a smaller fallback works, the row stays incomplete until its stated acceptance test passes.

Sources: [RocketSim features](https://www.rocketsim.app/features/), [capture documentation](https://www.rocketsim.app/docs/features/capturing/recordings/), [physical-device documentation](https://www.rocketsim.app/docs/features/physical-devices/), [agent documentation](https://www.rocketsim.app/docs/features/agentic-development/), and local Xcode tool help.

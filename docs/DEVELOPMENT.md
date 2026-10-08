# Developing TraceRook

The [MVP1 architecture specification](../TraceRook_MVP1_Architecture_Spec.md) is authoritative. The [implementation record](IMPLEMENTATION_STATUS.md) documents completed checks, platform observations, and pending release gates.

## Requirements

- Apple Silicon (`arm64`) Mac, macOS 26 or later.
- Swift 6 and the macOS 27 SDK.
- Full Xcode 27 for Xcode builds and archives; compatible Command Line Tools can build the development app with the repository scripts.

## Build and run

From the repository root:

```sh
./scripts/build.sh
open build/TraceRook.app
```

Build the optimized development configuration with `./scripts/build.sh release`.

Open `TraceRook.xcodeproj` and select the TraceRook scheme for Xcode development. SwiftPM owns the Swift Testing harness. Build settings restrict CPU to arm64, deployment to macOS 26.0, and Swift language mode to 6; hardened runtime is enabled.

The app bundle includes the service executable, hook CLI, and LaunchAgent plist. The Phase 0/1 build does **not** register a Login Item or install agent hooks. The bridge refuses ordinary operational invocation. Do not wire it into agent settings manually.

Development builds are ad-hoc signed unless `TRACEROOK_SIGNING_IDENTITY` is provided. Configuring an identity alone does not complete Developer ID distribution or notarization. Read [security and release limitations](../SECURITY_LIMITATIONS.md).

## Explore the native demo

```sh
open build/TraceRook.app --args --demo
```

The preview includes menu bar navigation, dashboard destinations, session timelines, incident evidence, onboarding, privacy preview, provider selection, and simulated Cloud Account, Usage, and Plans. BYOK remains unavailable until Phase 4 and does not collect a key. Real activity stays empty and Not integrated.

Select **Simulate review**, then open Approvals or the native review panel. A sample request has a 45-second deadline. Block and Allow once are terminal sample responses; repeated or expired responses are rejected. Demo approvals cannot authorize real actions.

Request notification permission explicitly in onboarding or Settings to exercise the native notification path. The approvals queue remains accessible without notifications. Full manual notification-delivery acceptance is still pending.

Settings supports System, Light, and Dark appearances without changing macOS preferences. `--appearance-light` and `--appearance-dark` are development preview switches.

## Automated checks

```sh
./scripts/test.sh
./scripts/smoke-test.sh
./scripts/ui-smoke-test.sh
```

The smoke script includes the unit tests, app build, and relocated bundle/resource checks. The testing script supplies Swift Testing framework paths for Command Line Tools installations when required. See the implementation record for known build-tool adjustments.

The UI smoke script renders 20 light/dark cases under `build/ui-smoke/`: dashboard destinations, pending/expired review, real/demo separation, and notification-denied settings. Render checks do not certify full VoiceOver support, actual notification delivery, or live-host enforcement.

A separate Scene-level launch check verifies a visible dashboard:

```sh
build/TraceRook.app/Contents/MacOS/TraceRook --demo --launch-smoke-test
```

Live phases require harmless tests on real Claude Code and Codex versions proving a denied tool body never ran, with host permissions preserved on Allow once. Fixture parsing is not evidence of verified hook coverage.

## Source layout

| Directory | Purpose |
| --- | --- |
| `App/` | Native SwiftUI interface and AppKit review window |
| `Agent/` | Background service executable foundation |
| `HookCLI/` | Host bridge executable foundation |
| `Packages/` | Shared contracts, adapters, privacy, rules, core, and fixtures |
| `Tests/` | Swift Testing cases |
| `Resources/` | App icon, Info.plist, and LaunchAgent resource |
| `website/` | Static product website and documentation |

When adding executable source files, synchronize the Xcode project:

```sh
python3 scripts/update-xcode-sources.py
```

## Static website

```sh
python3 website/scripts/build.py
python3 website/scripts/check.py
node --check website/dist/assets/site.js
node website/scripts/preview.mjs
```

Open `http://127.0.0.1:4173/`. The generated `website/dist/` is a portable static site with no runtime application backend. Search reads only its bundled same-origin index. See the [website guide](../website/README.md) for editing and publication details.

## Contribution expectations

Work through the specified phases in order. Each phase needs compilation, relevant tests, and a working demonstration. Keep synthetic examples labeled, preserve unrelated user configuration, and reject unsafe or incomplete remote payloads. Never substitute a fixture result for live protection.

Document actual platform/API deviations and their evidence in the implementation record. Pending security behavior must remain visibly pending until its acceptance tests pass.

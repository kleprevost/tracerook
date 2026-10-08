# Implementation and acceptance record

Authoritative specification: `TraceRook_MVP1_Architecture_Spec.md` version 1.0. No product requirement is waived by this record.

| Phase | Status | Evidence / remaining gate |
|---|---|---|
| 0 — Foundation | Passed locally | All three arm64 executables compiled with Swift 6 / SDK 27; 13 Swift Testing tests pass; packaged CLI/service self-tests pass; native foundation window inspected via accessibility |
| 1 — Native UI / Cloud Demo | Implemented; local acceptance checks passed | Native menu/dashboard/onboarding/settings, Cloud fixtures, sample review panel and notification routing; 23 tests pass; 20 light/dark native renders; actual Scene launch smoke passes. Full manual VoiceOver and notification delivery acceptance remain pending |
| 2 — Live ingestion | Pending | Signed helper, authenticated XPC, private socket, safe installer, SQLite, actual host callbacks |
| 3 — Enforcement | Pending | Both hosts must pass harmless pre-execution deny/review/allow-once tests |
| 4 — BYOK / drift | Pending | Real direct Anthropic requests, Keychain, consent, privacy, budgets and timeouts |
| 5 — Beta packaging | Pending | Developer ID, notarization, macOS 26/27, performance and release checklist |

## Platform observations and necessary development adjustments

- Development host: Apple Silicon, macOS 27.0, Swift 6.4, macOS 27 SDK from Command Line Tools. Full Xcode is absent. A checked-in native Xcode project accompanies a SwiftPM build path that packages a real `.app`; Xcode-specific build/archive validation is still required on a host with full Xcode.
- SwiftPM's new default SwiftBuild backend fails to initialize in this Command Line Tools installation (`Unknown error parsing property list`). The native SwiftPM build backend is used for local validation. This changes the build tool path, not the product architecture.
- Command Line Tools bundles Swift Testing but its framework search path is not injected by the native backend. `scripts/test.sh` supplies that path and runtime rpath for CLT installations. The standard Swift Testing runner executes the tests.
- SDK 27 introduces a `@State` macro requiring `SwiftUIMacros`, which is absent from this CLT installation. The UI uses a typealias of the existing Apple `SwiftUI.State<Value>` property wrapper (available on macOS 26). Swift 6 concurrency and SwiftUI remain unchanged.
- Foundation adapter fixtures are sanitized schema examples, not captured live-host proof. They never establish verified coverage.
- Native sidebar snapshot rendering with the SDK 27 sidebar List style yielded unreadable selected labels. A standard SwiftUI button sidebar inside native HSplitView gives explicit readable selection and accessibility labels. There is no web renderer or third-party UI framework.
- WindowGroup launch behavior is explicitly `presented`; the app otherwise restored a menu-only state after repeated development launches. A Scene-level launch smoke check verifies a visible dashboard.
- Bounded JSON uses Decimal rather than Double for original-action values. Inputs beyond supported decimal precision/exponent bounds are rejected rather than rounded into the same action digest. In live phases, incomplete mutable/exec inspection must result in denial or the configured strict policy.

## Local acceptance evidence (2026-10-08)

`scripts/smoke-test.sh` compiles all three targets, runs 23 Swift Testing cases, executes the CLI/service fixture demonstrations, verifies the development app's signature integrity and checks the Mach-O architecture. `LC_BUILD_VERSION` reports deployment 26.0 and SDK 27.0. Signature integrity is not Developer ID trust or notarization.

`scripts/ui-smoke-test.sh` renders 20 native PNG cases (six dashboard destinations, pending/expired review, real overview and notification-denied settings in both appearances). Overview, sessions, incidents, provider/account and expired-review artifacts were visually inspected. These tests check rendering and state behavior, not pixel equality against an approved baseline. Automated desktop-control attempts encountered ScreenCaptureKit errors/timeouts; exhaustive keyboard/VoiceOver and actual notification delivery have not been certified.

The native app launch test reports one visible dashboard window. Debug and optimized release configurations both compile. Bundle relocation tests verify that packaged helpers load bundled fixtures, and reject missing packaged resources rather than reading a development checkout. App resources include a code-drawn native icon.

Manual demo: launch `build/TraceRook.app`, Explore Demo, Simulate review, Approvals, Block/Allow once/Open review panel. Sample incidents expose evidence, task context, execution certainty and limitations. Real activity stays empty and Not integrated. No user agent configuration or service registration is changed.

## Next acceptance gate

Phase 2 must implement authenticated signed-family XPC before allowing privileged UI approval mutations, a private UID-checked bounded Unix socket, sole-writer SQLite migrations and optimistic-concurrency integration changes. No UI button can enable live protection before those pieces and real-host callbacks are validated. Codex trust is a separate human review step. Phase 3 cannot pass without harmless real-host pre-execution proof on both agents.

This document records actual platform behavior and acceptance evidence; it must not label pending functionality as complete.

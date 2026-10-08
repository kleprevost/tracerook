# Implementation and acceptance record

Authoritative specifications: `TraceRook_MVP1_Architecture_Spec.md` version 1.0, the additive `TraceRook_MVP2_Architecture_Implementation_Spec.md`, and `TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md`. PR scope follows each milestone's coding handoff. Product requirements remain in force except for explicitly user-authorized distribution deviations recorded in the milestone evidence.

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

## MVP2.0 / PR 1 — baseline and contracts (2026-10-08)

**Passed locally**, scoped to PR 1 by the handoff. Pinned main is `2d7712c298e7493f9b9b3f209d930d4c88d60cdb`; local branch is `codex/mvp2-baseline-contracts`. [MVP2_ACCEPTANCE.md](MVP2_ACCEPTANCE.md) records the inspected source, exact versions, phase checklist and no-ship gates. [MVP2_PR2_PLAN.md](MVP2_PR2_PLAN.md) lists concrete service/authentication/storage/UI and subsequent hook changes.

- Added additive live IPC v2 without changing v1 schema/fixtures/readers: bounded length-prefixed codec, duplicate-key rejection before Foundation, Decimal preservation, strict DTO keys, bounded timing, system-random invocation nonce, no-override/deny replies and exact request binding.
- Added per-class/version integration evidence and analysis availability contracts, plus live-only high-review request/resolution contracts reusing Core's existing `ApprovalBinding`. These DTOs do not authenticate callers, attest protection, enforce pending-state CAS or operate a service.
- Packaged helper `--protocol-version` reports 2. `--self-test` runs a synthetic v2 codec demonstration, preserving fixture checks and operational refusal. No agent configurations or service registrations are changed.

| Executed check | Actual result |
|---|---|
| Baseline `scripts/smoke-test.sh`, `scripts/ui-smoke-test.sh` | 23 tests; three debug executables; relocated bundle/signature/resource checks; 20 native renders passed |
| Final `scripts/smoke-test.sh` | **43 tests passed**: all 23 original + 20 new contract tests; three debug executables, packaged self-tests/protocol version, relocation/missing-resource refusal, ad-hoc integrity and arm64 checks passed |
| Post-change `scripts/ui-smoke-test.sh` | 20 native light/dark cases passed; case set matches baseline. Real overview and pending demo review visually inspected; labels remain honest |
| Scene launch | `TraceRook --demo --launch-smoke-test`: one dashboard window visible |
| Optimized build and `scripts/bundle-smoke-test.sh` | All three release executables compiled; relocated development bundle demonstrations, protocol versions, resources and signature integrity passed |
| Static site checks only | 23 HTML pages, 1,172 local links/assets/anchors, 20 guides, 7,829 docs words; JavaScript syntax passed. Website/README source unchanged |
| Configuration preservation | Local SHA-256 comparisons confirm Claude settings/local settings and Codex config unchanged; Codex hooks file remains absent |

Evidence logs and before/after native render artifacts remain in ignored `build/mvp2-baseline/` and `build/ui-smoke/`. Rendering is not a pixel-equality or accessibility certification. Official schema examples are recorded in [agent compatibility](AGENT_COMPATIBILITY.md); no live host was exercised. Installed versions are Claude Code **2.1.290** and Codex **0.162.0-alpha.2**. Neither host nor any tool class has verified protection.

Source adaptations: Review DTOs belong to Core because `ApprovalBinding` is already there; moving them into Contracts would require a dependency cycle or a duplicate domain type. No SQLite implementation exists at baseline, so schema-v1 readers are retained now and actual database migrations remain PR 2. The spec's illustrative SQL `real` origin will be translated to existing `DataOrigin.live`. The executable rule corpus assumed by the spec is absent and must be implemented. The foundation Codex normalizer's object-only input assumption needs tool-specific decoding before live integration.

Platform limits: full Xcode and Developer ID identities are absent; no production signed-family IPC, archive, notarization or macOS 26 validation occurred. The native SwiftPM backend still passes but now emits a deprecation warning; its eventual removal needs a build-tool migration, not weaker security. JSON decode deadline checks are cooperative around Foundation calls and bounded packets; PR 2 must add transport deadlines and cancellation. Hooks, service-owned reviews, SQLite and actual BYOK remain pending. No public beta claim or deployment is made by this phase.

## MVP3.0 / PR 0 — available-baseline and release-state audit (2026-10-08)

Audited source and public main: **`e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7`**, including the already-deployed MVP2 website update. [MVP3_BASELINE.md](MVP3_BASELINE.md) records exact source, local binary hashes, installed hosts, deployment and capability inventory. [MVP3_ACCEPTANCE.md](MVP3_ACCEPTANCE.md) separates passed, failed and not-run checks. [MVP3_PR1_PLAN.md](MVP3_PR1_PLAN.md) prepares the isolated Cloud contract/privacy scope; [PUBLIC_CLAIMS.md](PUBLIC_CLAIMS.md) records permitted current claims.

The available-preview regression passes: **43 tests**, three debug/optimized arm64 products, packaged self-tests/v2 protocol/resource/signature checks, **20 native render cases**, and debug/optimized visible Scene launch. Static checks pass for **24 pages, 1,300 local references and 21 guides**. Existing public website deployment `03b41904-e68f-4fcd-9136-3d1e6617c1d4` has a successful Cloudflare Pages check on GitHub; the live roadmap matches this preview's implementation state.

The package's reported shipping MVP2 release remains **unresolved**: no separate tag/release/installed distribution was discovered in the inspected locations. Local 0.1.0/build 1 bundles are ad-hoc signed, rejected by Gatekeeper and lack a stapled ticket. No live-host denial, actual BYOK, signed-family service, SQLite or hosted API runtime was found or exercised; their shipping regression remains not run. Installed Claude Code 2.1.290 and Codex 0.162.0-alpha.2 do not establish verified tool coverage.

PR 0 changes documentation only, preserves the supplied package, leaves runtime/build/site files and user-agent configuration unchanged, and makes **no deployments, hook installations, token changes or billable provider calls**. Raw local evidence stays ignored under `build/mvp3-baseline/`. Follow the handoff's **PR 0 only / review before PR 1** boundary; no live Cloud or protection claim is promoted by this audit. See [MVP3_DEVIATIONS.md](MVP3_DEVIATIONS.md) for unresolved baseline assumptions and retained free-tier constraints.

## MVP2.1 — local service implementation

Implemented and tested on macOS 27: authenticated XPC/control observers, audit-token-authenticated bounded hook socket, sole-writer SQLite, sanitized durable state and service-owned exact review transitions. **50 automated tests pass**; native 20-case rendering passes. Actual packaged app/CLI authentication and altered-peer rejection were exercised. [Service evidence and deviations](MVP2_SERVICE_EVIDENCE.md) distinguish these transport proofs from live protection. The hook remains nonoperational until the real rule engine and emergency fallback are enabled. No host/tool class is verified. The user explicitly accepted a non-notarized distribution; local ad-hoc mode and its per-user LaunchAgent are separate from Developer ID policy.

## Local API client preparation — October 8, 2026

The user assigned the local mock backend to `claude/zealous-einstein-nxxnwd`. Client request preview and strict isolated fixture-response validation are prepared, with connection disabled until the actual backend contract is integrated. The full local suite now passes 60 test functions and 22 native appearance cases. An initial 50-case local policy corpus is also implemented, but operational hook enforcement is still disabled. No real Claude request or backend deployment occurred. See [client preparation evidence](LOCAL_API_CLIENT_PREPARATION.md), [API handoff](LOCAL_MOCK_API_HANDOFF.md), and [policy evidence](MVP2_RULES_EVIDENCE.md).

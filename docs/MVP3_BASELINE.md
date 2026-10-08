# MVP3.0 / PR 0 — release-state audit

Audit date: **2026-10-08**. Requirements: [MVP3 specification](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md), [coding handoff](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Coding_Agent_Handoff.md), and retained [MVP2 security requirements](../TraceRook_MVP2_Architecture_Implementation_Spec.md).

**Result:** the available repository and development bundle are verified as the MVP2.0 foundation preview. The package's reported shipping MVP2 release has **not been located or verified**. This does not establish that a separate release does not exist. No runtime behavior is changed by PR 0. A shipping SHA/tag and authentic distributed binary are still needed before integrating Cloud with a purported shipping runtime.

The handoff's first instruction scopes this change to **PR 0 only**, followed by normal review before PR 1. No hooks, agent configuration, service registration, tokens, infrastructure, public site or release are changed. The [PR 1 plan](MVP3_PR1_PLAN.md) describes an isolated contract/privacy phase, not implemented Cloud functionality.

## Source and deployment identity

| Item | Verified observation |
|---|---|
| Repository | `https://github.com/kleprevost/tracerook.git` |
| Audited source / local and public `main` | `e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7` |
| Foundation implementation commit | `fd09039`, followed by the website/docs update in `e2615b8` |
| Audit branch | `codex/mvp3-baseline-audit`, created from the audited SHA |
| Remote branches / tags | Remote ref query found only `main`; no remote or local tags |
| GitHub releases | Authenticated read of the public releases collection returned `[]` |
| Other local source | Local `main` and `codex/mvp2-baseline-contracts` both point to the audited SHA; only this checkout appears in `git worktree list` |
| Static production website | `https://tracerook.dev`; Cloudflare Pages check for the audited SHA is `completed / success` |
| Website deployment | `03b41904-e68f-4fcd-9136-3d1e6617c1d4`; immutable preview `https://03b41904.tracerook.pages.dev`; successful check completed `2026-10-08T15:44:12Z` |
| Public product status | Browser read of `/docs/roadmap/` shows MVP2.0 passed locally, MVP2.1–2.6 pending; README agrees |
| Actual shipping Mac release | **Unresolved**: no release tag, downloadable release asset or installed distribution was discovered in the inspected locations |

Release and check evidence: [GitHub releases API](https://api.github.com/repos/kleprevost/tracerook/releases), [deployment check](https://github.com/kleprevost/tracerook/runs/113400491858), [audited commit](https://github.com/kleprevost/tracerook/commit/e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7). These reads prove the inspected public state, not the absence of an unpublished or externally hosted build.

## Binary identity and platform

Spotlight's bundle-ID query discovered only the repository's ignored `build/TraceRook.app`. Neither `/Applications/TraceRook.app` nor `~/Applications/TraceRook.app` existed. The pre-existing bundle was recorded before rebuild; it has no embedded source SHA, so its contents cannot establish a shipping source identity. This search did not enumerate arbitrary disks, private downloads or other machines.

Fresh debug and optimized bundles were built from the audited source. Both identify as `com.tracerook.app`, **version 0.1.0 / build 1**. They are development artifacts, including the optimized configuration; the word “release” in the build command does not mean distributed, Developer ID signed or notarized.

| Executable | Fresh optimized executable SHA-256 |
|---|---|
| `TraceRook` | `013b4a94617d19bc073a03b4c37f20f2b2a3e656b6723948f46361dd4b564dcd` |
| `TraceRookAgent` | `dc53c7bd2fb60ce0b273a305c2f35428ad42b8c247b43194c670547e0ce9d837` |
| `tracerook-hook` | `c45620067c519fe40c4b113543224508614e94e08431abb8d91baebb83e8b40a` |

The hashes identify the executables tested on this host, not a reproducible-build promise or a complete app archive digest. Local debug hashes, pre-existing binary observations, signature output and build logs are retained in ignored `build/mvp3-baseline/`.

| Prerequisite | Observation |
|---|---|
| Development host | Apple Silicon `arm64`; macOS 27.0 (`26A428`) |
| Swift / SDK | Swift 6.4; macOS SDK 27.0; language mode Swift 6; deployment macOS 26.0 |
| Developer tools | `/Library/Developer/CommandLineTools`; full Xcode unavailable to `xcodebuild` |
| Developer ID | `security find-identity -v -p codesigning`: **0 valid identities** |
| App signature | Ad-hoc, hardened-runtime flag present, no TeamIdentifier; deep/strict signature integrity passes |
| Distribution assessment | Debug and optimized bundles rejected by `spctl --assess --type execute` (exit 3); `stapler validate` finds no stapled ticket (exit 65) |
| Claude Code installed | `2.1.290`, read using `claude --version` |
| Codex installed | `codex-cli 0.162.0-alpha.2`, bundled CLI; read using `codex --version` |
| Agent versions actually hook-tested | **None**; installed version is not verified hook compatibility |

The existing native SwiftPM backend passes but emits its deprecation warning. No build-tool, signing or architecture workaround is added in this audit. Xcode archive, macOS 26, clean install and production signed-family acceptance are not run.

## Capability inventory

Status vocabulary: `verified` means the stated observation was exercised; `not run` means the capability's required acceptance was not executed; `broken` means a particular executed gate failed; `out of scope` means deliberately excluded from PR 0. A missing runtime in this checkout is stated explicitly, rather than silently treated as an existing feature regression.

| Capability | Status | Evidence and scope |
|---|---|---|
| Native dashboard, provider/demo surfaces and launch | verified | Three native executable builds; 20 light/dark renders; debug and optimized Scene launch each report one visible dashboard |
| Cloud Demo and live/demo separation | verified | Existing fixture tests reject live-origin analysis; native real overview is empty and Not integrated; demo account/usage remains labeled synthetic |
| IPC v2 framing, nonce, bounded DTOs and reply binding | verified | Existing contract tests and packaged self-tests; no operating transport is implied |
| Legacy schema / reader compatibility | verified | All original tests retained; event schema 1, legacy IPC 1 / adapter 1.0.0; additive live IPC 2 / adapter 2.0.0 |
| Demo exact-action review, replay and expiry | verified | Existing in-memory Core/UI tests, pending/expired render cases; no live approval demonstrated |
| Redaction / existing remote preflight utility | verified | Existing seeded tests pass; this is not MVP3's stronger egress projection, entropy/path scanning or consent boundary |
| LaunchAgent registration / service operation | not run | LaunchAgent plist is only bundled; `launchctl print` finds no registered service; `Agent/main.swift` ordinarily exits 78 |
| Authenticated UI XPC / private hook socket | not run | DTOs exist; no XPC listener, peer-authentication implementation or socket server in inspected runtime |
| Safe Claude Code / Codex installer and uninstall | not run | Adapter mutation methods throw `unsupportedOperation`; no configuration was changed |
| Real host pre-execution block / Allow Once / host-native permissions | not run | No hooks installed or exercised; ordinary standalone bridge exits 2. That refusal is not a host-denial or absent-canary test |
| Executable local catastrophic rules / outage fallback | not run | Rules module contains `RuleEvidence` only, not an executable policy engine |
| Service-owned approval CAS / restart semantics | not run | Core binding/transition contracts exist; there is no running service or persistent approval transaction |
| SQLite history, retention, migration, export | not run | No SQLite runtime/store exists in inspected source; real collections remain empty |
| Real Anthropic BYOK / Keychain / consent | not run | No BYOK provider or event-analysis network transport exists; Settings declares unavailable and collects no key |
| OS notification delivery / Focus / VoiceOver | not run | Demo notification routing exists; render harness uses an explicit synthetic denied-permission state. No permission request or live banner delivery is exercised |
| Developer ID / notarized distribution gate | broken | Gatekeeper rejects the audited development bundles; no stapled ticket. Expected for these ad-hoc artifacts, not proof of a shipping-release regression |
| Hosted Cloud API / enrollment / genuine Claude provenance | not run | No `cloud/` source or live Cloud provider exists; `api.tracerook.dev` did not resolve on this host. External infrastructure remains unverified |
| Startup application / external tester rollout | out of scope | Supplied application kit remains draft material; no submission, tester count, partnership or acceptance is inferred |

## Actual source ownership and PR 1 dependencies

| Source | Actual baseline / dependency |
|---|---|
| `Agent/main.swift`, `HookCLI/main.swift` | Nonoperational paths; synthetic self-tests only. Leave these paths unchanged during PR 1 |
| `Packages/TraceRookCore/Models.swift` | Existing `AnalysisProvider`, `AnalysisRequest`, `AnalysisVerdict`, `CloudAPIClient`, old future/demo Cloud DTOs and approval records. No real BYOK provider; preserve these public names/readers |
| `Packages/TraceRookCore/DesktopModel.swift` | In-memory demo state; hard-coded empty real collections. No live service subscription |
| `Packages/TraceRookContracts/{Contracts,LiveIPC,WireCodec}.swift` | Reusable typed values and strict framed JSON scanner. HTTP Cloud JSON is not IPC framing; reuse validation carefully, without accepting duplicate keys or changing v2 wire behavior |
| `Packages/TraceRookPrivacy/Redactor.swift` | Useful existing categories and 32 KiB preflight, insufficient for the new no-path/no-raw-input projection and expanded seeded corpus |
| `Packages/TraceRookAgentAdapters/Adapters.swift` | Generic `Bash · shell_exec` summary, not grounded Cloud context. Host originals must stay transient; later projection needs typed semantic features, not raw commands |
| `Packages/TraceRookFixtures/Fixtures.swift` | Real fixture-only Cloud client/provider; preserve rejection of live origin |
| `App/{ViewModels,Navigation,Notifications}/` | Native demo, disabled live install/BYOK, opaque demo notification IDs. No second event-analysis client may be added to the UI |
| `Package.swift`, `TraceRook.xcodeproj`, `scripts/` | Preserve package boundaries, Swift 6 concurrency and native demo harness; extend test targets additively in PR 1 |

`AnalysisRequest` currently lacks typed host/event/action metadata and a consent-bound projection. `CloudAnalysisPayload` can be constructed from demo input and has an older flat shape; it must **not** become the live `/v1/analysis` body by renaming it. A new versioned, validated live contract must reject demo before transport, while preserving old fixture readers. `AnalysisVerdict` restricts recommendations to allow/warn/review, but future validation must still enforce bound fields, provenance and contradictory/late results.

## Executed regression and distribution checks

| Command / observation | Outcome |
|---|---|
| `./scripts/smoke-test.sh` (invokes `./scripts/test.sh`) | **Passed**: 43 tests; three debug arm64 executables; self-tests; protocol-version 2; relocated resources; missing-resource refusal; deep/strict ad-hoc integrity |
| `./scripts/ui-smoke-test.sh` | **Passed**: 20 native light/dark cases with valid dimensions; representative real overview and demo provider Settings visually reviewed |
| Packaged `TraceRook --demo --launch-smoke-test` | **Passed**, debug and optimized: one dashboard window visible |
| `./scripts/build.sh release`; `./scripts/bundle-smoke-test.sh` | **Passed**: all three optimized products; relocated bundle demonstrations and resource/signature checks |
| Standalone operational refusal | **Passed**, checked exit codes: Agent 78, hook 2; never presented as a host blocking test |
| `python3 website/scripts/check.py`; `node --check website/dist/assets/site.js` | **Passed**: 24 HTML pages, 1,300 local references, 21 guides, 8,649 documentation words; no site regeneration or publication |
| Release identity / Gatekeeper / stapled ticket | Identity inspected; integrity passed; **distribution failed** as described above |
| Config preservation | **Passed** local before/after byte hashes, existence and mode; no configuration contents published |
| Real Claude Code / Codex deny tests; real BYOK / hosted analysis | **Not run**: runtime/security prerequisites absent in inspected checkout; PR 0 forbids hook installation and token/configuration changes |

`~/.claude/settings.json` and `settings.local.json` parse as objects with zero hook-event entries and mode `0644`. `~/.codex/config.toml` exists with mode `0600`; `~/.codex/hooks.json` is absent. These limited file observations are not an effective managed-policy or host-trust audit. No transcripts, provider credentials or Keychain contents were inspected. Only host version commands were run; no live agent session or synthetic host callback was generated.

## Environments, missing prerequisites and security delta

Confirmed environment: static Cloudflare Pages production for the public product website. Keep the user's **Cloudflare free-tier** constraint. PR 0 does not create Workers, D1, Durable Objects, domains, bindings, paid services, invitations or a billable inference call. The repository has no hosted API implementation, migrations, API deploy profiles or CI workflows. Staging and production-alpha API deployments, TraceRook-owned Anthropic workspace/key, configured spend controls and API readiness remain **not verified**, not assumed absent from every external system.

New transmitted fields: **none**. New stored product fields/auth scopes/outbound domains: **none**. Host output and permission semantics: **unchanged**. Audit reads use public GitHub metadata, the public site, local version/configuration metadata and local test artifacts. Raw local evidence and configuration hashes stay in ignored `build/mvp3-baseline/`; no keys, invitation values, request bodies or private operational logs belong in committed documentation.

The shipping tag/SHA and authentic app/download were requested during the audit. Until supplied, the release-state question stays open. Review PR 0 before the isolated [PR 1 contract/privacy work](MVP3_PR1_PLAN.md); live service integration and any protection/Cloud-alpha claim remain gated by authentic runtime evidence. See [MVP3 acceptance](MVP3_ACCEPTANCE.md), [public claims](PUBLIC_CLAIMS.md), and [deviation record](MVP3_DEVIATIONS.md).

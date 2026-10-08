# MVP2 acceptance matrix

Authoritative requirements: [MVP2 specification](../TraceRook_MVP2_Architecture_Implementation_Spec.md), [agent handoff](../TraceRook_MVP2_Agent_Handoff.md), and the retained [MVP1 specification](../TraceRook_MVP1_Architecture_Spec.md). The original handoff scoped the first implementation to **PR 1 only**; the subsequent user request authorizes completing and shipping MVP2, with a non-notarized distribution deviation. This record distinguishes contract tests from live security evidence. MVP2 is not complete and this build is not a real-protection beta.

## Pinned baseline — 2026-10-08

| Item | Observed value |
|---|---|
| Repository / baseline main | `kleprevost/tracerook` / `2d7712c298e7493f9b9b3f209d930d4c88d60cdb` |
| Local work branch | `codex/mvp2-baseline-contracts` |
| Host | Apple Silicon arm64; macOS 27.0 (26A428) |
| Compiler / deployment | Swift 6.4; SDK 27 Command Line Tools; deployment macOS 26.0; Swift language mode 6 |
| Claude Code | `2.1.290`; `~/.local/bin/claude` |
| Codex | `codex-cli 0.162.0-alpha.2`; bundled CodexCLI in ChatGPT.app |
| Full Xcode | Absent; `xcodebuild -version` rejects the CLT developer directory |
| Signing | `security find-identity -v -p codesigning`: **0 valid identities**; development bundle is ad-hoc signed |
| Initial checks | 23 tests; three debug executables; relocated bundle/self-tests/signature integrity; 20 native appearance/state renders |
| Operational integration | No TraceRook hook installed or exercised; no service registered; neither host/tool class verified |

Read-only configuration inspection was deliberately limited to existence, permissions, JSON validity and hook-event counts. `~/.claude/settings.json` and `settings.local.json` exist, parse as objects, have mode `0644`, no recognized hook events and no `disableAllHooks: true`. `~/.codex/config.toml` exists with mode `0600`; `~/.codex/hooks.json` is absent. This is not an effective-policy or trust audit. No transcript, key or configuration contents are copied into this document. File hashes are compared locally after the checks, not published.

Only host `--version` and Codex `--help` were invoked. No live session, canary, host trust bypass, agent configuration change, service registration, remote analysis, deployment, push or merge is part of PR 1.

## Inspected source and specification gaps

| Actual source / types at the pinned baseline | Reality / next dependency |
|---|---|
| `Package.swift`; `TraceRook.xcodeproj`; `scripts/{build,test,smoke-test,bundle-smoke-test,ui-smoke-test}.sh` | SwiftPM shared libraries, three executable targets, five test targets; native CLT workaround. Xcode archive still untested. `update-xcode-sources.py` and `generate-icon.swift` are generators, not acceptance tests. |
| `Packages/TraceRookContracts/Contracts.swift`: `JSONValue`, `AgentEvent`, `HookRequest`, `HookResponse`, `IntegrationHealth` | Schema/IPC v1 preserved. Decimal precision and byte/depth limits exist. V1 decoding does not detect duplicate JSON keys. Existing health facts are not exact-version, per-tool attestation. |
| `Packages/TraceRookAgentAdapters/Adapters.swift`: `ClaudeCodeAdapter`, `CodexAdapter`, normalization/encoding helpers | Fixture decoders and deny encoding exist; detection is unknown and config mutations throw `unsupportedOperation`. Codex tool input is assumed to be an object. Original fingerprints lack a per-invocation nonce when the host supplies a call ID. |
| `Packages/TraceRookRules/RuleContracts.swift`: `RuleEvidence` | **No executable policy engine or rule corpus to port exists.** Implement the specified families and positive/negative scenarios; do not count sample findings as rules. |
| `Packages/TraceRookPrivacy/Redactor.swift`: `Redactor`, `SafeLogger` | Redaction, bounded remote preflight and enumerated logging exist. Must be enforced at every future persistence/API boundary. |
| `Packages/TraceRookCore/Models.swift`: `AnalysisVerdict`, `AnalysisRequest`, `AnalysisProvider`, `LocalRulesOnlyProvider`, records, `ApprovalBinding`, `ApprovalTransition`, future Cloud protocols | Strict verdict and in-memory approval transitions exist. No service actor, compare-and-swap transaction, SQLite, Keychain or Anthropic implementation. Local provider availability does not establish functioning enforcement. |
| `Packages/TraceRookCore/DesktopModel.swift`: `DesktopModel` | MainActor demo collections and empty real collections; no service subscription or real mutations. |
| `Packages/TraceRookFixtures/Fixtures.swift`; `Resources/{cloud-demo,claude-pretool,codex-pretool}.json` | Deterministic synthetic content; Cloud client rejects live-origin analysis. Host fixtures are not captured callbacks. |
| `Agent/main.swift`; `HookCLI/main.swift` | Service operational path exits 78; CLI operational path refuses use with exit 2. Self-tests exercise fixtures only. |
| `Resources/{Info.plist,com.tracerook.agent.plist}` | Bundled Mach service/LaunchAgent declaration; neither active registration nor caller authentication. |
| `App/TraceRookApp.swift`; `ViewModels/AppEnvironment.swift`; `Notifications/NotificationController.swift` | Native Scene/menu bar, fixture environment, demo notification routing, ad-hoc signature description. Notifications carry only opaque demo IDs. |
| `App/Navigation/{Dashboard,Overview,Sessions,Incidents,Approvals,Integrations,Settings,Onboarding}View.swift`; `Theme/{Components,UISmokeRenderer}.swift` | Existing native UI to retain. Protection is Not integrated; BYOK unavailable; sample review is explicitly synthetic. |
| `Tests/{Contracts,Privacy,Adapter,Core,UIBasic}Tests/` | 23 baseline tests; no real-host, signed IPC, database, live provider, performance or release evidence. |
| `README.md`, `SECURITY_LIMITATIONS.md`, `website/` | Development-preview claims; public updates wait for release gates. |

## PR 1 additive contracts

`LiveIPC.swift` freezes `HookEnvelopeV2`, `HookReplyV2`, `RequestBudget`, `IntegrationEvidence` and `ProviderStatus`. `WireCodec.swift` bounds and validates the complete frame. `ReviewContracts.swift` adds `ReviewRequest`/`ReviewResolution` using the existing `ApprovalBinding`.

| Contract | Bounds / meaning |
|---|---|
| Version / compatibility | Live IPC 2 and adapter 2.0.0; legacy event schema 1, IPC 1 and adapter 1.0.0 readers/fixtures retained |
| Packet | Four-byte big-endian UInt32 length; exactly one JSON packet; 1 MiB payload; replies 16 KiB |
| JSON | Depth 32; encoded string content 64 KiB including escapes; 1,024 members per object; 2,048 elements per array; reject duplicate decoded keys at every depth, invalid UTF-8 and extra typed fields; retain Decimal bounds |
| Decode time | 100 ms default monotonic deadline, checked during scanning and before/after Foundation decode. Cooperative checks cannot interrupt Foundation midway; packet bounds limit work. Runtime transport cancellation/read deadlines remain PR 2 work. |
| Invocation | System-generated 128-bit nonce, 32 lowercase hexadecimal characters; request UUID; original host payload only in transient memory |
| Replies | Only `no_override` or `deny`; matching request ID; execution observation always `unknown`; no grant, ask, rewrite or approval mutation |
| Budget | Hook cap 80 s, model 8 s, review 45 s, output reserve 1 s; bounded allocations must fit. These are design defaults, not verified host timeout settings. |
| Review | Live origin, high severity, existing exact action binding plus nonce and request/approval IDs; request lifetime at most 45 s. Shape/binding validation does not authenticate a caller, enforce service expiry or consume an approval. |
| Health / analysis | Exact host/version/tool evidence is a record, not proof by itself. Analysis mode is separate from coverage. Demo cannot be represented as a ready live provider. |

**Necessary source adaptation:** review DTOs live in Core, rather than the spec's suggested Contracts inventory, because `ApprovalBinding` already belongs to Core and Contracts cannot depend back on Core. This preserves the existing domain instead of duplicating it or breaking v1 clients. The suggested SQL origin `real` also differs from `DataOrigin.live`; PR 2 will retain `live` in storage with an explicit constraint/migration. There is no baseline database to migrate yet: retaining readers is completed here; actual SQLite migration tests belong to PR 2.

Mode identifiers remain the existing `AnalysisMode` cases: `traceRookCloudDemo`, `localRulesOnly`, `anthropicBYOK`. No new parallel feature-flag system is introduced. Cloud Demo is working and synthetic; Local Rules and BYOK choices cannot enable live protection in this phase.

## Phase-by-phase checklist

| Phase | Required automated acceptance | Working demonstration / evidence | Status |
|---|---|---|---|
| **MVP2.0 / PR 1** | Preserve all 23 tests; test strict v2 framing/keys/precision/versions/budgets/nonces, reply binding and forbidden grants; review live/demo isolation; compile all three executables debug/release; bundle and native render checks | Packaged nonoperational CLI performs synthetic v2 round trip; native Cloud Demo works; real UI remains Not integrated; exact inventory, host versions and PR 2 plan recorded | **Passed locally**; 43 tests and 20 native renders; no live security claim |
| **MVP2.1 / PR 2** | Signed-family XPC rejects unsigned/wrong-team/altered callers; hook socket rejects approval writes and wrong peers; packet/read/concurrency limits; duplicate request handling; SQLite migration/rollback/foreign-key/unknown-enum/retention; restart aborts pending reviews | Consented service starts; sanitized simulated ingestion creates real-origin state through service; UI survives reconnect/restart and empty real state remains truthful | Implemented locally; 50 tests, actual developer-mode XPC/socket authentication and altered-peer rejection. See [service evidence](MVP2_SERVICE_EVIDENCE.md); Developer ID chain tests unverified. |
| **MVP2.2 / PR 3** | Claude config preview, hash conflict, idempotent install/repair/remove, restrictive atomic files, existing hooks preserved; strict original input; emergency rules before bridge enablement; host-compatible output | Real installed Claude callback, benign pre-execution deny and absent canary for Bash plus supported Write/Edit; exact-version/class evidence | Pending; separate user authorization for config/live tests required |
| **MVP2.3 / PR 4** | Codex config preservation, shell escaping, canonical Bash/apply_patch mapping, trust downgrade after hash/version change, no trust bypass | Explicit `/hooks` review; real Bash/apply_patch deny and absent canary; Allow Once preserves native approval; untrusted coverage never green | Pending; alpha version has no verified coverage |
| **MVP2.4 / PR 5** | All specified rule families; at least 40 positive/negative/scope/quoting/traversal/symlink/encoded scenarios; shared emergency rules; concurrent CAS, duplicate clicks, expiry boundary, replay/change of arguments or nonce, stale notifications, drop/crash/sleep | Real high-risk pending hook and notification: Block, Allow Once and ignored/expired actions; critical rules work without Anthropic; legitimate cleanup is not a critical false positive | Pending |
| **MVP2.5 / PR 6** | Keychain/consent, redaction and second preflight; strict verdict/schema/model recommendation bounds; invalid key, budget/token cap, rate limit, malformed response, cancellation and outage; no raw persistence | Opt-in real host event -> minimized preview -> actual direct Anthropic Messages call -> typed verdict -> incident with sanitized model/status/token evidence | Pending; needs user-owned test key and consent |
| **MVP2.6 / PR 7** | Developer ID/hardened runtime/notarization; Xcode archive; clean install/update/uninstall; macOS 26/27 arm64; public claims match verified matrix | Signed beta; 1,000+ fixture and preferably 100 live callbacks/host latency p50/p95/p99; notifications with permission/Focus variations, keyboard and VoiceOver; responsive concurrent sessions | Pending; release environment/signing unavailable here |

Every subsequent PR also reruns existing tests, checks Cloud Demo isolation, compiles, updates this matrix and includes a working demonstration of only its implemented behavior.

## PR 1 verification evidence

| Check | Result / evidence |
|---|---|
| Baseline `scripts/smoke-test.sh` | Passed: 23 tests, three arm64 debug products, bundled fixture self-tests, relocated resources, missing-resource refusal, ad-hoc signature integrity |
| Baseline `scripts/ui-smoke-test.sh` | Passed: 20 light/dark native renders; preserved in ignored `build/mvp2-baseline/ui-before/` |
| Updated `scripts/test.sh` / `scripts/smoke-test.sh` | Passed: **43 tests** (23 retained + 20 security contract tests); all three debug products and bundled demonstrations; logs in ignored `build/mvp2-baseline/` |
| Updated `scripts/ui-smoke-test.sh` | Passed: all 20 original light/dark cases remain; representative post-change real overview and pending review visually inspected; real coverage stays Not integrated |
| Scene-level native launch | Passed: `TraceRook --demo --launch-smoke-test` reports one visible dashboard |
| `scripts/build.sh release` / release bundle checks | Passed: all three optimized arm64 products; relocated self-tests, version checks, resources and ad-hoc signature integrity |
| Configuration preservation | Passed: all three inspected config file hashes unchanged; Codex hooks file still absent |
| Website checker / JS syntax | Passed: 23 HTML pages, 1,172 local references, 20 guides, 7,829 documentation words; no website source edits or deployment |
| Actual host denial / real Anthropic | **Not run**; no inferred pass from fixture tests |
| Full Xcode / signed-family rejection / notarization / macOS 26 | **Not run**; unavailable production validation environment |

Rendering checks verify cases and dimensions with representative visual review; they do not assert pixel equality or certify accessibility. The acceptance evidence for the next PR is in [MVP2_PR2_PLAN.md](MVP2_PR2_PLAN.md).

## Release blockers — spec §16

- [ ] Claude real shell and file write/edit callback/deny evidence with absent canary.
- [ ] Codex real shell and apply_patch callback/deny evidence with explicit native trust.
- [ ] Signed app/service/CLI, authenticated UI mutations, bounded private hook transport, no alternate approval channel.
- [ ] Service-owned exact-invocation approval, expiry denial, signed notification routing, replay/origin isolation.
- [ ] Deterministic catastrophic rules and executing-CLI outage fallback without Anthropic.
- [ ] Consented real direct Anthropic BYOK call, redaction/preflight, typed verdict and incident.
- [ ] No raw command/transcript/key/provider response in DB/logs; retention and Clear History proven.
- [ ] Skip/timeout/hosted/continuation limitations shown; upgrades invalidate incompatible coverage.
- [ ] Cloud Demo remains synthetic and cannot route or approve real activity.
- [ ] Developer ID/notarized clean install/update/uninstall on macOS 26 and 27 arm64.
- [ ] Manual accessibility/notification checks and measured latency.
- [ ] Repository, docs, public claims and real end-to-end demonstration agree.

No release checkbox is satisfied solely by this contract phase.

## Subsequent local demonstration update — 2026-10-08

The pinned inventory and PR1 evidence above are historical. Current local work implements the authenticated service, private SQLite, durable exact-review transitions, initial policy corpus and isolated connected local API demonstration. Current evidence: 64 Swift tests, 103 backend tests, 22 native renders, and actual native/XPC/loopback HTTP lifecycle checks. See [service evidence](MVP2_SERVICE_EVIDENCE.md), [initial rules evidence](MVP2_RULES_EVIDENCE.md) and [connected API evidence](LOCAL_API_DEMO_EVIDENCE.md). Full live-host and release gates above remain unmet; neither synthetic verdicts nor the separate single real Haiku diagnostic closes them.

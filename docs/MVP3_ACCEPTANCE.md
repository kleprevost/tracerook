# MVP3 acceptance matrix

Requirements: [MVP3 specification](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md) and [handoff](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Coding_Agent_Handoff.md). Audit as of **2026-10-08**, source **`e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7`**. Details: [baseline](MVP3_BASELINE.md), [PR 1 plan](MVP3_PR1_PLAN.md), [deviations](MVP3_DEVIATIONS.md), [public claims](PUBLIC_CLAIMS.md).

**MVP3 is not implemented or released.** PR 0 completes the audit of available source/development artifacts; reconciliation with the package's reported shipping MVP2 release remains open. No live-host protection, real BYOK, hosted Claude, private alpha or notarized download is inferred from passing foundation tests.

## PR 0 acceptance

| Required audit item | Result | Evidence / remaining condition |
|---|---|---|
| Pin accessible source and public deployment | passed | Local/public main SHA above; Cloudflare Pages successful check and deployment `03b41904-e68f-4fcd-9136-3d1e6617c1d4`; live site inspected |
| Locate actual shipping MVP2 tag / app | not run — unresolved | No tags/releases or separate source/binary discovered in inspected locations; shipping identifier requested; no claim of exhaustive external discovery |
| Record exact development binaries | passed | 0.1.0/build 1; fresh debug/optimized executable hashes and signatures captured; optimized hashes in baseline |
| Preserve runtime behavior | passed | PR 0 changes documentation only; runtime, tests, build scripts and website hashes unchanged |
| Native regression | passed | 43 existing tests; three debug/optimized arm64 products; helper/self-test/protocol/resource/signature checks |
| Working native demonstration | passed, preview only | 20 light/dark renders; representative real overview and fixture provider UI reviewed; debug/optimized native Scene launch visible |
| Installed host versions / configuration preservation | passed, read-only | Claude Code 2.1.290; Codex 0.162.0-alpha.2; local config bytes/modes/existence unchanged |
| Real host deny, review, Allow Once, timeout and permission regression | not run | No running service/hook/policy prerequisites in this checkout; no host callback or trust changes authorized in PR 0 |
| Real BYOK and persistent security service regression | not run | No corresponding runtime in inspected source; cannot claim regression of an unavailable shipping artifact |
| Developer ID / clean distribution | failed on development bundle | Ad-hoc identity; Gatekeeper exit 3; no stapled ticket, exit 65. Signed shipping artifact still unknown |
| Notification delivery, Focus, VoiceOver, macOS 26, Xcode archive, latency | not run | No permission or platform changes; render harness is not acceptance of these gates |
| Existing public claims reconciliation | passed, preview scope | README and deployed roadmap correctly say MVP2 foundation complete and live runtime/BYOK pending; public website unchanged |
| Smallest accurate PR 1 plan | delivered for review | Isolated contracts, transient semantic projection, preview parity, strict preflight and injected synthetic transport; no live security substitution |

`passed` applies to each bounded executed check, not to the missing shipping baseline. `failed` applies to the executed distribution assessment, not an untested shipping binary. Missing credentials or missing code produce `not run`, not a fictitious success or an assumed regression.

## Incremental implementation sequence

Every PR must preserve baseline tests and compile all three native products, include a working demonstration of only its actual behavior, update this matrix and the claims registry, and provide exact source/deployment identifiers. No stage is accepted because its UI merely renders.

| Phase | Required implementation and automated gates | Required demonstration | Current status |
|---|---|---|---|
| **MVP3.0 / PR 0** | Immutable source/binary/deployment inventory, current tests, live/demo/BYOK/service/storage/release audit, smallest PR 1 plan | Available native preview and truthful release-state record | Available-preview audit passed; shipping release reconciliation unresolved; review pending |
| **MVP3.1 / PR 1** | Strict Cloud v1 DTOs, duplicate/unknown-key rejection, exact preview projection, consent/origin/deadline gating, 20+ seeded privacy cases, fake transport and retained mode/permission semantics | Clearly synthetic provider contract demonstration with zero sends for demo/revoked/unsafe input | Not started; [plan](MVP3_PR1_PLAN.md) prepared |
| **MVP3.2 / PR 2** | Worker/D1/atomic DO or documented equivalent; enroll/capabilities/usage/analysis/rotate/revoke/delete; invalid/revoked/expired token, cross-account, concurrent invite/quota, replay/body conflict, floods, secret-free logs, kill switch and rollback tests | Restricted staging, explicitly fake upstream, authentic enrollment and usage accounting; no fake Claude claim | Not started; existing external API unverified; free-tier constraint retained |
| **MVP3.3 / PR 3** | Server-owned first-party Messages call, configured/verified model, strict structured outputs, real provenance/tokens, deadline/cost bounds, 401/403/429/500/529/malformed/late handling | Real TraceRook-owned upstream request and matching receipt/Console usage; key remains server-side | Not started; workspace/key/spend authorization and deployment unverified |
| **MVP3.4 / PR 4** | Native invite/consent/preview, service-owned Keychain token, authenticated XPC, disconnect/rotate/revoke, actual usage, provenance, mode switching, cancellation and degraded states | Signed clean-install Mac connects, performs real evaluation, switches BYOK and disconnects without losing local security/history | Not started; authentic shipping runtime and signed environment required |
| **MVP3.5 / PR 5** | Real supported Claude/Codex host regressions, 60 privacy-safe classification cases, latency/cost/failure calibration, independent local policy/approval preservation | Real agent event → hosted Anthropic → validated native incident; separate absent-sentinel local deny; ≥10 real hosted successes and accurate proof video | Not started; no authentic live model or host evidence |
| **MVP3.6 / PR 6** | Evidence-linked claims, current release/download hash, privacy/security disclosures, verified founder/contact, operational access request, startup proof/application copy | Every live statement traceable to immutable evidence; request-access process works; draft/partnership status honest | Registry initialized; public changes and submission not started |
| **MVP3.7 / PR 7** | Invite-only staged cohort, 48-hour auth/spend/latency checks, revoke/delete, provider failure and rollback drills, clean-install acceptance | Founder plus 2 testers before 10, then ≤25 only after stability; authentic private operations receipts | Not started; optional for application submission, required before scaling |

## No-go release gates

- [ ] Actual shipping MVP2 SHA/tag and authentic distributed app reconciled, tested and preserved.
- [ ] Signed/authenticated local service, supported host runtime, service-owned approvals, native permissions and deterministic denial preserved.
- [ ] Genuine supported Claude Code hook event reaches TraceRook-operated Cloud and first-party Anthropic, then a validated native incident.
- [ ] Separate real host denial leaves a harmless execution sentinel absent; Codex claimed classes pass installed-version tests.
- [ ] TraceRook-owned Anthropic key stays server-side; BYOK goes directly to Anthropic; device credential is scoped and Keychain-owned.
- [ ] Explicit consent, exact preview parity, double redaction, second preflight and immediate disconnect block future event egress.
- [ ] Invitation/auth/device isolation, rotation/revocation/deletion, parallel quotas, idempotency, spend ceilings and kill switch pass.
- [ ] No raw action/transcript/path/secret/model explanation in hosted persistent receipts or logs; retention and deletion drills pass.
- [ ] Real model/trace/token receipts and ≥10 successful non-fixture requests; health-only and fake transport never count.
- [ ] Model advice cannot grant permissions, override local catastrophic rules or reuse a human approval; late/invalid/unavailable results are not safe verdicts.
- [ ] Signed/notarized native Cloud workflow, existing-store compatibility, notifications/accessibility and actual deadline performance verified.
- [ ] ≥60-case evaluation, honest methodology, restricted founder trace and safe evidence/video bundle exist.
- [ ] Website, README, access workflow, privacy/security disclosures and claims registry match actual release evidence.
- [ ] No Anthropic acceptance, partnership, endorsement or tester count claimed without independent evidence.

No checkbox above is satisfied by PR 0's contract tests, render output, installed agent detection or successful static-site deployment. The application program is an external founder decision, not a software acceptance gate.

## Security and operational delta for PR 0

New event fields transmitted: none. Product DB/Keychain fields: none. Authentication scope: unchanged. Outbound event-analysis domains: none added. Host deny/no-override/approval semantics: unchanged. Consent flow and existing fixture transport: unchanged. Raw audit artifacts remain under ignored `build/mvp3-baseline/`, with private config hashes permission-restricted; committed files contain no credentials, invitation values, production request bodies, billing/account identifiers or unredacted operational logs.

Actual infrastructure deployments and feature flags in PR 0: **none**. Existing static production remains on the user-authorized free Cloudflare setup. No paid provider canary runs automatically. Follow the handoff's review boundary before PR 1; unresolved release identity does not permit fake live functionality.

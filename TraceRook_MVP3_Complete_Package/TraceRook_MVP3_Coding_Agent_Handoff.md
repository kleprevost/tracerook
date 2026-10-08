# TraceRook — MVP3 Coding Agent Handoff

**Read first:** `TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md` (authoritative MVP3 requirements); deployed MVP2 release tag and its acceptance tests; then `TraceRook_MVP2_Architecture_Implementation_Spec.md` for pre-execution security guarantees.

## Your mission

Extend the *shipped* native macOS TraceRook app with a minimal production-backed **TraceRook Cloud private alpha**. Selected real coding-agent activity must travel, after user consent and strict local minimization, to a TraceRook-operated backend that calls **the first-party Anthropic Claude Messages API using a TraceRook-owned key**, returns a strictly validated advisory risk verdict, and displays it in the existing native app with accurate provenance. Preserve local Claude Code/Codex interception, deterministic denial, authenticated UI approval, existing BYOK, and demo separation. Do not rewrite MVP2.

**Critical:** The founder reports MVP2 shipped, but the accessible public `main` still describes an incomplete MVP2 preview. Verify the *actual* shipping source and binary before editing. This is a release-state audit, not permission to discard the user's statement or rebuild prior features.

## Always-on engineering constraints

- Swift 6 + native SwiftUI for macOS 26+ on Apple Silicon. No Electron, webview-driven app, root daemon or system-wide interception.
- Existing local security service owns network analysis, Keychain device secret, persisted incidents and decisions. Signed/authenticated control plane must stay intact.
- Model output is **advisory only**. Local deterministic catastrophic deny and exact-tool-call approval binding cannot be undone remotely. A model allow never becomes a host permission grant.
- Preserve BYOK direct to Anthropic; hosted TraceRook Cloud uses **only** the TraceRook-owned server-side key.
- Cloud Demo remains fixture-only and *cannot* receive/live-process real activity. Source provenance appears in every session and incident.
- No raw tool input/transcripts/credentials/absolute paths/raw source dumps in Cloud request, DB, logs, exception reporting or video artifacts. Consent and exact outgoing-data preview before egress; second preflight can prevent network calls.
- No fake backend/usage/Claude request is presented as real in a production build. Staging fake upstream is labeled synthetic.
- Always respect the host's remaining pre-execution hook deadline. A timeout is not a safe verdict.
- Publish planned capabilities as planned; `private alpha` claims require an operational private alpha. Do not assert Anthropic approval/partnership.
- Never commit Anthropic or Cloud keys, production invitation values, API request bodies, production logs or screenshots with identifiers.

## Implementation order (separate, reviewable PRs)

### PR 0 — Reality/baseline reconciliation

**Tasks:** Pin actual shipping MVP2 SHA/tag and deployed `.app` build; collect supported Claude Code/Codex versions; record current functional BYOK, host blocking, notification, storage and release behavior; run build/test/safe-host tests; compare public README/site to live release. Add `docs/MVP3_BASELINE.md`, `docs/MVP3_ACCEPTANCE.md`.

**Accept:** No existing MVP2 behavior changes. Each capability has `verified`, `not run`, `broken`, or `out of scope`, with evidence and exact binary/SHA. If the shipping tag is unavailable, stop *mutating production configuration*, but continue building isolated Cloud code and transparent mocks.

### PR 1 — Cloud v1 contracts and client outbound privacy

**Tasks:** Create strict JSON DTOs (Cloud enroll, capabilities, analysis, usage, errors, revocation) and a new `TraceRookCloudProvider` implementing existing `AnalysisProvider`; map verdict to `AnalysisVerdict`. Add ephemeral local feature projection, `CloudEgressBuilder`, double-redaction and privacy preflight, user preview parity, separate demo/live origins. Provider network implementation stays injectable behind a fake transport.

**Accept:** Contract fuzz tests and 20+ privacy seeded cases; schema mismatch/unknown keys rejected; no demo → live request; BYOK regression; no existing hook or native permission changes.

### PR 2 — Cloud API foundation

**Tasks:** Create `cloud/` TypeScript Worker package (or formally document equivalent existing backend), D1 migrations, per-account quota/idempotency DO, invite CLI, Keychain-safe enrollment credential flow, `/alpha/enroll`, `/capabilities`, `/usage`, `/device/rotate`, `/device/revoke`, `/privacy/delete`, strict `/analysis` contract with fake upstream. Configure `api.tracerook.dev` staging and prod, secret store, CI, WAF/rate limits, logs/metrics redaction, kill switch.

**Accept:** Cannot use inference anonymously. Concurrent invite redemption, quota spend, invalid/revoked token, cross-account access, replay and request/body floods are rejected. Production environment has a real rollback procedure; fake upstream results are labeled fake.

### PR 3 — Anthropic hosted inference

**Tasks:** Implement one-shot first-party Messages call to `https://api.anthropic.com/v1/messages` using server secret, configurable model (initially `claude-sonnet-5-5`), fixed versioned untrusted-evidence prompt and `output_config.format` strict JSON schema. Parse/validate verdict + provider provenance, upstream `request-id`, actual token usage, server timings; enforce spend/deadline caps, zero raw content logs and bounded failures. Keep provider rate limit handling consistent with official Anthropic API.

**Accept:** Authentic **first-party API call** with TraceRook-owned Console account and restricted founder trace evidence; account token usage aligns with server receipt. No client or repo can recover key. Invalid/late results never become allow.

### PR 4 — Native Cloud private-alpha flow

**Tasks:** Add Cloud provider to existing Settings/onboarding, consent/preview, enter invite, connect status, secure token rotation/disconnect, actual usage UI, connectivity diagnostics, degraded/quotas messages. Capture exact Cloud vs BYOK vs local-rule source in incident records and notifications. Reuse XPC/service ownership; no network code from the UI for event analysis.

**Accept:** A notarized clean-install Mac can join, use Cloud, switch to BYOK, disconnect and revoke while local rules continue. Health check never sets `liveAnalysisValidatedAt`; only a real successful evaluation can.

### PR 5 — Real-host demonstration, evaluation and abuse tests

**Tasks:** Use a disposable repository and legitimate task; run actual Claude Code and supported Codex class compatibility tests; induce synthetic suspicious activity safely; show real cloud verdict in incident. Independently prove a locally denied `/tmp` sentinel command never executed. Implement ≥60 synthetic security classification cases; run latency/cost/timeout eval; evaluate preflight false positives and review rates; capture release and cloud manifest.

**Accept:** One screen recording makes it possible to distinguish **real Claude assessment**, **host hook interception**, and **local enforcement**. 10+ authenticated Anthropic-backed requests on TraceRook's own API workspace. No sensitive private artifacts leak.

### PR 6 — Public materials / Startup readiness

**Tasks:** Update README, security/privacy docs, site feature statuses, cloud alpha CTA/waitlist, founder identification/contact, download/release hash, short video, Cloud API provenance example, `docs/STARTUP_PROOF.md` and `docs/PUBLIC_CLAIMS.md`. Build `TraceRook_MVP3_Startup_Application_Kit.md` into checked-in docs or link from site. Do not expose internal billing/account identifiers.

**Accept:** Every claimed currently-live feature references evidence; outdated preview status is fixed; feedback/alpha invitation request works; application is ready to submit or update.

### PR 7 — Limited alpha (optional to application submission; required before expanding signups)

**Tasks:** Founder + 2 testers, then 10, later ≤25 on invite list, 48-hour incident/spend/latency tracking, delete/revoke drills, fresh macOS install, provider error/rollback drills.

**Accept:** Ops dashboard and founder can identify real provider requests and quota drift; no unbounded spend or ongoing secret exposure. Auth and transport blockers fixed before scaling.

## Implement these exact behavior distinctions

| Situation | Correct resulting behavior |
|---|---|
| Verified local critical rule finds direct catastrophic signature | Deny locally; no model result can override; cloud analysis optional/retrospective if privacy permitted, never necessary for denial |
| Suspicious but context-dependent action with usable hook deadline | Build minimized context, submit Cloud analysis, use advisory verdict to inform warning/user review |
| Claude response says `allow` | Do not emit native host permission grant; pass through TraceRook only when local policy permits |
| Anthropic rate limit, malformed response, timeout or API cost cap | Mark unavailable/degraded; use policy fallback; never `analyzed: true` |
| Host callback not verified or not covered | UI says limited/monitoring; cloud evaluation cannot convert to protected status |
| UI demo sample is present | Must never be sent as a real Cloud evaluation or labeled as user activity |
| User disconnects / revokes consent | Stop future Cloud event network egress immediately, then revoke token when reachable |
| Same request ID reused with a different body | Conflict/error, no second billed provider call |
| Cloud storage/logging | Metadata only, no original action text or model explanation by default |
| Review/Allow Once after cloud finding | Bound to same exact local invocation, same host-native permission semantics as MVP2 |

## Tests/commands to leave in the repo

```bash
# Preserve existing baseline commands; execute from repo root
./scripts/test.sh
./scripts/smoke-test.sh
./scripts/ui-smoke-test.sh
# New cloud tests (names can be adapted to actual project tooling)
cd cloud && npm ci && npm run typecheck && npm test
# Staging-only real provider smoke with disposable synthetic input:
# npm run smoke:anthropic:staging -- --confirm-billable
# Use wrangler or equivalent with explicit staging/prod profiles.
```

Create deterministic test helpers for CI: fake Anthropic transport, fake clock/deadline, in-memory auth/quota store and replay tests, safe host test repo, opt-in billable staging smoke. No production live-call test should run automatically on every PR.

## Required outputs from every PR

1. `git diff --stat` + exact commit SHA; docs of which MVP3 phase was implemented and what remains.
2. Automated test counts, real-host test evidence where relevant, and limitations. Separate `passed`, `not run`, and `failed`.
3. Security/privacy checklist: any new transmitted field, stored field, auth scope, outbound domain, change in host decision semantics or consent flow.
4. Reproduction instructions on a clean Apple Silicon Mac and staging backend; any actual deployments and feature flags (or say none).
5. Screenshots/video only where they add genuine evidence; never fake provider receipts.
6. Update `docs/MVP3_ACCEPTANCE.md`, `docs/IMPLEMENTATION_STATUS.md` and public claim registry when feature state changes.

## First coding-agent instruction — copy verbatim

> Read `TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md` and this handoff. Treat the founder's statement that MVP2 is shipped as the intended baseline, but independently reconcile it with the actual shipping tag, default-branch files and deployed binary. Execute **PR 0 only**: inventory runtime source, deployment SHA, agents tested, app/version, BYOK, service, hooks, cloud/demo distinction, and existing acceptance. Run nondestructive tests. Create `docs/MVP3_BASELINE.md` and an evidence-based `docs/MVP3_ACCEPTANCE.md`. Do not install hooks, edit user-agent configs, rotate tokens, deploy infrastructure or claim feature completion. Return the audit and smallest accurate PR 1 plan. Then await normal repo-review/merge workflow before PR 1.

## Deployment go/no-go

**Go:** One production-backed, consented, redacted real coding-agent event → TraceRook Cloud → Anthropic Claude → validated provenance-carrying verdict → local Mac incident with accurate approval/coverage; budget/auth/privacy controls proven; product materials accurate.

**No-go:** Mocked Cloud results shown as real, leaked server API key, unchecked invite/usage, unconsented data egress, BYOK keys proxied to TraceRook, unsupported auto-authorize, website claims overstating verified protection, missing Anthropic request provenance, or no rollback/kill switch.

**Important:** Anthropic Startup acceptance is an external decision, not a software-test gate and not a promise. Apply when eligible, update with verified evidence; do not require approval before MVP3 implementation.

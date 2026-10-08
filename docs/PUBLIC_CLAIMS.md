# Public capability claims

Reviewed **2026-10-08** by the TraceRook maintainer audit. Scope: source `e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7`, native development app **0.1.0 / build 1**, static production deployment `03b41904-e68f-4fcd-9136-3d1e6617c1d4`. The actual shipping MVP2 app is unresolved; this record does not replace its evidence if supplied.

Requirements: [MVP3 claim rules](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md). Evidence: [baseline audit](MVP3_BASELINE.md), [MVP2 acceptance](MVP2_ACCEPTANCE.md), [MVP3 acceptance](MVP3_ACCEPTANCE.md). Registry owner: **TraceRook maintainers**; each row's review date is 2026-10-08. This document records allowed current wording, not published launch copy.

| Capability | Current evidence/state | Allowed current wording | Claim still gated |
|---|---|---|---|
| Native macOS app | Three native executable builds; native Scene launch; development signature only | “Native macOS development preview for Apple Silicon” | Released signed/notarized security app or clean-install availability |
| Native UI / Cloud Demo | Fixture tests, 20 renders, demo/live rejection; actual usage/account synthetic | “Explore bundled Cloud Demo sample data” | Real Cloud account, billing, usage or hosted analysis |
| MVP2 foundation | 43 tests and strict v2 codec/DTO/self-tests from the audited source | “MVP2.0 foundation passed locally; live protection remains pending” | “MVP2 real-protection beta shipped” without the actual shipping evidence |
| Claude backend | Architectural intent; no live provider transport in inspected checkout | “Designed around Anthropic Claude for planned contextual analysis” | “Uses the Anthropic API today” or a real request receipt |
| BYOK | Settings explicitly unavailable; no provider/Keychain runtime inspected | “Direct Anthropic BYOK is planned” | Working direct BYOK, API key connection or authenticated inference |
| TraceRook Cloud | MVP3 specification and isolated PR 1 plan; hosted runtime not verified | “TraceRook Cloud is planned / in development” | Operational private alpha, Cloud connected, real Claude analysis or invitation availability |
| Claude Code / Codex support | Fixture adapter tests; binaries detected; no actual host deny tests | “Designed for supported local Claude Code and Codex hooks; live integrations pending” | Protected badges or verified tool-class/version support |
| Pre-execution enforcement | DTO/deny encoding and refusal only; no host body/canary evidence | “Pre-execution enforcement is a release gate” | “Blocked before execution” for real activity |
| Human review | In-memory exact-binding/expiry/replay tests and clearly labeled sample review | “Native sample review demonstrates the intended experience” | Service-owned authenticated live approval, native permission preservation or notification success |
| Privacy | Existing seeded utility tests; no event-analysis transport | “Cloud Demo makes no analysis network requests; planned remote processing requires consent and local minimization” | Absolute leak prevention, global zero retention or completed Cloud privacy boundary |
| Performance / effectiveness | No representative live benchmark or efficacy corpus result | Publish explicit engineering targets as targets only | Measured production p95, accuracy or breach-prevention percentages |
| Startup affiliation / traction | Supplied draft application kit only; no acceptance/tester proof | “Independent project; no Anthropic endorsement implied” | Partner, approved program member, certification or invented customer/tester count |

README and the public `/docs/roadmap/` were inspected and agree with this preview status. No website or marketing copy changes are made in PR 0. Keep the distinction between intended architecture and working behavior even when Claude is prominent on the homepage.

Before upgrading a row, record the immutable app/source/Cloud versions, exact host classes, relevant automated and real tests, evidence owner and new review date. Real Cloud analysis requires first-party provenance and usage; health/auth connectivity does not substitute. Protection separately requires real pre-tool denial and authenticated local policy/approval evidence. Program acceptance requires an actual notice and applicable branding permission.

Do not publish internal account/billing identifiers, upstream founder-only diagnostics, keys, invitation values, production payloads or private screenshots. Public evidence uses sanitized trace references and stated scope. Supplied startup copy remains a draft until amended to match these rows.

## Later local development delta — 2026-10-08

The table above is the historical audit of `e2615b8`, not a statement that newer local source lacks the service. Subsequent work implements authenticated local transport, private SQLite, durable review transitions, an initial 50-case policy corpus and a connected synthetic API demonstration. Current validation: 64 Swift tests, 103 backend tests, 22 native renders and actual native/XPC/HTTP lifecycle checks. Fixture results leave real history and coverage unchanged.

Allowed current wording: “The native development app connects to an authenticated local mock API; fixtures have no protection authority.” A separate authorized probe validates one actual Anthropic Haiku 5.5 verdict using 798 input/178 output tokens in 3,006 ms. Allowed wording is “One isolated developer Anthropic test succeeded.” This does not support “The native client performs real Claude analysis,” “Operational proprietary cloud backend,” or “Verified host protection.” No backend is deployed; native real-provider and live-host gates remain pending. Evidence: [connected API record](LOCAL_API_DEMO_EVIDENCE.md), [service record](MVP2_SERVICE_EVIDENCE.md), [policy record](MVP2_RULES_EVIDENCE.md).

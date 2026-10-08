# MVP3.1 / PR 1 — smallest accurate implementation plan

This plan follows [PR 0's observed baseline](MVP3_BASELINE.md), [MVP3 requirements](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md) and the [handoff](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Coding_Agent_Handoff.md). **No work in this plan is implemented by PR 0.** Normal review precedes PR 1.

The shipping MVP2 runtime is unresolved. PR 1 may implement isolated Cloud contracts/privacy behind an injected synthetic transport; it must not activate a provider in the native app, install hooks, create a UI network client, or retrofit fake service authentication. Before wiring live Cloud, audit the supplied shipping runtime or resolve the unfinished MVP2 runtime as separately reviewed work.

## Additive source changes

| File / area | Concrete scope |
|---|---|
| `Packages/TraceRookContracts/CloudAuthV1.swift` (new) | Strict enrollment, capabilities, usage, typed errors, own-device rotate/revoke/delete DTOs; bounded version/IDs/enums/timestamps; no account scope taken from untrusted input |
| `Packages/TraceRookContracts/CloudEvaluationV1.swift` (new) | Canonical bounded `/v1/analysis` request/context and server-issued provenance/usage envelope; no local fingerprint, raw action/transcript/path, arbitrary model/system/tools or fixture origin on the wire |
| `Packages/TraceRookContracts/CloudJSONCodec.swift` (new) | Bounded raw HTTP JSON scanner rejecting duplicate decoded keys at every depth, invalid UTF-8, extra keys, stale versions, excessive cardinality and unsupported precision. HTTP JSON must not require the IPC length prefix; extract/reuse the existing scanner only with unchanged IPC regressions |
| `Packages/TraceRookPrivacy/CloudEgressBuilder.swift` (new) | Transient typed semantic projection from original host input; source/event/action allowlists, coarse task/project/network categories, fresh session pseudonym, ≤6 constrained recent summaries, policy signal allowlist |
| `Packages/TraceRookPrivacy/OutboundPreflightV2.swift` (new) | Redact twice and independently reject residual secrets, full paths, environment dumps, suspicious entropy/obfuscation, unsafe source excerpts and oversized serialized payloads. Preflight failure skips Cloud, not local policy |
| `Packages/TraceRookCore/CloudEvaluationContext.swift` (new) and `Models.swift` | Attach typed optional Cloud context to existing `AnalysisRequest`, with defaults preserving all old callers/readers. No context or missing consent fails before transport. Keep `AnalysisVerdict`, `DataOrigin` and `ApprovalBinding` authority intact |
| `Packages/TraceRookCore/TraceRookCloudProvider.swift` (new) | Conform to existing `AnalysisProvider`; explicit consent gate, frozen approved request bytes, injected async transport, fake clock/deadline, cancellation and strict returned request/device/provenance/verdict checks |
| `Contracts.swift`, `LiveIPC.swift` | Add a distinct Cloud-alpha mode only as needed for provider identity; handle exhaustive switches explicitly. Keep it unavailable in production during this phase; existing demo/local/BYOK status meaning and v1/v2 readers must not change |
| `Tests/{Contracts,Privacy,Core}Tests/` | New Cloud contract, privacy, preview-parity, origin, provenance, timeout and permission-preservation tests; fixtures explicitly synthetic and credential-free |
| `Package.swift` / Xcode source inventory | Add only necessary module dependencies/source membership; preserve native build and render entry points |

Keep the existing flat `CloudAnalysisPayload` / `CloudAnalysisResponse` and `CloudAPIClient` fixture interfaces intact. Introduce explicit new v1 live types and mappings, not a silent reinterpretation of their old encoded fields. Credential responses must never gain an automatic printable/loggable representation. A test credential store may exercise ownership contracts; actual Keychain access and authenticated XPC provisioning belong to the later service/native phase.

## Frozen request and consent boundary

1. Reject `DataOrigin.demo`, unconsented mode, missing typed metadata, revoked consent and insufficient remaining deadline before forming or sending live Cloud input.
2. Extract narrow enumerated features from original arguments in transient memory. Produce constrained summaries; do not persist or send originals, absolute paths, repository identity, host session ID, domain/IP, source dumps, fingerprint or approval IDs.
3. Project allowed fields, redact, enforce Unicode and serialized-byte bounds, then run independent residual-secret/path/entropy preflight over the exact serialized body.
4. Present a preview derived from that same immutable projection. Bind consent to the policy version, categories and exact projected bytes. If the content or consent generation changes, invalidate the prior approval and preview.
5. Recheck consent and the deadline at transport dispatch, including cancellation races. The injected transport receives only the approved bytes and narrowly scoped credential; rejected/demonstration requests must yield zero transport invocations.
6. Validate response limits, schema, matching request, source/provenance and server-issued usage; decode into `AnalysisVerdict` and sanitize any later display/persistence. Model-only recommendations remain allow/warn/review. No provider calls an approval resolver or returns a host grant.

PR 1 has **no concrete production HTTP transport**. A recording fake transport makes the allowed bytes observable in tests and is explicitly synthetic. It cannot claim a real Anthropic receipt or set a real-analysis timestamp. Health and enrollment state never imply verified host protection or successful inference.

## Exact protocol limits to implement

- UTF-8 JSON; client schema 1; hard total request cap **32 KiB**.
- Task summary ≤512 Unicode codepoints **and** 1 KiB; proposed action summary ≤1,024 **and** 2 KiB.
- At most 12 allowlisted local signal codes; at most 6 recent summaries, each ≤160 characters with an explicit serialized-byte bound.
- UUID request/device/session pseudonym; only `claude_code` / `codex`; permitted event/action enums; excerpt flag must be false in this phase.
- Cloud deadline 1,000–12,000 ms, capped by actual remaining monotonic host/model budget minus local/output reserve. Never round an infeasible budget upward or retry beyond it.
- Strict response/error/provenance/usage caps must be recorded in `CLOUD_API.md`; reconcile the illustrative schema with the existing verdict validator without permitting additional authority. Fake and real transport provenance must be distinguishable.

The specification leaves several endpoint DTOs and response/scanner limits illustrative. PR 1 must document chosen bounds in `MVP3_DEVIATIONS.md` / `CLOUD_API.md`, maintain compatibility and test every boundary. Do not change the authoritative source package to hide these design decisions.

## Acceptance tests and demonstration

Retain all **43 current tests**, all three debug/optimized executables, packaged helper demonstrations and **20 native render cases**. Add strict round-trip/unknown-field/duplicate-key/Unicode/cardinality/version/ID/enum/precision tests and at least **20 separately named or parameterized privacy seeded cases**.

Privacy corpus: Anthropic and Cloud bearer material, AWS access/secret keys, PEM blocks, `.npmrc` and GitHub tokens, credential assignments, authorization headers, env dumps, absolute/home/internal project paths, Git remotes, host session identifiers, hostname/IP, source dumps, data URIs, base64/high-entropy and multiline/Unicode obfuscation. Include benign near-misses so a passing scanner does not merely reject every body.

Test preview/transmitted-byte parity, fresh pseudonyms, fixture rejection before transport, disabled excerpts, consent revocation before dispatch and in flight, changed payload invalidating approval, impossible deadline, cancellation, expired/mismatched response, fake provenance, malformed/contradictory verdict, forbidden grants, redacted error handling and no raw persistence/log fields. Keep native deny/no-override output tests and existing BYOK-mode behavior unchanged. **A real BYOK regression cannot be claimed until its shipping implementation is located.**

Demonstration: a disposable synthetic live-origin request yields a constrained preview and records exact approved bytes in an injected fake transport; seeded unsafe input and demo origin yield zero sends. Label all evaluations/receipts synthetic. Native Cloud Demo and real Not integrated views continue to work unchanged. This is a privacy/contract demonstration, never a real host or hosted-Claude demonstration.

## Boundaries for later PRs

PR 2 adds Worker/D1/DO/auth/quota/idempotency and an explicitly fake upstream; PR 3 requires real first-party Anthropic evidence; PR 4 integrates through an authenticated service, secure credential owner and native consent flow. All depend on the actual shipping baseline before live integration. Preserve the Cloudflare **free-tier** requirement and verify current deployment compatibility before provisioning; document any genuine platform incompatibility before selecting a substitute. The proposed Anthropic model and API spend cap are configuration proposals, not verified availability or permission to incur charges.

PR 1 must update `MVP3_ACCEPTANCE.md`, `IMPLEMENTATION_STATUS.md`, `PUBLIC_CLAIMS.md`, and the documented transmitted/stored-field inventory. No site publication, Cloud deployment, tokens, provider billable calls, hook installation or partnership claims belong to this phase.

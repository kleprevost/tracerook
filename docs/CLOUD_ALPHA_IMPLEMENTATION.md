# Cloud alpha implementation checkpoint

Reviewed 2026-10-08. This is an implementation checkpoint, not evidence of deployed protection. The original MVP3 package remains authoritative except for the explicit founder overrides recorded in [deviations](MVP3_DEVIATIONS.md).

## Implemented

The new `cloud/` TypeScript Worker uses D1 for digest-only invitations/device authentication and a SQLite-backed Durable Object for atomic accounting, request identity, lifecycle recovery and temporary verdict caching. Its fixed upstream is Anthropic's first-party Messages API with Claude Haiku 5.5. There are no fixture responses in the hosted analysis handler. Local tests use a test-only fake upstream inside the actual Workers runtime; they do not demonstrate billed inference.

Native Settings → AI Provider → TraceRook Cloud · Invited alpha exposes explicit versioned consent, secure invitation entry, asynchronous enrollment, capabilities, usage, rotation, disconnect and account deletion. The authenticated background service owns HTTPS and credentials; UI replies never contain tokens. Capabilities and enrollment cannot set `realAnalysisValidatedAt`; only a request-bound, validated analysis receipt can set it. Cloud availability is separate from supported host coverage.

Live requests use a separate strict v1 contract with no fixture/scenario fields. Construction rejects Demo origin. The current projection accepts fixed task/action vocabulary and enumerated signals; it does not accept caller-provided summary prose, commands, paths or code. An independent secret/path/URL/entropy preflight checks summaries. This conservative projection limits model context and must be evaluated on real host cases before richer extraction is claimed. The UI control protocol deliberately has no analysis operation, so it cannot send its Demo fixture events to production.

Native credential storage is **not accepted and is disabled**. Actual disposable login-Keychain tests triggered system prompts despite the requested no-UI flag and returned data to a separate signed executable. The founder explicitly requested that these tests stop. The popup-generating test entrypoints and unproven store were removed; startup performs no cloud Keychain read and enrollment is unavailable. No plaintext or in-memory production credential substitute was introduced. A corrected, explicitly authorized platform verification is required before connecting the native enrollment flow. Developer ID signing/notarization remains unavailable and is not claimed.

## Commercial and budget decision

The founder explicitly requested no customer inference quota and no company spending cutoff on 2026-10-08. Daily evaluation/input/output and global monthly caps default to null. Actual usage and conservative unresolved reservations are still counted. Invitation checks, request-size/deadline bounds, concurrency limits, abuse rate limits, token expiry/revocation and an emergency disable switch remain. Optional capped configurations exist for operator testing, but are not enabled by default.

The intended price is $20/month for invited alpha users. Payment collection, subscriptions and customer billing are not implemented. No inference allotment is advertised; the absence of a software quota does not guarantee availability beyond Cloudflare/Anthropic platform limits.

## Remaining evidence gates

- Authenticate deployment tooling, create separate staging/production D1 databases, apply migrations and deploy on the current Workers Free plan without paid bindings.
- Configure a fresh server-side Anthropic secret through a secure operator entry flow. The key previously pasted in chat is not persisted or committed.
- Verify production DNS/TLS, unauthenticated rejection, enrollment, revoke/rotate/delete, operator disable and one explicitly billed synthetic canary. This diagnostic must remain distinguishable from a real host event.
- Connect and verify the actual pre-execution host path, deterministic policy, exact human approval and outage fallback. The current hook still denies ordinary invocations as nonoperational. Deploying the API does not close that gap.
- Complete real evaluation corpus, API Console correlation, operational rollback and the MVP3 acceptance checklist before claiming “everything works as intended.”

Deployment credentials, invitations, bearer tokens, submitted context and upstream response bodies must never enter this document, public artifacts, command arguments or Git history.

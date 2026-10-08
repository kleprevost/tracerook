# Cloud alpha implementation checkpoint

Reviewed 2026-10-08. This is an implementation checkpoint, not evidence of deployed protection. The original MVP3 package remains authoritative except for the explicit founder overrides recorded in [deviations](MVP3_DEVIATIONS.md).

## Implemented

The new `cloud/` TypeScript Worker uses D1 for digest-only invitations/device authentication and a SQLite-backed Durable Object for atomic accounting, request identity, lifecycle recovery and temporary verdict caching. Its fixed upstream is Anthropic's first-party Messages API with Claude Haiku 5.5. There are no fixture responses in the hosted analysis handler. Local tests use a test-only fake upstream inside the actual Workers runtime; they do not demonstrate billed inference.

Native Settings → AI Provider → TraceRook Cloud · Invited alpha exposes explicit versioned consent, secure invitation entry, asynchronous enrollment, capabilities, usage, rotation, disconnect and account deletion. The authenticated background service owns HTTPS and credentials; UI replies never contain tokens. Capabilities and enrollment cannot set `realAnalysisValidatedAt`; only a request-bound, validated analysis receipt can set it. Cloud availability is separate from supported host coverage.

Live requests use a separate strict v1 contract with no fixture/scenario fields. Construction rejects Demo origin. The current projection accepts fixed task/action vocabulary and enumerated signals; it does not accept caller-provided summary prose, commands, paths or code. An independent secret/path/URL/entropy preflight checks summaries. This conservative projection limits model context and must be evaluated on real host cases before richer extraction is claimed. The UI control protocol deliberately has no analysis operation, so it cannot send its Demo fixture events to production.

Beta credential storage uses the user's explicitly authorized minimal scope: digest-only tokens in the hosted database and an actual service-memory vault. Users enter an operator-issued beta access code through a SecureField; credentials never appear in UI replies. Restart requires re-entry. There is no native disk or Keychain fallback. Authenticated capabilities and usage checks must pass before accepting a code. Cloud analysis can be paused without revoking the code, and only explicit consent enables it. Developer ID signing and notarization remain unavailable.

Production is deployed at `https://api.tracerook.dev` using Cloudflare Workers Free, D1 and a SQLite Durable Object. The Anthropic key is a Worker secret. Deployment does not itself prove native host enforcement; that requires separate evidence.

## Commercial and budget decision

The founder explicitly requested no customer inference quota and no company spending cutoff on 2026-10-08. Daily evaluation/input/output and global monthly caps default to null. Actual usage and conservative unresolved reservations are still counted. Invitation checks, request-size/deadline bounds, concurrency limits, abuse rate limits, token expiry/revocation and an emergency disable switch remain. Optional capped configurations exist for operator testing, but are not enabled by default.

The intended price is $20/month for invited alpha users. Payment collection, subscriptions and customer billing are not implemented. No inference allotment is advertised; the absence of a software quota does not guarantee availability beyond Cloudflare/Anthropic platform limits.

## Evidence and remaining gates

- Worker type checking and 55 runtime tests pass. Production databases/migrations, DNS route, HTTPS and the inference enable switch are configured.
- [Beta evidence](BETA_E2E_EVIDENCE.md) records real Claude Code 2.1.290 callbacks, benign execution, deterministic denial, review timeout denial and service-outage denial. Those host tests use an isolated loopback model double and do not demonstrate hosted Claude inference.
- Hosted Anthropic receipts, native signed-client connection and complete host-to-cloud tests must be recorded separately before a beta release is claimed ready.
- Codex native hook trust review, second-Mac distribution checks, the full evaluation corpus and API Console correlation remain independent acceptance gates.

Deployment credentials, invitations, bearer tokens, submitted context and upstream response bodies must never enter this document, public artifacts, command arguments or Git history.

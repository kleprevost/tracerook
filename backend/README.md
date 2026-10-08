# TraceRook Cloud backend

Hosted service behind the app's **TraceRook Cloud** provider: accounts on a **$20/month Individual plan**,
API-key authentication, device enrollment, usage metering, and contextual analysis of risky agent actions
by Anthropic Claude. It is the real implementation of the contract the macOS client already models in
`Packages/TraceRookCore/Models.swift` (`CloudAPIClient`, `CloudAccount`, `CloudUsage`, `CloudPlan`,
`CloudAnalysisPayload`, `CloudAnalysisResponse`) and `TraceRook_MVP1_Architecture_Spec.md` §15.

> Status: backend only. The Swift `HTTPSCloudAPIClient` and the Settings UI for entering an API key are not
> written yet, and nothing here is wired into the shipping app. Billing/checkout is not implemented
> (accounts are provisioned with `tracerook-admin`); the account `state` field is the hook for it.

## Connecting a client

1. Base URL: wherever you deploy it (HTTPS only), e.g. `https://api.tracerook.dev`.
2. Every request except `GET /v1/plans` and `/healthz` sends `Authorization: Bearer trk_live_…`.
3. Once per install: `POST /v1/device/registrations` with `{"installation_id": "<client UUID>"}` (body optional;
   sending the same `installation_id` returns the same `device_id`). Keep the `device_id`.
4. Per analysis: `POST /v1/analyze` with the `CloudAnalysisPayload` JSON.

```sh
curl -sS -X POST "$BASE/v1/analyze" -H "Authorization: Bearer $TRACEROOK_API_KEY" -H 'Content-Type: application/json' -d '{
  "request_id": "6f1c…uuid", "schema_version": 1, "device_id": "dev_…", "session_pseudonym": "s-91ac",
  "task_anchor_redacted": "Fix the README layout.", "proposed_action_redacted": "npm publish",
  "prior_events_redacted": [], "privacy_policy_version": 1, "client_deadline_ms": 12000 }'
```

| Method & path | Auth | Returns (Swift type) |
|---|---|---|
| `GET /v1/plans` | none | `{"plans": [CloudPlan]}` (note camelCase `monthlyPriceLabel`, as the Swift struct has no CodingKeys) |
| `POST /v1/device/registrations` | key | `CloudDeviceRegistration` — 201 new, 200 existing |
| `GET /v1/account` | key | `CloudAccount` (`plan` is the display name) |
| `GET /v1/usage?month=YYYY-MM` | key | `CloudUsage` (`daily_actions[i]` = UTC day *i+1*) |
| `POST /v1/analyze` | key | `CloudAnalysisResponse` (`expires_at` has no fractional seconds, as `.iso8601` requires) |
| `POST /v1/events` | key | `{"acknowledged": true}`; validated, **not stored** |

Errors are always `{"error": {"code", "message"}}`:

| HTTP | `code` | Client `TraceRookError` | Notes |
|---|---|---|---|
| 401 | `not_authenticated` | `notAuthenticated` | missing/invalid/revoked key |
| 402 | `subscription_inactive` | *(new)* | account not `active` (canceled/past_due/suspended) |
| 402 | `quota_exhausted` | `quotaExhausted` | monthly plan quota used |
| 429 | `rate_limited` | `rateLimited` | honor `Retry-After` |
| 422 | `unsafe_payload` | `unsafePayload` | server preflight found unredacted secrets/paths |
| 400/413 | `malformed_request`, `payload_too_large` | `malformedInput` | |
| 404/409 | `device_not_found`, `device_limit_reached`, `duplicate_request` | *(new)* | |
| 503 | `provider_unavailable` | `providerUnavailable` | Anthropic down/declined; **not billed**; retry |
| 502 / 504 | `malformed_response` / `timeout` | `malformedResponse` / `timeout` | **not billed** |

The client must treat every non-200 as "no verdict" and fall back to local rules; a verdict is advisory and
never overrides critical local rules (`recommended_action` is only `allow`, `request_approval` or `warn_allow`).

## Guarantees (and how they're enforced)

- **No analyzed content is stored or logged.** SQLite holds accounts, hashed keys, devices and per-request
  *metadata* (ids, day, tokens, model, latency). Validation errors never echo input.
- **API keys:** 256-bit random, shown once, stored only as HMAC-SHA256 with a server pepper.
- **Server-side preflight** (`redaction.py`, port of the Swift `Redactor` patterns): payloads that would still be
  redacted are rejected with 422, not repaired.
- **Prompt-injection hardening:** fixed system prompt; all agent-derived text is JSON-encoded under `untrusted`;
  the output must satisfy a JSON schema *and* a strict validator that mirrors Swift `AnalysisVerdict.validate()`.
  Malformed or refused output yields an error, never a partial verdict.
- **Metering:** quota check + reservation is one atomic transaction; failures release the reservation; a retry with
  the same `request_id` within 2 minutes replays the response (`Idempotent-Replay: true`) without re-billing.
  Months are UTC.

## Run

```sh
cd backend && python -m venv .venv && . .venv/bin/activate && pip install -e '.[dev]'
pytest                                   # 70 tests, no network or API key needed

export TRACEROOK_ENV=production TRACEROOK_KEY_PEPPER="$(openssl rand -hex 32)" \
       ANTHROPIC_API_KEY=… TRACEROOK_DATABASE_PATH=/var/lib/tracerook/tracerook.db
tracerook-admin create-account someone@example.com     # prints the customer's API key once
uvicorn tracerook_backend.app:app_factory --factory --host 127.0.0.1 --port 8000   # behind a TLS proxy
```

See `.env.example` for all settings. `TRACEROOK_ENV=development TRACEROOK_ANALYZER=stub` runs without an Anthropic key
(refused in production) and enables `/docs`.

## Known limits / before launch

- **Single process.** Rate limiting, the replay cache and the SQLite writer are in-process: run one uvicorn worker
  per database. Horizontal scale means Postgres (`store.py` is the seam) and Redis (`ratelimit.py`).
- **No billing.** Wire Stripe webhooks to `Store.update_account(state=…)`; add self-serve signup and key rotation UI.
- **Cost model is a product decision.** Default model is `claude-opus-5-5` at `low` effort with a 2,000-action quota;
  per-call cost and latency on Opus are far above `claude-haiku-5-5`. Measure real token use (it's recorded in
  `usage_events`) before fixing price/quota/model. Haiku has no refusal fallback; `TRACEROOK_ANTHROPIC_MODEL` switches it.
- **Not exercised against the live Anthropic API** (no key in the build environment): request shape, structured
  output and the `server-side-fallback-2026-07-01` beta are verified only against a fake client and the SDK signature.
- Behind a reverse proxy, failed-auth throttling keys on the socket peer; configure the proxy/uvicorn
  `--forwarded-allow-ips` so the real client IP is used.

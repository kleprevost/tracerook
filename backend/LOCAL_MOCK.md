# Local API

The default server factory serves a loopback-only API backed by fixtures. It mirrors TraceRook Cloud's flows for development and the in-app Local API demo without calling Claude or storing anything. The native service owns the HTTP transport; the UI never receives credentials.

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/python -m uvicorn tracerook_backend.app:app_factory --factory --host 127.0.0.1 --port 8787 --no-access-log
```

Run checks with `.venv/bin/pytest -q`. The server binds to `127.0.0.1:8787`.

## Routes

All routes are under `/mock/v1/`. Responses carry `schema_version:1`, `simulation:true`, `Cache-Control: no-store` and `X-TraceRook-Request-ID`.

- `GET healthz` — no credential; reports `provider_ready:false`.
- `POST alpha/enroll` — `invitation_id:"local-demo"`, `consent:true`, `privacy_policy_version:2`. Returns `device_id`, `device_token` and `expires_at`. The token is random, returned once, held only as a SHA-256 digest and expires after one hour.
- `GET capabilities` — `provider:"fixture"`, `transport:"local_mock"`, `model_id:"synthetic-v1"`, `privacy_policy_version:2`.
- `GET usage` — `fixture_evaluations`, with zero tokens and billed units.
- `POST device/rotate`, `POST device/revoke` — `device_id` matching the bearer principal. Rotation returns a fresh enrollment and invalidates the old token.
- `POST privacy/delete` — matching `device_id` and `confirm:true`; clears the device's metadata and receipts and revokes its token.
- `POST analysis` — the exact `LocalAPIDemoRequest` from `Packages/TraceRookCore/LocalAPIDemo.swift`, including `simulation:true`, an allowlisted scenario and its predefined context. Returns a `LocalAPIDemoResponse` with fixture provenance.

## Request handling

Every authenticated route checks the bearer token, and devices are isolated from one another. Browser origins, unexpected `Host` headers, non-loopback peers, query strings, unsupported methods, malformed UTF-8, duplicate JSON keys, unknown keys, non-finite numbers and bodies over 32 KiB are rejected without echoing input. POST requests use `Content-Type: application/json`.

The same device and request ID with identical canonical JSON returns the same receipt for 120 seconds; a changed payload conflicts. Evaluations are serialized, and each device gets 30 successful fixture evaluations per UTC day. State resets when the process restarts. The outage, quota and deadline scenarios return typed 503, 429 and 504 errors without touching counters.

## Haiku diagnostic

`backend/scripts/probe_anthropic.py` is independent of the local API. Run `.venv/bin/python scripts/probe_anthropic.py` from `backend/` and enter the key at its hidden prompt, or pipe exactly one key line on stdin. Never put a key in arguments, environment variables, files or logs.

The script performs one HTTPS Models API lookup for `claude-haiku-5-5`. On an exact match it sends at most one Messages request with fixed benign context: low effort, at most 800 output tokens, the structured verdict schema, no tools, fallbacks or retries, and a 30-second deadline. It prints only the status, returned model, token counts, elapsed time and whether the verdict validated. The request is billed to the key's account.

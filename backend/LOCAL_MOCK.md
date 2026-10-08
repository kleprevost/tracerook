# Local API Demo

The default server factory serves an ephemeral, loopback-only synthetic API. It does not instantiate the legacy analyzer or database, call Claude, meter real tokens, or grant native host permissions. The native service owns HTTP transport; UI receives no credentials. No backend deployment is part of this demonstration.

```sh
cd backend
/opt/homebrew/bin/python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/python -m uvicorn tracerook_backend.app:app_factory --factory --host 127.0.0.1 --port 8787 --no-access-log
```

Run checks with `.venv/bin/pytest -q`; the socket integration check requires port 8787 free and terminates only its own subprocess. The process must be bound exactly to loopback on port 8787. No `.env`, API key, account provisioning, paid infrastructure, or persistent database is needed.

All routes are under `/mock/v1/`, responses carry `schema_version:1`, `simulation:true`, `Cache-Control:no-store`, and `X-TraceRook-Request-ID`. GET healthz requires no credential and reports `provider_ready:false`.

- POST `alpha/enroll`: exactly `invitation_id:"local-demo"`, `consent:true`, `privacy_policy_version:2`. The invitation is a public development identifier. Returns `device_id`, `device_token`, `expires_at`; token is random and returned once, stored only as a SHA256 digest in process memory, expires after one hour.
- GET `capabilities` authenticated: `provider_ready:false`, `provider:"fixture"`, `transport:"local_mock"`, `model_id:"synthetic-v1"`, `privacy_policy_version:2`.
- GET `usage` authenticated: `fixture_evaluations`, `input_tokens:0`, `output_tokens:0`, `billed_units:0`.
- POST `device/rotate` / `device/revoke`: exactly `device_id` matching bearer principal. Rotation returns a fresh enrollment envelope and invalidates the old token; revoke returns `revoked:true`.
- POST `privacy/delete`: exactly matching `device_id` and `confirm:true`; clears that device's process metadata and receipts, revokes token, returns `deleted:true`.
- POST `analysis`: exact `LocalAPIDemoRequest` in `Packages/TraceRookCore/LocalAPIDemo.swift`, including mandatory `simulation:true`, allowlisted scenario, and exactly matching predefined synthetic context. Response is its separate `LocalAPIDemoResponse`, with fixture provenance and zero tokens/billing. No arbitrary host event, user text, command, repository content or model options are accepted.

Bearer credentials are checked on every authenticated route. Devices are isolated; rotation/revocation/delete require the caller's principal. Browser Origins, unexpected Host headers, non-loopback peers, query strings, unsupported methods, malformed UTF8, duplicate JSON keys at every depth, unknown keys, nonfinite numbers, and bodies over32KiB are rejected without echoing input. Native calls must send Content-Type exactly `application/json` for POST.

Same device/request ID plus identical canonical JSON returns the same receipt for120seconds; a changed payload conflicts. One process-wide fixture evaluation lock serializes concurrent evaluation and prevents double-counting retries. Successful fixture evaluations are capped at30 per device per UTC day. All metadata/counters/credentials reset when the process restarts; this is no durable quota or customer enrollment system. Enrollment has64device and replay cache1024receipt bounds. Explicit outage/quota/deadline scenarios return503/429/504 with canonical typed, simulated errors and no counter increment.

The legacy `/v1` backend remains separate and is not mounted by the default factory. Selecting `TRACEROOK_MODE=production` requires explicit production configuration, a real key pepper and Anthropic key, and the Anthropic analyzer. It remains the older flat protocol, not an implementation of hosted MVP3 enrollment/spend controls. Mock request fields are forbidden by its legacy strict schema. No production inference was exercised or deployed during this work. This backend provides advisory fixtures only; verified pre-execution protection is a native host responsibility.

## Separate opt-in Haiku diagnostic

`backend/scripts/probe_anthropic.py` is a developer diagnostic, independent of the default local API. Invoke `.venv/bin/python scripts/probe_anthropic.py` from `backend/` and enter the key at its hidden prompt, or supply exactly one key line through an ephemeral stdin pipe. Do not place the key in command arguments, environment variables, files, shell history or logs. The script accepts no arguments and writes no files. Python process memory is transient, but cannot promise cryptographic memory erasure.

The diagnostic performs one first-party HTTPS Models API lookup for `claude-haiku-5-5`; only an exact model match permits at most one Messages request with predefined synthetic benign context. That request may incur actual token cost. It uses low effort, at most800 output tokens, the existing structured verdict schema and validator, no tools/fallbacks/sampling overrides, no retries, no redirects or environment proxies, and a30second total deadline. Upstream bodies and verdict text are neither echoed nor saved. Output contains only safe status/code, validated returned model identifier, actual token counts when present, elapsed milliseconds and verdict validation boolean. Refusals/incomplete/schema-invalid/mismatched model responses fail safely without another request.

The user's authorized diagnostic succeeded on October8,2026 with `claude-haiku-5-5`: one validated verdict, 798 input tokens, 178 output tokens and3006ms elapsed. The native mock remains fixture-only. A subsequent user-directed change sets the separate legacy analyzer's default to Haiku5.5; this does not connect `/mock/v1` to Claude, deploy an API or establish native execution protection. References: [Haiku5.5 migration guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide), [Models retrieve API](https://platform.claude.com/docs/en/api/models/retrieve), [scoped native/API evidence](../docs/LOCAL_API_DEMO_EVIDENCE.md). SDK regression tests use fake upstream responses and make no real calls.

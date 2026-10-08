# TraceRook backend

Current development target: the **Local API Demo**, an ephemeral fixture backend bound to `127.0.0.1:8787`, connected through the native service. The default factory mounts only `/mock/v1/`. It constructs no Anthropic analyzer or account database and reports explicit synthetic provenance and zero actual tokens/billing. Its advisory receipts cannot grant native host permission. See [local mock contracts and run instructions](LOCAL_MOCK.md).

This repository also contains an older, separate `/v1` backend with API-key authentication, account/device records, SQLite usage metadata and a flat analysis protocol. It is implementation groundwork, not an operating hosted service, hosted MVP3 alpha, or commercial offering. Individual-plan price/quota values are planning placeholders; there is no billing/checkout or customer subscription system. No backend deployment was performed.

## Run the current local demonstration

```sh
cd backend
/opt/homebrew/bin/python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/pytest -q
.venv/bin/python -m uvicorn tracerook_backend.app:app_factory --factory --host 127.0.0.1 --port 8787 --no-access-log
```

Tests require no key or external requests. The actual socket integration test requires port8787 free and cleans up its own process. Keep the default `TRACEROOK_MODE=local_mock`; no `.env`, paid infrastructure or persistent data is needed. Mock credentials/counters/receipts disappear on restart. The fixture quota is30 successful evaluations per device per UTC day.

## Isolated live developer diagnostic

On **2026-10-08**, a separately authorized, one-shot developer probe verified first-party Anthropic model `claude-haiku-5-5` and received a schema-validated synthetic benign verdict: **798 input tokens,178 output tokens,3,006ms**. This proves that isolated request succeeded; it does not establish hosted service availability, native live Claude integration, hook coverage, or pre-execution protection. The probe is separate from the legacy SDK analyzer and local mock server.

The user explicitly selected Haiku5.5, overriding the MVP3 plan's Sonnet choice. The configured legacy analyzer now defaults to `claude-haiku-5-5`, low effort, structured verdict output, and text-block selection by type. Haiku receives no server fallback beta/parameter or removed sampling controls. Refusal, truncation, malformed output and model mismatch produce typed errors without a retry or fallback. Explicitly configured legacy Opus/Sonnet models retain their existing opt-in fallback support.

The [diagnostic instructions](LOCAL_MOCK.md#separate-opt-in-haiku-diagnostic) describe transient stdin/getpass credentials, at most one Messages call, bounded output and deadline, and safe status/token reporting. The diagnostic may incur actual token cost when explicitly invoked. Never put keys in command arguments, files or logs.

## Legacy backend reference

The following routes are mounted only when `TRACEROOK_MODE=production` is explicitly selected, alongside valid production settings, a strong `TRACEROOK_KEY_PEPPER`, and an Anthropic credential. The default mock factory does not mount them. This older protocol differs from MVP3's canonical `/v1/analysis` envelope and is not the native Local API Demo contract.

| Method/path | Purpose |
|---|---|
| GET `/healthz`, `/readyz` | Legacy process/database checks |
| GET `/v1/plans` | Planned product metadata |
| POST `/v1/device/registrations` | API-key-scoped device registration |
| GET `/v1/account` | Provisioned account metadata |
| GET `/v1/usage?month=YYYY-MM` | Monthly analysis/token metadata |
| POST `/v1/analyze` | Legacy flat redacted analysis request |
| POST `/v1/events` | Sanitized counters, acknowledged without storage; synthetic origin refused in production |

The legacy analyzer uses a fixed system prompt, JSON-encoded untrusted context, schema-constrained output and the bounded verdict validator. SDK retries are disabled and the client deadline is enforced. SQLite stores account/device/key and usage metadata; analyzed context is not persisted or logged. API keys are HMAC-digested with a server pepper. Critical local rules and host permissions remain native responsibilities.

Remaining hosted work includes canonical MVP3 enrollment/protocol, consent/preview integration, durable device-scoped idempotency, complete quotas/spend cutoffs, operational monitoring, credential lifecycle and deployment hardening. Legacy replay behavior does not bind retries to a payload digest; the local mock API does. Production account provisioning and planned pricing do not imply a launched product. No production integration or deployment should be inferred from the isolated probe.

References: [Haiku5.5 migration guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide), [first-party Models API](https://platform.claude.com/docs/en/api/models/retrieve).

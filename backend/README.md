# TraceRook local API

A FastAPI server for development. By default it serves the **Local API** used by the in-app Local API demo: a loopback-only, fixture-backed implementation of TraceRook Cloud's enrollment, capability, usage, credential and analysis flows under `/mock/v1/`. Production Cloud is the Cloudflare Worker in [`cloud/`](../cloud/README.md).

```sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/pytest -q
.venv/bin/python -m uvicorn tracerook_backend.app:app_factory --factory --host 127.0.0.1 --port 8787 --no-access-log
```

Tests need no key and make no external requests; the socket integration test needs port 8787 free. No `.env`, account provisioning or persistent data is required. Routes and request shapes are documented in [LOCAL_MOCK.md](LOCAL_MOCK.md).

## Haiku diagnostic

`scripts/probe_anthropic.py` checks an Anthropic key end to end: one Models API lookup for `claude-haiku-5-5`, then at most one Messages request with fixed benign context, validated against the verdict schema. It reads the key from a hidden prompt or a single stdin line and prints only status, model, token counts and elapsed time. See [LOCAL_MOCK.md](LOCAL_MOCK.md#haiku-diagnostic).

## Reference `/v1` server

With `TRACEROOK_MODE=production`, a strong `TRACEROOK_KEY_PEPPER` and an Anthropic key, the factory instead mounts a self-hosted `/v1` API with API-key accounts, device registration, monthly usage metadata and Claude analysis:

| Method and path | Purpose |
| --- | --- |
| `GET /healthz`, `/readyz` | Process and database checks |
| `GET /v1/plans` | Plan metadata |
| `POST /v1/device/registrations` | Device registration |
| `GET /v1/account` | Account metadata |
| `GET /v1/usage?month=YYYY-MM` | Monthly analysis and token usage |
| `POST /v1/analyze` | Redacted analysis request |
| `POST /v1/events` | Sanitized counters, acknowledged without storage |

The analyzer uses a fixed system prompt, JSON-encoded untrusted context, schema-constrained output and a strict verdict validator, with `claude-haiku-5-5` at low effort by default. API keys are stored as HMAC digests; analyzed context is never persisted or logged. Accounts are managed with `tracerook-admin`.

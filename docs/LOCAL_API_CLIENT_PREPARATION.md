# Local API client preparation — 2026-10-08

**Historical preparation milestone.** The backend and native HTTP connection have since been implemented and demonstrated. Current results and run instructions are in [connected local API evidence](LOCAL_API_DEMO_EVIDENCE.md); the text below records the earlier preparation, not current availability.

The user assigned the mock backend to a separate agent on `claude/zealous-einstein-nxxnwd`. Current client work is on `codex/mvp2-live-beta`. The backend branch was not present in the local checkout when this preparation was validated. Its contract must be reviewed before connection is enabled.

## Implemented and demonstrated

- Settings → **Local API Demo** previews six fixed synthetic scenarios. It says not connected, backend integration pending, and no Claude call. The disabled Connect button does not fake connectivity.
- Separate mock request/response types require `simulation: true`. They do not conform to the live `AnalysisProvider` protocol or map into hooks, approvals, incidents, or protection status.
- Requests reject arbitrary sample substitutions and extra fields. Responses reject false Anthropic/Cloud provenance, token/billing claims, critical severity, permission fields, unsafe/unbounded text, wrong request IDs, stale/future timestamps, and responses exceeding the request's budget.
- Unframed HTTP JSON reuses the existing strict IPC payload scanner. Duplicate decoded keys, unknown nested fields, invalid UTF-8, and bodies over 32 KiB are rejected without weakening existing framed IPC checks.
- The website source adds a local API development guide and distinguishes planned company-owned TraceRook Cloud analysis from the separate direct BYOK path. Both remain unavailable for real Claude inference.

Local validation: **60 Swift test functions pass**, including a 50-case deterministic shell corpus and six parameterized mock scenarios; **22 native light/dark render cases** pass. The static site has 25 HTML pages, 22 searchable guides, and 1,384 checked local links/assets/anchors. Representative native and browser previews were visually reviewed. These counts describe this development checkout, not hosted-alpha acceptance or security efficacy.

Ignored artifacts: `build/mvp2-live/api-contract-tests.log`, `ui-api-preview.log`, `local-api-docs-preview.png`, and `build/ui-smoke/*-local-api-pending.png`.

## Still required

No native HTTP connection, device enrollment, mock token storage, or backend process is implemented by this client preparation. No backend is deployed. The offline Cloud Demo continues making zero analysis network requests. No real host integration, Claude inference, or protected badge has been added.

After backend completion: review its actual protocol and tests, reconcile the [provisional handoff](LOCAL_MOCK_API_HANDOFF.md), add service-owned loopback transport and authenticated UI control DTOs, then run real local HTTP and native end-to-end tests. Mock credentials must stay transient, requests must remain fixture-only, and the real history/approval channel must remain isolated. An injected fake transport or a process health check is insufficient evidence of that milestone.

Production MVP3 still requires server-owned Anthropic integration, consent and privacy preflight for real events, scoped Keychain credentials, operational quotas/retention, hosted infrastructure, and independent local host enforcement evidence. The user's local-only mock direction changes the immediate demonstration scope; it does not waive those requirements or establish a proprietary Claude backend.

# Local mock backend — proposed shared contract

Status: **provisional contract; native request preview and response validators are prepared. The server and native HTTP connection are not integrated yet.** The user assigned the backend to a separate agent on `claude/zealous-einstein-nxxnwd`; reconcile that branch's actual protocol before wiring transport. See [client preparation evidence](LOCAL_API_CLIENT_PREPARATION.md).

The user clarified that the immediate target is a locally running mock backend connected to the native client. This is an explicitly simulated development demonstration, not the hosted Claude alpha described in the [MVP3 specification](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md). It does not establish working Claude inference, customer enrollment, or verified host enforcement.

## Ownership

- Backend work: `cloud/local-mock/`, its tests, and its run instructions.
- Client work: additive Swift contracts, service-owned HTTP transport, authenticated UI control calls, and native presentation.
- Website work: truthful documentation distinguishing the offline Cloud Demo, this local API demonstration, and future Claude integration.

Do not change the existing offline Cloud Demo provider or route mock verdicts through live hook decisions, approvals, incidents, or protection status.

## Transport and authentication

Bind only to `127.0.0.1:8787`. Use `/mock/v1/` so synthetic requests cannot be confused with future production `/v1/analysis`. Do not expose production routes or make external requests. Reject browser `Origin` headers, unexpected `Host` headers, query strings, and unsupported methods. Responses use UTF-8 JSON and `Cache-Control: no-store`; no CORS allowance.

The service, not the SwiftUI process, owns all HTTP calls. The native app invokes the service over its existing authenticated XPC channel. Mock device credentials remain in service memory and disappear on restart; do not use preferences, logs, source files, or the live credential namespace. An explicitly public development invitation identifier may be used for local setup, but it must never be represented as a production invitation secret.

Issue random high-entropy device tokens. Store only token digests in backend memory, bind tokens to a device UUID, and actually check authentication, expiry, rotation, and revocation. Return tokens only from enrollment and rotation. No credential fields in UI status replies.

## Routes

| Method | Path | Behavior |
|---|---|---|
| GET | `/mock/v1/healthz` | Process health; `simulation: true`, `provider_ready: false` |
| POST | `/mock/v1/alpha/enroll` | Enroll an ephemeral mock device; return its token once |
| GET | `/mock/v1/capabilities` | Authenticated mock capabilities; Claude readiness remains false |
| POST | `/mock/v1/analysis` | Authenticated, bounded synthetic evaluation; no inference |
| GET | `/mock/v1/usage` | Authenticated fixture evaluation count; actual tokens and billing are zero |
| POST | `/mock/v1/device/rotate` | Atomically replace this device's token and invalidate the old one |
| POST | `/mock/v1/device/revoke` | Revoke this device |
| POST | `/mock/v1/privacy/delete` | Require explicit confirmation; clear the device's mock metadata and revoke it |

Use the MVP3 canonical request/context shape and bounds, with two mandatory additional fields: `simulation: true` and an allowlisted `scenario`. Only client-generated, predefined synthetic examples are accepted. Scenario contexts must match the shared fixtures exactly; no arbitrary action text, paths, transcripts, repository data, API keys, or host payloads. Allowed scenarios: `benign`, `credential_transfer`, `task_drift`, `provider_unavailable`, `quota_exhausted`, `deadline_exceeded`.

The prepared client uses `source: claude_code`, `event: pre_tool_use`, privacy policy version 2, and a 1,000–4,000 ms budget (default 3,000 ms) inside the existing five-second XPC call budget. This is a narrower mock subset of the hosted specification's 12,000 ms maximum. Context fixtures are defined in `Packages/TraceRookCore/LocalAPIDemo.swift`; preview UUIDs are placeholders until enrollment. Timestamps accept canonical UTC seconds or three fractional digits. Freeze the approved request bytes before sending and generate a fresh request ID for a changed scenario.

Responses follow the MVP3 analysis envelope, but require `simulation: true` and the following provenance:

```json
{
  "provider": "fixture",
  "transport": "local_mock",
  "model_id": "synthetic-v1",
  "policy_version": 1,
  "prompt_version": "mock-risk-eval-v1",
  "trace_id": "tr_<UUID>",
  "validated_at": "<UTC timestamp>"
}
```

`input_tokens`, `output_tokens`, and `billed_units` are always zero. Mock error envelopes also contain `simulation: true`; use the specification's typed error codes and HTTP statuses. Do not echo input in errors. This envelope must have a distinct Swift type and must never be accepted as an Anthropic or live Cloud response. Recommendations remain advisory and have no path to granting host permission.

Reject unknown and duplicate JSON keys at every depth, invalid UTF-8, bodies over 32 KiB, stale schema versions, invalid IDs, mismatched device principals, unsupported enums, and out-of-bound fields. Preserve the service's bounded deadline and cancellation; no automatic analysis retries. Same device/request ID with the same canonical payload returns the same short-lived analysis receipt; a changed body returns `409 conflict`. Do not cache approvals or hook decisions.

## Required demonstration and tests

Demonstrate native client → authenticated XPC → service → local HTTP server → validated synthetic verdict → native UI. Display **Local API Demo · synthetic · no Claude call** and keep live host session counts and protection status unchanged. Show the exact outgoing synthetic request before the user runs a scenario.

Backend tests cover auth failure, wrong-device access, expiry/rotation/revocation, malformed and duplicate JSON, size bounds, browser/DNS rebinding defenses, idempotency conflicts, concurrent duplicates, typed outage/quota/deadline scenarios, zero billing, and explicit mock provenance. Client tests cover response/request binding, strict nested fields, provenance rejection, deadline/cancellation, fixture-only egress, and absence of any live permission or history mutation. Include a real local HTTP integration test rather than relying entirely on an injected fake transport.

This local-only implementation introduces no Cloudflare resources or costs. Publishing the static website does not deploy this backend. Document each implemented subset and remaining hosted-alpha requirement accurately.

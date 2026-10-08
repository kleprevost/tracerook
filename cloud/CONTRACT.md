# TraceRook Cloud v1 contract

Native base URL: `https://api.tracerook.dev`. All endpoints below use `/v1` (including health). TLS required; no query parameters or browser Origins. Private responses: `Cache-Control: no-store`, `X-TraceRook-Request-ID` server trace UUID. JSON UTF-8, exact keys, no duplicate keys, maximum 32768 bytes. Schema version is integer 1; privacy policy version is integer 2. Bearer token is opaque and must live in Keychain.

* `GET /v1/healthz` → `{schema_version:1,status:"ok"}`. Process health only.
* `POST /v1/alpha/enroll` body `{schema_version:1,invitation:string,device_id:UUID,app_version:string,privacy_policy_version:2}` → `{schema_version:1,device_id:UUID,device_token:string,token_expires_at:ISO8601,limits:{evaluations_per_day:null,input_tokens_per_day:null,output_tokens_per_day:null,devices_per_account:3}}`.
* `GET /v1/capabilities` (bearer) → `{schema_version:1,provider:"anthropic",transport:"tracerook_cloud",model_id:"claude-haiku-5-5",analysis_enabled:boolean,privacy_policy_version:2,retention:{receipt_days:30,usage_days:90,verdict_cache_seconds:600},limits:{...same limits...}}`. Enabled means configured, never proves a successful Claude call.
* `GET /v1/usage` (bearer) → `{schema_version:1,date_utc:"YYYY-MM-DD",evaluations_today:integer,input_tokens:integer,output_tokens:integer,reserved_input_tokens:integer,reserved_output_tokens:integer,limits:{...same limits...}}`. Reservations include ambiguous provider outcomes conservatively; actual usage only counts validated returned usage.
* `POST /v1/device/rotate` (bearer), body `{schema_version:1,device_id:UUID}` → same enrollment response. Previous token invalid immediately.
* `POST /v1/device/revoke` (bearer), body `{schema_version:1,device_id:UUID}` → `{schema_version:1,revoked:true}`.
* `POST /v1/privacy/delete` (bearer), body `{schema_version:1,device_id:UUID,confirm:true}` → `{schema_version:1,deleted:true}`. Deletes the authenticated account's metadata and all devices. Aggregate global cost remains without account identifiers.

## Analysis

`POST /v1/analysis` (bearer):

```json
{"schema_version":1,"request_id":"UUID","device_id":"UUID","session_pseudonym":"UUID","source":"claude_code","event":"pre_tool_use","deadline_ms":9000,"privacy_policy_version":2,"context":{"task_summary":"Implement a checkout button","action_class":"shell_exec","proposed_action_summary":"Run project tests","local_signals":[],"recent_activity":[],"contains_code_excerpts":false}}
```

`source`: `claude_code|codex`; `event`: `pre_tool_use`; `action_class`: `shell_exec|file_read|file_write|network|other`. Task ≤512 codepoints/1024 bytes; action ≤1024/2048 bytes. Recent entries ≤6, each ≤160 codepoints/512 bytes. Signals ≤12 unique values: `sensitive_config_read`, `outbound_transfer`, `task_mismatch`, `reads_credential_store`, `outbound_post`, `writes_repo_config`, `destructive_delete`, `remote_endpoint_unfamiliar`, `prompt_injection`, `privilege_change`, `untrusted_instructions`, `session_drift`. Deadline integer 1000–12000. Code excerpts must be false. No simulation, scenario, raw command, path, code or model fields. Client must refuse demo origins before constructing this DTO.

200 response:

```json
{"schema_version":1,"request_id":"UUID","analysis_id":"an_UUID","verdict":{"schema_version":1,"category":["unsafe_action"],"severity":"low","confidence":0.5,"suspicious":false,"rationale":"Advisory rationale","evidence":[],"recommended_action":"allow","session_drift":false,"limitations":[]},"provenance":{"provider":"anthropic","transport":"tracerook_cloud","model_id":"claude-haiku-5-5","policy_version":1,"prompt_version":"risk-eval-v1","trace_id":"tr_UUID","validated_at":"ISO8601"},"usage":{"input_tokens":100,"output_tokens":100,"billed_units":1},"server_elapsed_ms":100}
```

These values are illustrative. Actual successful output requires first-party Anthropic model match, request-id, end_turn and bounded validated usage/verdict. Category has 1–2 unique values `unsafe_action|agent_misbehavior`; severity `critical|high|medium|low|unknown`; confidence 0–1; recommendation `allow|warn_allow|request_approval`; rationale ≤2048 bytes, evidence/limitations ≤10 entries each ≤512 bytes. Advice never grants host permissions.

Same device/request UUID and canonical body returns cached verdict for ≤600 seconds. Changed body → 409 `conflict`; concurrent or expired/ambiguous replay → 409 `in_progress` or `replay_unavailable`. Failed requests are never re-billed by replay. No automatic provider retries.

## Errors

`{schema_version:1,error:{code:string,message:string,retryable:boolean},trace_id:"tr_UUID"}`. Messages contain no submitted data. Codes: `invalid_request` 400, `invalid_invite` 403, `unauthorized` 401, `revoked` 403, `consent_required` 403, `conflict|in_progress|replay_unavailable` 409, `upgrade_required` 426, `rate_limited|quota_exhausted` 429, `provider_unavailable` 503, `deadline_exceeded` 504. Oversize is 413 `invalid_request`; privacy rejection is 400 `invalid_request`. Retry-After only advises later requests, never a retry beyond host deadline.

Kill switch starts disabled and global monthly cap defaults to null (no cutoff), per the founder’s explicit instruction on 2026-10-08. Enrollment/health can work while inference is disabled. No fixture output is returned as real provenance.

Quota fields evaluations_per_day, input_tokens_per_day and output_tokens_per_day are integer or null. Null means no customer quota. Default deployment has no customer quota and no company spend cutoff per founder instruction (2026-10-08); optional numerical limits remain supported for operator testing/configuration. Rate limits, two concurrent evaluations per device and three devices per account still apply. Analysis remains disabled until explicitly enabled and pricing and secrets are configured.

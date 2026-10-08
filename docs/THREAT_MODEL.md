# Threat model

| Boundary | Untrusted input | Enforcement |
| --- | --- | --- |
| Agent → hook bridge | Hook JSON, commands, paths, tool output | Input caps, strict nested decoding, canonical original action, no trust in agent-controlled content |
| Hook bridge → service | Any same-user process can connect | Socket directory `0700`, socket `0600`, kernel peer credentials, fixed method set with no approval or trust mutations |
| App → service | A same-user process attempting an approval | Code-signing requirements on XPC, method authorization, exact binding and nonce, single-use pending state |
| Service → TraceRook Cloud | Secrets in session context | Category projection, local preflight, server preflight that rejects rather than repairs |
| Claude → policy | Prompt injection, malformed or late output | Fixed system prompt, strict schema and model/provenance checks, advisory-only verdicts |
| Internet → TraceRook Cloud | Credential guessing, replay, oversized or malformed requests | Keyed-digest tokens, device-scoped idempotency, strict UTF-8 JSON, size and deadline limits, per-device and per-IP rate limits |

Agent arguments, repository instructions, tool responses and model findings are always treated as data. Critical denials require local evidence; model text can neither grant permissions nor execute instructions.

Review binding covers provider, session, turn, tool-call ID, tool name, working directory and a digest of the original, unmodified action, plus a per-invocation nonce. Terminal reviews cannot be reused, reviews past their deadline deny, and a service restart never restores a pending review as approved.

Coverage for each agent and tool class is recorded from the hook configuration, the signed helper, the host version and a recent successful pre-execution test.

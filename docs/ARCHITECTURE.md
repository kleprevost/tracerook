# TraceRook architecture

```text
Claude Code ── PreToolUse hook (stdin JSON / stdout decision) ──▶ tracerook-hook
                                                                     │  IPC v2, private Unix socket
                                                                     ▼
                                                     TraceRookAgent (per-user service)
                                                  local rules · reviews · SQLite history
                                                      │                         │
                                         authenticated XPC              HTTPS, device token
                                                      ▼                         ▼
                                              TraceRook.app        TraceRook Cloud ──▶ Anthropic Claude
                                  dashboard, menu bar, notifications   (api.tracerook.dev)
```

## Processes

- **`tracerook-hook`** runs once per hook invocation. It reads bounded stdin, normalizes the host payload, applies the shared emergency rules, asks the service for a decision within the hook deadline, and writes host-format output.
- **`TraceRookAgent`** is the per-user LaunchAgent and the sole writer of private SQLite history. It evaluates local policy, owns pending reviews and their deadlines, and calls TraceRook Cloud for contextual analysis.
- **`TraceRook.app`** is the SwiftUI dashboard and menu bar companion. It reads state and resolves reviews over XPC, delivers actionable notifications and opens the native review window.
- **TraceRook Cloud** (`cloud/`) is a Cloudflare Worker. D1 holds invitation, account and device digests plus metadata-only receipts; a SQLite Durable Object holds usage accounting and device-scoped idempotency. It calls Anthropic's Messages API with TraceRook's key. See [cloud/CONTRACT.md](../cloud/CONTRACT.md).
- **Local API** (`backend/`) is a loopback FastAPI server with the same enrollment and analysis shapes, backed by fixtures, for development and the in-app Local API demo.

## Swift modules

| Module | Responsibility |
| --- | --- |
| `TraceRookContracts` | Event envelopes, bounded JSON, IPC v2 framing, replies, budgets, coverage records, typed errors |
| `TraceRookPrivacy` | Redaction, remote-payload preflight and status-code-only logging |
| `TraceRookAgentAdapters` | Claude Code and Codex normalization, denial encoding, canonical SHA-256 action binding |
| `TraceRookRules` | Deterministic policy rules shared by the service and hook bridge |
| `TraceRookCore` | Domain records, exact review transitions, analysis providers, Cloud and service DTOs |
| `TraceRookFixtures` | Bundled sample data for demo mode |

Service state lives in actors and UI state on the MainActor, under Swift 6 strict concurrency. The Mac app has no third-party runtime dependencies.

## Transports

- **Hook socket.** Four-byte big-endian length prefix, one JSON packet, 1 MiB request and 16 KiB reply caps, duplicate-key rejection, Decimal-preserving numbers and a system-random 128-bit invocation nonce. Replies are `no_override` or `deny`. The socket carries events and decisions only.
- **XPC.** Code-signing requirements on both sides. Carries status snapshots, Cloud controls and exact review resolutions.
- **Cloud.** HTTPS to `api.tracerook.dev/v1` with an opaque bearer device token, strict JSON and a 32 KiB body limit.

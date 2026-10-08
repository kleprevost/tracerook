# MVP2.1 — local service evidence

Branch: `codex/mvp2-live-beta`, based on public `e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7` and the preserved MVP3 audit. The user requested shipping MVP2 before MVP3 and accepted a non-notarized distribution. This supersedes the earlier PR-1-only scope; host protection remains unverified.

## Implemented

- Per-user service owns migrated SQLite/WAL and an exclusive writer lock. Directory `0700`; DB/WAL/SHM/lock/socket `0600`. Unsafe final symlinks, hardlinks and owners are rejected. Prepared statements bind data; v1 readers remain. There was no previous database.
- Bounded v2 XPC DTOs with macOS signing requirements on both peers and a UID admission check. Authenticated observers receive change signals; snapshots and reconnect recover UI state. The app never opens the DB.
- Private hook socket uses kernel UID and audit token, then Security.framework running-code validation. Only hook envelopes are accepted; maximum 32 connections, three-second frame reads and disconnect cancellation. No approval/configuration mutation route.
- Service-owned review binds request/approval/incident, original action digest and fresh nonce. Monotonic deadlines, durable CAS and terminal reservation prevent concurrent/replayed grants. Restart aborts pending reviews; Clear History cancels unconsumed authority first.
- Sanitized bounded snapshots; simulated ingestion is labeled and excluded from actual host-session counts. Cloud Demo cannot resolve live reviews.

The operational hook stays disabled here. A conservative policy-unavailable transport reply is not detection or host-denial evidence.

## Observed on macOS 27.0 / Swift 6.4 / arm64

| Check | Result |
|---|---|
| Automated tests | 50 pass: 43 retained plus store, privacy, retention, restart, CAS, replay and concurrency tests |
| Native regression | 20 light/dark renders with valid dimensions; representative views reviewed |
| Packaged app → service | Authenticated snapshot and simulated ingestion pass; state survives restart |
| Altered XPC app | Valid re-signed copy with changed Info.plist/code hash rejected |
| Packaged CLI ↔ service | Actual bidirectional kernel-audit-backed signature validation passes |
| Hook socket control DTO | Clear-history request rejected; original CLI exchange still succeeds |
| Altered CLI | Valid re-sign with different signing flags/code hash receives no reply; original CLI succeeds |
| Developer ID / wrong-team chain | Not run: no Developer ID identity; local signature checks are not this proof |
| Real host deny / actual BYOK | Not run in this milestone; later gates remain |

Ignored private outputs: `build/mvp2-live/`. No host coverage is inferred from these synthetic transport tests.

## Required deviations

1. **Non-notarized distribution** explicitly authorized by the user. The build script marks ad-hoc builds `TraceRookSecurityMode=local-adhoc`; no automatic production fallback. Exact signatures authenticate peers of the installed family, not publisher authenticity. Replacement of the whole ad-hoc bundle remains outside that trust boundary. Developer ID builds retain Apple anchor, Developer ID certificate OIDs, identity and team requirements. Gatekeeper acceptance and certificate-chain tests remain unverified.
2. **Service registration:** actual `SMAppService` registration succeeded, but macOS 27 rejected helper launch with `OS_REASON_CODESIGNING / Launch Constraint Violation`, `c[5]p[1]m[1]e[0]`. A conventional per-user LaunchAgent started the same helper and passed IPC tests. Local builds offer an exact plist before/after preview and consented LaunchAgent installation; Developer ID builds retain `SMAppService`. No launch constraint is disabled. macOS 26 behavior needs validation.
3. **SQLite path alias:** Foundation normalizes the temporary path back to `/var`, while SQLite NOFOLLOW rejects that system alias. POSIX `realpath()` supplies `/private/var` after private-directory validation. Final symlinks remain rejected.

The UI continues to show Not integrated. This milestone is not a shipping MVP2 protection claim.

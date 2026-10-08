# MVP2 PR 2 implementation plan

This is the concrete next scope after [PR 1 acceptance](MVP2_ACCEPTANCE.md): service, authenticated IPC, SQLite and honest real UI state. It is a plan, not evidence that these pieces exist. Live agent configuration, host canaries and BYOK remain later gates.

## Exact source changes

| File | Classes / changes |
|---|---|
| `Agent/main.swift` | Replace operational exit only after wiring `AgentRuntime`; start migration, single-writer actor graph, XPC and hook listener; preserve read-only version/self-tests |
| **New** `Agent/AgentRuntime.swift` | `AgentRuntime`: owned lifecycle, startup failure reporting, shutdown/cancellation, monotonic request deadlines |
| **New** `Agent/IPC/UIControlService.swift` | `UIControlService`, listener delegate, versioned read/subscribe methods and authorized mutation dispatch; accept bounded encoded DTO Data rather than arbitrary object graphs |
| **New** `Agent/IPC/PeerVerifier.swift` | `PeerVerifier`: production designated requirements for app, service and CLI; system-backed peer validation; typed safe failure; separate developer configuration that cannot count as production trust |
| **New** `Agent/IPC/HookSocketServer.swift` | `HookSocketServer`: private socket, kernel peer credentials, frame/read limits, fixed hook-only method set, bounded concurrent requests/waits, disconnect cleanup |
| **New** `Packages/TraceRookCore/Service/{EventBroker,ApprovalCoordinator,IntegrationHealthMonitor}.swift` | Service-owned actors: sanitized ingestion; request/nonce dedupe; pending review CAS/expiry; class/version/signature-keyed evidence. No placeholder verified coverage |
| **New** `Packages/TraceRookCore/Persistence/{SessionStore,SchemaMigrations}.swift` | SQLite sole writer, prepared statements/WAL/foreign keys, bounded sanitized rows, retention, migration transactions and recovery. Persist no `HookEnvelopeV2` or raw payload |
| `Packages/TraceRookContracts/{Contracts,LiveIPC,WireCodec}.swift`; **new** `ServiceContracts.swift` | Retain v1; bounded paginated snapshots/control errors; frozen v2 transport validation; explicit hook-only decoder dispatch |
| `Packages/TraceRookCore/{Models,ReviewContracts,DesktopModel}.swift` | Reuse records/bindings; add service snapshot application and connection state; retain demo collections; production resolution only through authenticated service |
| **New** `App/Services/AgentConnection.swift` | `AgentConnection`: bidirectional signature requirement, reconnect/backoff, version negotiation, cancellation/backpressure; no writable UI DB |
| `App/ViewModels/AppEnvironment.swift`; `App/TraceRookApp.swift` | Subscribe native UI/menu bar to actual service state; show unavailable/not integrated for failure; retain demo path |
| `App/Navigation/{Overview,Sessions,Incidents,Approvals,Integrations,Settings}View.swift` | Consume sanitized snapshots and actual status, empty/reconnecting states; keep inactive integration controls until later gates |
| `App/Notifications/NotificationController.swift` | Reserve separate live notification routing; opaque IDs only; notification is an authenticated mutation request, never authority. Full live review actions arrive with PR 5 |
| `Resources/com.tracerook.agent.plist`; **new** `App/Services/ServiceRegistration.swift` | `ServiceRegistration`: consented supported per-user registration, stable bundled executable path, safe removal; GUI termination does not unregister service |
| `Package.swift`; `TraceRook.xcodeproj`; `scripts/build.sh`; `scripts/test.sh`; `scripts/update-xcode-sources.py` | System SQLite3 bridge if required, new files/targets, explicit developer signing test mode; production requirements are never downgraded for CLT |
| **New** `Tests/{IPC,Persistence,Service}Tests/`; existing UI/Core tests | Negative callers, protocol/route limits, races, restart, migrations, sanitized snapshots, real/demo isolation |

## Authentication design to validate

The installed SDK's `Foundation/NSXPCConnection.h` declares `NSXPCListener.setConnectionCodeSigningRequirement(_:)` and `NSXPCConnection.setCodeSigningRequirement(_:)`, both available since macOS 13. The listener API rejects mismatching connections before its delegate, and the connection requirement validates new messages. Use the supported system peer checks rather than private audit-token access or a PID-to-path guess. A malformed requirement is a programmer error; construct and validate requirements before activation. [Apple API](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)).

PR 2 must prove actual bidirectional requirements against signed processes, exact allowed bundle identities and Developer ID team/anchor, including unsigned, wrong-team, altered and forged-ID failures. Kernel peer validation is distinct from method authorization: verify live origin, exact IDs/binding/nonce, pending state and monotonic expiry for every mutation. No user-provided bundle ID, path, UID or DTO boolean proves identity. The current host has no signing identities; production signed-family acceptance remains blocked until a real signing environment is available. A separate test/developer mode cannot silently become the production fallback.

For the Unix socket, the current SDK exposes `getpeereid`, `LOCAL_PEERPID` and `LOCAL_PEERTOKEN`. Validate their actual runtime behavior and use audit-backed code identity where supported. The directory is `0700`, socket `0600`; reject unsafe ownership/symlinks, fixed-route mutation attempts, incomplete frames, excessive waits and duplicate/conflicting UUIDs. This channel never resolves reviews or changes keys, policy or integration trust. Same-user malicious host/config interference remains outside a hook's guarantee.

## Storage and cancellation

The baseline has no SQLite database or migration history. Create a transactionally migrated first schema; preserve schema-v1 record readers and test old sanitized records rather than pretending a prior DB exists. Translate the spec's illustrative `origin='real'` into the existing `DataOrigin.live` raw value with a checked constraint. Demo records stay out of live storage and live approval lookup. Keep pending binding nonce and CAS generation in service-owned state; after restart persisted pending reviews expire/abort unless the original wait can be safely proven active. Never deserialize an approval into permission.

Derive local deadlines from `ContinuousClock`; epoch milliseconds are bounded transport/display metadata, not wall-clock authority. Reserve output time, cancel on disconnect/logout, and reject late model/UI results. A lost service cannot turn into a grant. The operating CLI stays disabled until shared emergency rules and host-specific output are ready in PR 3.

## Next hook-integration changes (PR 3 / PR 4)

These are listed now to make the source dependencies explicit; they are not part of PR 2:

- `HookCLI/main.swift` plus new `HookCLI/{Bridge,EmergencyPolicy,HostOutput}.swift`: strict bounded stdin, canonical original action plus nonce, validated v2 request/reply, monotonic wait, emergency rule parity, empty stdout for no override and host-tested deny output.
- `Packages/TraceRookAgentAdapters/Adapters.swift` plus `ConfigurationTransaction.swift`, `ClaudeCodeIntegration.swift`, `CodexIntegration.swift`: executable/version detection, actual capability map, preview/source hash/atomic restrictive write, owned-entry merge/rollback/repair/uninstall, no trust bypass.
- `Packages/TraceRookRules/`: actual rules and concrete evidence/negative corpus. Existing `RuleEvidence` is only a contract. Share enabled emergency rules with CLI before installation can be offered.
- `Packages/TraceRookPrivacy/Redactor.swift`: sanitize before every new DB/UI/API boundary; keep original action only in transient decision memory. Strengthen preflight using adversarial tests if new payload shapes require it.
- Host fixture resources and adapter tests: tool-specific decoding rather than one generic object assumption; include Bash, Claude Write/Edit and Codex apply_patch, missing IDs/subagent fields/MCP arguments, duplicate keys and lossless original fingerprints.
- `App/Navigation/IntegrationsView.swift`: real diff/consent, Codex trust instructions, benign deny results, last tested exact version/tool class; never infer trust from successful file installation.

## PR 2 acceptance demonstration

1. With consent, start the service using the supported registration path; show empty real native state and no installed agent hooks.
2. A properly signed development UI reads a bounded snapshot. Show wrong/unsigned caller rejection separately; production identity-chain proof uses actual release signing.
3. Use a sanitized in-memory integration-test event through the service data plane, expressly labeled **simulated ingestion**, and show the resulting live-origin DB record/UI entry. It is not a real-host callback or protected coverage.
4. A hook-socket approval mutation fails; a disconnected/restarted service cannot resolve or restore a pending review as approved.
5. Restart/migrate, verify transaction and retention behavior, and inspect DB/log/export for absence of sentinel raw secrets, commands and transcripts.
6. Rerun native/demo regression checks. Keep the compatibility matrix unverified until PR 3/4 real-host canaries pass.

Actual live-host tests need the later authorized config/trust changes. No README/site/release claim changes belong to this phase.

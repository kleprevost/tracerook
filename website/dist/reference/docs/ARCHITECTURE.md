# TraceRook architecture

The macOS 26+ arm64 app, per-user LaunchAgent and hook CLI share Swift 6 modules in the root Swift package. The Xcode project consumes these as local package libraries. Strict concurrency is enforced by Swift 6; mutable service state uses actors and UI state uses MainActor.

- **TraceRookContracts**: normalized sanitized event envelope, bounded Codable JSON, adapter and IPC contracts, version constants, coverage facts and typed errors.
- **TraceRookPrivacy**: redaction, remote preflight and structured status-only logging.
- **TraceRookAgentAdapters**: host normalization and denial encoding, canonical SHA-256 action binding. Original actions live only in process memory.
- **TraceRookRules**: deterministic policy evidence; shared service/CLI emergency rules will be added before live enforcement.
- **TraceRookCore**: domain records, exact approval transitions, analysis and Cloud protocols.
- **TraceRookFixtures**: bundled, explicitly synthetic Cloud Demo. Its client rejects live-origin analysis. No networking dependency exists in this module.

The service is the sole writer of private sanitized SQLite history. The authenticated hook socket carries events and decisions only, with no approval/trust commands. Authenticated XPC carries UI status and exact review mutations. Notifications are an affordance; deadlines and pending state belong to the service.

No third-party runtime dependencies, broad disk access, root daemon, cloud backend, embedded web UI or live-agent configuration changes are introduced by the foundation build.

## MVP2 baseline contracts

The [MVP2 specification](../TraceRook_MVP2_Architecture_Implementation_Spec.md) extends this architecture. PR 1 adds live IPC v2 alongside the unchanged v1 event/fixture formats. `LiveIPC.swift` and `WireCodec.swift` define strict framing, invocation nonces, budgets, typed no-override/deny replies, provider status and per-class integration evidence. These tested contracts are now used by the implemented local socket and XPC service. The ordinary hook CLI remains disabled until real-host acceptance passes.

`ReviewRequest` and `ReviewResolution` live in Core's `ReviewContracts.swift` so they can reuse `ApprovalBinding` without a dependency cycle or duplicated domain type. Shape/binding validation is not caller authentication or approval consumption. The service actor and signed UI control plane now implement caller authentication, durable review transitions and exact one-time consumption. Hook wiring and actual native host review remain pending.

See the [acceptance matrix](MVP2_ACCEPTANCE.md) for the actual source inventory, limits and open gates, and the [PR 2 plan](MVP2_PR2_PLAN.md) for exact service/persistence/UI changes. Existing Cloud Demo remains isolated and real coverage remains Not integrated.

## Isolated local API demonstration

The developer-only service client owns loopback HTTP transport and transient `mock_` credentials. SwiftUI sends separate allowlisted controls over authenticated XPC; fixed synthetic requests and validated fixture receipts never enter the live analysis provider or review/history paths. Enrollment, usage, rotation, revocation, deletion, deadlines and cancellation are implemented. See [current evidence](LOCAL_API_DEMO_EVIDENCE.md). The Python/FastAPI default factory mounts only `/mock/v1`; hosted production Cloud and native real Anthropic analysis remain unavailable.

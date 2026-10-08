# TraceRook architecture

The macOS 26+ arm64 app, per-user LaunchAgent and hook CLI share Swift 6 modules in the root Swift package. The Xcode project consumes these as local package libraries. Strict concurrency is enforced by Swift 6; mutable service state will use actors and UI state uses MainActor.

- **TraceRookContracts**: normalized sanitized event envelope, bounded Codable JSON, adapter and IPC contracts, version constants, coverage facts and typed errors.
- **TraceRookPrivacy**: redaction, remote preflight and structured status-only logging.
- **TraceRookAgentAdapters**: host normalization and denial encoding, canonical SHA-256 action binding. Original actions live only in process memory.
- **TraceRookRules**: deterministic policy evidence; shared service/CLI emergency rules will be added before live enforcement.
- **TraceRookCore**: domain records, exact approval transitions, analysis and Cloud protocols.
- **TraceRookFixtures**: bundled, explicitly synthetic Cloud Demo. Its client rejects live-origin analysis. No networking dependency exists in this module.

The service will be the sole SQLite writer. The hook socket will carry events and decisions only, with no approval/trust commands. Authenticated XPC will carry UI status and exact approval mutations. Notifications are an affordance; deadlines and pending state belong to the service.

No third-party runtime dependencies, broad disk access, root daemon, cloud backend, embedded web UI or live-agent configuration changes are introduced by the foundation build.

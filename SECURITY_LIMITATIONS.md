# Security and release limitations

The architecture specification is authoritative. This development build is being implemented sequentially. It is not a released security product.

## Foundation / native demo

- Live hooks, LaunchAgent registration, XPC, SQLite ingestion, BYOK and live enforcement are not enabled in the Phase 0/1 build. Integration controls describe this accurately; they do not simulate successful installation.
- Demo account, usage, sessions, incidents and approvals are bundled synthetic data. No Cloud network transport, authentication, purchase or billing exists. Demo approvals cannot authorize a real agent action.
- The hook foundation binary refuses ordinary invocation. Do not install it manually into an agent configuration before the live phases pass acceptance tests.
- Development app builds use ad-hoc signing by default. Ad-hoc signatures do not establish Developer ID identity, notarization or trusted approval IPC.

## Product boundaries

TraceRook can enforce decisions only inside supported callbacks that actually run and return before the agent timeout. Hooks are guardrails, not a sandbox or system-wide endpoint enforcement. A lost, skipped, untrusted or timed-out hook can permit execution. Hosted tools, some specialized paths, nested process operations, and Codex continuation calls can be outside coverage.

Same-user processes can change configurations or disable hooks. Unix peer UID checks isolate other users, not malicious processes running as the account owner. Approval mutations require authenticated, signed-client XPC in the live implementation.

Model findings are advisory. Only enabled deterministic catastrophic rules with concrete evidence can cause an automatic critical block. Allow once means passing TraceRook for the exact waiting invocation; host permissions remain independent. An allow does not prove execution.

Redaction cannot guarantee removal of every secret. BYOK must require explicit consent, minimum redacted context, a second preflight scanner and direct Anthropic transport. Keys belong in Keychain, never logs or the history database. Local SQLite storage is permission restricted but not encrypted in MVP1.

Release remains blocked until all gates in specification §20 are validated, including real Claude Code and Codex pre-execution tests and signed/notarized macOS 26/27 testing.

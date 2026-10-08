# Agent compatibility

| Host | Adapter | Real installed-version smoke | Coverage |
|---|---|---|---|
| Claude Code | 1.0.0 foundation | Not performed | Not integrated |
| Codex | 1.0.0 foundation | Not performed | Not integrated |

Phase 0 fixtures use the hook envelope described in specification §6–7. They test normalization and output shape only. Installation methods currently return `unsupportedOperation`; no user configuration is modified.

Live installation must inspect actual versions and host schemas, preserve unrelated hooks and configuration, present a preview and require explicit consent. Codex requires host trust review via `/hooks`; installed does not mean trusted. The Claude shell-form command example will be verified against the installed API before generating configuration.

Denials use `hookSpecificOutput.permissionDecision = deny`. Allows emit empty stdout. Unsupported `ask`, `continue: false`, or host permission-grant output must not be used. Hosted tools, continuation calls and callback timeouts have coverage limitations.

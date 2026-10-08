# Agent compatibility

| Host | Adapter | Real installed-version smoke | Coverage |
|---|---|---|---|
| Claude Code | 1.0.0 foundation | Not performed | Not integrated |
| Codex | 1.0.0 foundation | Not performed | Not integrated |

Phase 0 fixtures use the hook envelope described in specification §6–7. They test normalization and output shape only. Installation methods currently return `unsupportedOperation`; no user configuration is modified.

Live installation must inspect actual versions and host schemas, preserve unrelated hooks and configuration, present a preview and require explicit consent. Codex requires host trust review via `/hooks`; installed does not mean trusted. The Claude shell-form command example will be verified against the installed API before generating configuration.

Denials use `hookSpecificOutput.permissionDecision = deny`. Allows emit empty stdout. Unsupported `ask`, `continue: false`, or host permission-grant output must not be used. Hosted tools, continuation calls and callback timeouts have coverage limitations.

## MVP2 read-only audit — 2026-10-08

| Host | Installed version | V2 contract / installed hook | Live denial / verified classes |
|---|---|---|---|
| Claude Code | 2.1.290 | Additive adapter 2.0.0 contract; no installed TraceRook hook | Not run / none |
| Codex | 0.162.0-alpha.2 | Additive adapter 2.0.0 contract; user hooks file absent | Not run / none |

Current official documentation was checked; it is not evidence of behavior on these exact binaries. Claude command hooks support executable-plus-`args` form as well as shell form. Synchronous `PreToolUse` deny output blocks; command-hook timeout resumes normal host permissions. The Agent SDK callback timeout behaves differently and is outside this integration. MCP provenance must not be inferred from a tool-name prefix. [Claude hooks reference](https://code.claude.com/docs/en/hooks).

Codex documents `tool_input` as a JSON value; Bash and apply_patch use its `command` field. The current foundation decoder's object assumption needs tool-specific handling. apply_patch matches Edit/Write aliases. Hosted WebSearch and write_stdin continuation lack this pre-tool gate. Unsupported pre-tool ask/continue fields can fail the hook while the tool continues. Native trust and each claimed tool class require installed-version tests. [Codex hooks reference](https://learn.chatgpt.com/docs/hooks).

### Synthetic schema samples for later adapter tests

These are authored examples of documented fields, not captured runtime input and not installable hook configuration. No transcript path/content is needed for this sample. [Claude input reference](https://code.claude.com/docs/en/hooks#pretooluse-input), [Codex input reference](https://learn.chatgpt.com/docs/hooks#pretooluse).

```json
{"session_id":"synthetic-claude","cwd":"/tmp/tracerook-test","hook_event_name":"PreToolUse","tool_name":"Write","tool_use_id":"synthetic-call","tool_input":{"file_path":"/tmp/tracerook-test/example.txt","content":"sample"}}
```

```json
{"session_id":"synthetic-codex","turn_id":"synthetic-turn","cwd":"/tmp/tracerook-test","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_use_id":"synthetic-call","tool_input":{"command":"*** Begin Patch\n*** Add File: example.txt\n+sample\n*** End Patch"}}
```

The schema samples intentionally contain no grants or rewrite output. The operating bridge remains disabled. Read the [acceptance matrix](MVP2_ACCEPTANCE.md) for remaining host/security gates and the [implementation plan](MVP2_PR2_PLAN.md) for source changes. Any future protocol-version output denotes wire compatibility, not a claim that hooks are operational.

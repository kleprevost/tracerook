# Agent compatibility

| Agent | Version | Hook | Status |
| --- | --- | --- | --- |
| Claude Code | 2.1.290 | Synchronous `PreToolUse` command hook | Supported |
| OpenAI Codex | — | `PreToolUse` with `/hooks` trust review | Coming soon |

## Decision output

- **Deny:** `hookSpecificOutput.permissionDecision = "deny"` with a short sanitized reason.
- **No override:** empty stdout and exit code 0, which hands the call back to the agent's own permission flow.

TraceRook never emits `ask`, `continue: false` or a permission grant, so the agent's permission system stays in charge of allowing a tool.

## Claude Code configuration

Add a synchronous command hook alongside your existing settings (see [installation](BETA_RELEASE.md#configure-claude-code)). The hook timeout (85 s) sits above TraceRook's own 80 s budget so that a 45-second human review always completes inside the callback.

## Sample `PreToolUse` input

```json
{"session_id":"sample-claude","cwd":"/tmp/tracerook-test","hook_event_name":"PreToolUse","tool_name":"Write","tool_use_id":"sample-call","tool_input":{"file_path":"/tmp/tracerook-test/example.txt","content":"sample"}}
```

```json
{"session_id":"sample-codex","turn_id":"sample-turn","cwd":"/tmp/tracerook-test","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_use_id":"sample-call","tool_input":{"command":"*** Begin Patch\n*** Add File: example.txt\n+sample\n*** End Patch"}}
```

References: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Codex hooks](https://learn.chatgpt.com/docs/hooks).

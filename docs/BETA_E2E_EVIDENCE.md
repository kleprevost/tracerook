# Beta execution evidence

This harness separates local deterministic checks, an actual host callback with a local model double, and genuine hosted-provider evidence. A local model double never counts as Anthropic/provider evidence.

## Commands and prerequisites

- `scripts/beta-e2e.sh --check`: read-only installed CLI versions and prerequisite report.
- `scripts/beta-e2e.sh --local`: service, adapter, rules, privacy and contract tests in a private disposable Swift scratch directory. Does not rebuild the shared app bundle or start a host.
- `scripts/beta-e2e.sh --host-callback --helper /absolute/path/to/signed/tracerook-hook --coordinated`: explicitly coordinated, opt-in Claude execution. Requires an operational signed helper and authenticated running service. Uses documented `--settings`, `--setting-sources`, `--strict-mcp-config`, `--mcp-config`, `--no-session-persistence`, and private `CLAUDE_CONFIG_DIR`. Never use `--bare`: it disables hooks.

The callback harness supplies two deterministic Bash tool calls through a localhost Messages/SSE double. The benign command writes a sentinel. The denial canary attempts to remove an empty disposable `.claude/settings.local.json` in the private project and then write a second sentinel. It cannot delete founder configuration. Success requires an actual host callback for the canary, explicit deny/exit 2, benign execution, host exit zero, and absence of the denial sentinel. Its result contains only bounded booleans, counts and exit status. Raw callback payloads remain inside the temporary directory and are removed on exit. No credentials or real provider calls are used. The supplied helper's service state is a separate prerequisite; the harness does not install or repair it.

## Executed checks, 2026-10-08

| Check | Result | Scope |
|---|---|---|
| Claude version | passed | `2.1.290 (Claude Code)`, read-only |
| Codex version | passed | `codex-cli 0.162.0-alpha.2`, read-only |
| Harness syntax | passed | Python compilation; shell prerequisite command |
| Isolated local suite | failed to build | Concurrent production source `Agent/ServiceRuntime.swift:15` could not find `SessionCloudCredentialStore`; no test result inferred |
| Actual Claude callback | not run | Signed running service and coordinated host execution required |
| Actual Codex callback | not run | This harness currently covers Claude only; no Codex efficacy claim |
| Genuine hosted Anthropic canary | not run | Parent-owned post-deployment gate; never inferred from local double |

## Required remaining evidence

Existing local suites exercise approval binding/replay, consume once, abort/restart, deadline/failure handling and developer-only Demo isolation. Passing these suites establishes bounded deterministic behavior; actual host approval UI, timeout/outage/malformed provider behavior, native permissions, and current-version Codex callbacks remain separate execution gates. Capture those results against the final signed operational bundle and deployed provider, recording version/source identifiers and safe receipts. No tester count or overall protection efficacy is asserted.

The harness does not modify existing Claude/Codex config, perform installer/repair/uninstall/cohort operations, call Keychain APIs, deploy, or obtain credentials. The opt-in Claude process uses an explicit dummy API key and private config; whether the installed host independently touches Keychain during startup is not established by the unexecuted callback gate. Coordinate this prerequisite before invoking it.

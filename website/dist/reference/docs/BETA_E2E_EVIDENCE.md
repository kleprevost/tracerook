# Beta execution evidence

This harness separates local deterministic checks, an actual host callback with a local model double, and genuine hosted-provider evidence. A local model double never counts as Anthropic/provider evidence.

## Commands and prerequisites

- `scripts/beta-e2e.sh --check`: read-only installed CLI versions and prerequisite report.
- `scripts/beta-e2e.sh --local`: service, adapter, rules, privacy, core and contract tests in a private disposable Swift scratch directory. Does not rebuild the shared app bundle or start a host.
- `scripts/beta-e2e.sh --host-callback --helper /absolute/path/to/signed/tracerook-hook --coordinated`: explicitly coordinated, opt-in Claude execution. Requires an operational signed helper and authenticated running service. Uses documented `--settings`, `--setting-sources`, `--strict-mcp-config`, `--mcp-config`, `--no-session-persistence`, and private `CLAUDE_CONFIG_DIR`. Never use `--bare`: it disables hooks.

The callback harness supplies two deterministic Bash tool calls through a localhost Messages/SSE double. The benign command writes a sentinel. The denial canary attempts to remove an empty disposable `.claude/settings.local.json` in the private project and then write a second sentinel. It cannot delete founder configuration. Success requires an actual host callback for the canary, explicit deny/exit 2, benign execution, host exit zero, and absence of the denial sentinel. Its result contains only bounded booleans, counts and exit status. Raw callback payloads remain inside the temporary directory and are removed on exit. No credentials or real provider calls are used. The supplied helper's service state is a separate prerequisite; the harness does not install or repair it.

## Executed checks, 2026-10-08

| Check | Result | Scope |
|---|---|---|
| Claude version | passed | `2.1.290 (Claude Code)`, read-only |
| Codex version | passed | `codex-cli 0.162.0-alpha.2`, read-only |
| Harness syntax | passed | Python compilation; shell prerequisite command |
| Isolated local suite | passed, 75 tests | Final retry after host fixture correction; private scratch build, 0 test failures |
| Actual Claude callback | passed | Installed Claude 2.1.290, signed operational helper/service; 2 callbacks, benign executed, explicit dangerous deny, denied sentinel absent, host exit 0; loopback model double |
| Actual Codex callback | not run | This harness currently covers Claude only; no Codex efficacy claim |
| Genuine hosted Anthropic canary | not run | Parent-owned post-deployment gate; never inferred from local double |

## Required remaining evidence

Existing local suites exercise approval binding/replay, consume once, abort/restart, deadline/failure handling and developer-only Demo isolation. Passing these suites establishes bounded deterministic behavior; actual host approval UI, timeout/outage/malformed provider behavior, native permissions, and current-version Codex callbacks remain separate execution gates. Capture those results against the final signed operational bundle and deployed provider, recording version/source identifiers and safe receipts. No tester count or overall protection efficacy is asserted.

The harness does not modify existing Claude/Codex config, perform installer/repair/uninstall/cohort operations, call Keychain APIs, deploy, or obtain credentials. The opt-in Claude process uses an explicit dummy API key and private config; whether the installed host independently touches Keychain during startup is not established by this callback gate. No login or Keychain prompt was observed or interacted with; no Keychain API was called by the harness.

## Executed host result and binary identity

Parent authorized the running test LaunchAgent with an unenrolled, memory-only Cloud client before execution. The actual installed Claude CLI ran with the explicit temporary settings and loopback model endpoint. The deterministic model double supplied tools; genuine Claude inference and hosted classification were not exercised.

```json
{"benign_executed":true,"callback_count":2,"dangerous_denied":true,"denied_sentinel_absent":true,"host_exit":0,"kind":"actual_claude_callback_local_model_double","provider":"loopback_double"}
```

The callback-used helper SHA-256 was `310cd45ff224a99b29da2acb5a5b8c0745bf6709a0ce3ce2d9b327a685054c8c`; agent SHA-256 was `110cbe4178547e49669ebd932d3b77eb9aece431c00e1f1eb997c9e661023bd2`. HEAD at capture was `f087e248bbafb1eb06967d6af432ee41908d473d` with concurrent uncommitted production implementation; that commit alone does not identify all tested source. Parent must record the final source commit and any subsequent bundle changes separately.

Earlier local attempts encountered a concurrent missing credential-store symbol and two invalid synthetic receipt-identifier fixtures. The implementation owner corrected these; the final independent isolated run passed 75 tests. Those fixture corrections do not substitute for the separately executed actual host callbacks above.

## Additional host failure and Codex gates

`--case timeout` and `--case outage` extend the Claude callback command. Both use only `sudo --version; printf denied > denied-sentinel` in the disposable project: a high-risk command shape whose actual execution is harmless. They require an actual helper denial and absent sentinel. Timeout gives the helper a 4000ms deadline and requires at least 1.5 seconds inside the callback. Outage requires the parent to stop its test service before the run and restore it afterward; the harness never stops services. These are pending execution. Benign inspected commands may legitimately use local fallback during service outage; that is distinct from these high-risk failure canaries.

The Codex harness is `python3 scripts/test-support/beta-codex-callback.py --helper ABSOLUTE_HELPER --coordinated --review-hooks`. It creates private subprocess-only `CODEX_HOME`, file-only credential storage, a localhost Responses double, and exact PreToolUse hooks. It opens the native TUI for `/hooks` review before noninteractive execution. It does not fabricate a trust registry or use a trust-bypass option. The exact configured hook must be reviewed and trusted through the native workflow. Codex remains unverified until this gate and actual callbacks execute successfully; the Responses double is currently syntax-checked, not a tested inference implementation.

The [official OpenAI hooks documentation](https://learn.chatgpt.com/docs/hooks) documents canonical Bash hooks, `tool_input.command`, exact-definition native trust review through `/hooks`, and skipping hooks that remain untrusted. The [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) documents custom provider base URL, Responses transport, and provider authentication options. Installed 0.162.0-alpha.2 help confirms `--no-daemon`, `exec --ephemeral`, and `--strict-config`. These prerequisites establish a documented testing path, not successful installed-version coverage.

### Actual Claude timeout result

The parent confirmed the original callback-tested bundle was unchanged and the test service was running. The timeout case then passed without any review approval or click. One actual Claude callback took 3.104 seconds with the helper's 4000ms hard limit and returned explicit deny; the sentinel was absent and the host exited zero. This establishes bounded hook timeout denial, not a successful human review or real provider inference.

```json
{"benign_executed":null,"callback_count":1,"callback_elapsed_seconds":3.104,"case":"timeout","dangerous_denied":true,"denied_sentinel_absent":true,"elapsed_seconds":3.813,"host_exit":0,"kind":"actual_claude_callback_local_model_double","provider":"loopback_double"}
```

Codex remains unverified pending normal native hook trust review. Service outage remains pending the parent-owned stop window.

### Actual Claude service outage result

The parent explicitly authorized stopping only `com.tracerook.agent.test` for this gate. Its `launchctl bootout` returned zero; the harness then passed against the unchanged callback-tested helper while that test service was stopped. The one callback returned explicit deny in 0.078 seconds, the sentinel remained absent, and Claude exited zero. The test service was deliberately left stopped for the parent to rebuild the final source. This tests the helper's conservative high-risk local fallback, with no real provider request or credential use.

```json
{"benign_executed":null,"callback_count":1,"callback_elapsed_seconds":0.078,"case":"outage","dangerous_denied":true,"denied_sentinel_absent":true,"elapsed_seconds":1.225,"host_exit":0,"kind":"actual_claude_callback_local_model_double","provider":"loopback_double"}
```

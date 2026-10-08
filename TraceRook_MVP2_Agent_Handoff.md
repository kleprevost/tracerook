# TraceRook MVP2 — Coding Agent Handoff

## Mission

Implement TraceRook MVP2 as a **real-protection native macOS beta** in the existing repository at https://github.com/kleprevost/tracerook. Do not rebuild or replace MVP1's UI. The full technical requirements and release criteria are in `TraceRook_MVP2_Architecture_Implementation_Spec.md`. Read that document first, along with `TraceRook_MVP1_Architecture_Spec.md`, `docs/IMPLEMENTATION_STATUS.md`, `docs/ARCHITECTURE.md`, `docs/AGENT_COMPATIBILITY.md`, and `SECURITY_LIMITATIONS.md`.

## Non-negotiable constraints

- macOS 26+; Apple Silicon arm64; Swift 6; SwiftUI/AppKit native; no Electron or app webview.
- Claude Code and Codex local hooks only; no OpenCode/hosted/system-wide enforcement in MVP2.
- Cloud Demo remains synthetic. Anthropic **BYOK** is the only live Claude analysis provider in this release, direct Mac-to-Anthropic API.
- Privacy by design: no raw secrets/tool arguments/transcripts in persistent logs, DB, or telemetry; Keychain storage; redaction and remote preflight before every API call.
- A host/tool class is **Protected** only if a real installed-version pre-execution benign deny test proves that the tool body did not execute.
- No model recommendation, notification click, service error or `allow once` action may bypass native Claude Code/Codex permissions.
- Critical rules block automatically with concrete local evidence; high risks request approval; medium warn; low proceed with no TraceRook override.
- Service owns approvals, expiry and storage. Signed app XPC handles approval mutations. Hook CLI socket never accepts approval writes.
- Never describe timed-out/skipped/untrusted hooks as fail-closed, and never label Cloud Demo as real protection.

## PR sequence and acceptance

1. **Baseline + contracts.** Pin current `main` SHA, inventory actual source, run all current scripts, capture host CLI versions. Introduce MVP2 acceptance matrix and versioned IPC DTOs; retain schema-v1 migrations.
2. **Service + authenticated IPC + SQLite.** Implement LaunchAgent/lifecycle, signed-family XPC, bounded Unix socket, SQLite single writer, migration/retention and real UI state; tests reject spoofed approval callers and service errors.
3. **Claude Code live integration.** Build safe hook install/diff/repair/uninstall; wire CLI bridge, emergency fallback, `PreToolUse` host output; run harmless real-host denial with absent canary side effect.
4. **Codex live integration.** Use trusted user hook config and `/hooks` trust review; test Bash and apply_patch before claiming verified coverage; preserve host approvals and other installed hooks.
5. **Policy + notifications + approval state.** Implement deterministic rules, high-risk notification review with Block/Allow Once, exact-invocation CAS binding and expiry; test concurrency/replay/stale notifications/host timeout.
6. **Real Anthropic BYOK.** Keychain and consent; direct Messages API, bounded structured verdict, privacy preview/preflight, model request budgets, drift warnings. Prove actual live-host event -> redacted API call -> typed verdict -> incident with sanitized evidence.
7. **Beta hardening.** Signed/notarized build, clean install/uninstall, macOS 26/27 tests, p95 latency measurements, VoiceOver and notifications; change public claims only after passing real-host gates.

## First coding-agent instruction

> Start with **PR 1 only**. Inspect the existing project; don't assume the specification's inferred types match the checked-out code. Run the repository tests and build commands, capture installed Claude Code/Codex versions, list the exact files/classes to modify for service IPC and hook integration, and add a phase-by-phase acceptance checklist to docs. Return a concise report with passed tests, blockers, risks, and the proposed changes for PR 2. Do not edit user agent configurations, run live hooks, deploy, publish the website or merge without user approval.

## Demonstration required before declaring MVP2 complete

**A. Live blocking:** In a disposable directory, a real supported Claude Code or Codex tool call that would create `should-not-exist.txt` is denied by TraceRook; confirm the file does not exist and UI records a verified host denial.

**B. Real Claude:** With an opt-in test Anthropic key, the host supplies a benign suspicious event; show the minimized payload preview and the real API response parsed into `AnalysisVerdict`, along with request model ID, status and token counts, never revealing sensitive values.

**C. Native review:** High-risk action remains pending while macOS notification is shown; Block denies; Allow Once clears TraceRook review only for the exact waiting invocation; expiry denies; stale/replayed actions do not work.

**D. Shipping:** Clean signed/notarized install, no old dummy protection states, live/demo isolation, explicit hook coverage limitations and measured latency.

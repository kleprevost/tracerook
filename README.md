<p align="center">
  <img src="docs/assets/tracerook-icon.png" alt="TraceRook" width="80" height="80">
</p>

<h1 align="center">TraceRook</h1>

<p align="center">
  <strong>Let your agent build. Keep the next move in check.</strong>
</p>

<p align="center">
  Native macOS guardrails for local coding agents.<br>
  Local rules first. Contextual analysis with Anthropic Claude.
</p>

<p align="center">
  <strong>macOS 26+</strong> &nbsp;·&nbsp; Apple Silicon &nbsp;·&nbsp; Swift 6 + SwiftUI &nbsp;·&nbsp; MIT
</p>

<p align="center">
  <a href="#try-the-preview">Try the preview</a> &nbsp;·&nbsp;
  <a href="#documentation">Documentation</a> &nbsp;·&nbsp;
  <a href="#roadmap">Roadmap</a> &nbsp;·&nbsp;
  <a href="https://tracerook.dev">Website</a>
</p>

TraceRook is an independent review layer for developers working with **Claude Code and OpenAI Codex**. Its MVP1 architecture combines deterministic local policy with **Anthropic Claude** to assess risky supported tool calls before execution, explain the evidence, and put consequential decisions in your hands.

> **Development preview:** The native app and Cloud Demo are working. Live agent integrations, pre-execution enforcement, and Anthropic BYOK analysis are upcoming. This build does not protect real sessions or collect API keys; signed, notarized distribution remains a release gate.

![TraceRook native macOS dashboard showing explicitly labeled Cloud Demo fixtures and real integrations marked Not integrated](docs/assets/dashboard-demo.png)

*Actual SwiftUI app · bundled sample data · no live protection implied.*

## Why TraceRook

Coding agents act on commands, files, services, and instructions from sources you may not trust. TraceRook’s MVP1 design adds a second look at the action—and its relationship to the task you asked for.

- **Review before execution.** Supported local hooks provide the opportunity to block critical actions or pause high-risk ones for human review.
- **Local policy + Claude context.** Deterministic rules handle concrete dangerous signatures. Anthropic Claude adds task relevance, prompt-injection indicators, and intent-drift analysis. Model findings remain advisory.
- **A deliberate privacy boundary.** Planned BYOK sends selected, minimized, redacted context directly from your Mac to Anthropic, using your own key stored in Keychain. Additional code excerpts default off.
- **Native decisions, clear evidence.** A menu bar companion, session timelines, incident details, and exact-action approvals make the reasoning visible. Protection status must reflect verified coverage.

## Explore what works today

The current preview includes:

- A native dashboard with Overview, Sessions, Incidents, Approvals, Integrations, and Settings.
- Onboarding, provider selection, privacy previews, and light/dark appearance.
- A focused review panel with sample Allow once, Block, and expiry behavior.
- Cloud Demo account, usage, plans, and findings backed by bundled fixtures, with no analysis network requests.

Demo data stays separate from real activity. Real sessions remain empty and **Not integrated** until the live phases pass their acceptance gates.

## Try the preview

**Run:** Apple Silicon Mac, macOS 26 or later. **Build:** Swift 6 and the macOS 27 SDK; full Xcode 27 is required for Xcode archives.

From the repository root:

```sh
./scripts/build.sh
open build/TraceRook.app --args --demo
```

Browse a sample session, inspect an incident, then select **Simulate review**. Open Approvals or the native review panel and try Block, Allow once, or let the 45-second sample deadline expire.

For Xcode setup, automated checks, and preview switches, see the [development guide](docs/DEVELOPMENT.md).

## Documentation

| Guide | What you’ll find |
| --- | --- |
| [Product documentation](https://tracerook.dev/docs/) | 20 searchable guides covering the app, Claude, privacy, integrations, policy, and engineering |
| [Development](docs/DEVELOPMENT.md) | Build, run, test, and work on the native app |
| [Architecture](docs/ARCHITECTURE.md) | Processes, Swift packages, and transport boundaries |
| [Privacy](docs/PRIVACY.md) | Data minimization, redaction, and planned BYOK behavior |
| [Threat model](docs/THREAT_MODEL.md) | Trust assumptions and enforcement boundaries |
| [Agent compatibility](docs/AGENT_COMPATIBILITY.md) | Host-specific decisions and verification requirements |
| [Implementation status](docs/IMPLEMENTATION_STATUS.md) | Acceptance evidence, pending gates, and platform observations |
| [Authoritative MVP1 specification](TraceRook_MVP1_Architecture_Spec.md) | Approved product and engineering requirements |

The [static website source](website/README.md) is included in this repository and can be served by a static host.

## Roadmap

| Milestone | Status |
| --- | --- |
| Phase 0 · Native foundations, contracts, and test harness | Passed locally |
| Phase 1 · Native UI and Cloud Demo | Implemented; manual accessibility and notification acceptance remain |
| Phases 2–3 · Live hooks, safe installation, persistence, and enforcement | Upcoming; real-host pre-execution proof required |
| Phase 4 · Direct Anthropic BYOK and session drift | Upcoming |
| Phase 5 · Hardening, Developer ID signing, and notarized beta | Upcoming |

Each phase must compile, pass relevant automated tests, and deliver a working native demonstration. The [implementation record](docs/IMPLEMENTATION_STATUS.md) tracks the evidence; there is no signed beta download yet.

## Security boundaries

TraceRook’s intended enforcement depends on supported callbacks that actually run and return in time. Lost, skipped, untrusted, or timed-out hooks can permit execution. Nested processes, hosted tools, remote sessions, and commands outside an integrated agent may be outside coverage. Native agent permissions remain independent.

Redaction can miss secrets, and same-user processes can disable hooks. Read the [security limitations](SECURITY_LIMITATIONS.md) for the complete boundary. Do not manually install the current foundation bridge into agent settings; live integration is not enabled.

## Contributing

Start with the [MVP1 specification](TraceRook_MVP1_Architecture_Spec.md) and [development guide](docs/DEVELOPMENT.md). Contributions should preserve explicit demo labeling, user privacy, reversible configuration changes, and truthful coverage. Include relevant acceptance evidence and document deviations caused by actual platform or host behavior.

## License

[MIT](LICENSE) · Copyright © 2026 Kyle LePrevost.

Claude is a product of Anthropic. TraceRook is an independent project; no affiliation or endorsement is implied.

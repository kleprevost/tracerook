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

TraceRook is an independent review layer for developers working with **Claude Code and OpenAI Codex**. Its MVP2 design combines deterministic local policy with **Anthropic Claude** to assess risky supported tool calls before execution, explain the evidence, and put consequential decisions in your hands.

> **Invited beta available:** Native app, authenticated local service, private SQLite history, exact-action review UI, and fixture demonstrations are implemented. Production Cloud API deployment and HTTPS authentication are verified; 60 Worker tests pass. Claude Code 2.1.290 passed actual callback allow/deny, bounded timeout, and high-risk service-outage checks using a local model double. Genuine hosted Haiku inference and the full signed native host-to-Cloud-to-Claude-to-human-review path passed; the broader hosted evaluation corpus remains in progress; Codex coverage remains unverified. The beta retains ad-hoc signatures and is not notarized. [Download beta 0.1.0-beta.1](https://github.com/kleprevost/tracerook/releases/tag/v0.1.0-beta.1); Cloud access requires an invitation.

![TraceRook native macOS dashboard showing explicitly labeled Cloud Demo fixtures and real integrations marked Not integrated](docs/assets/dashboard-demo.png)

*Actual SwiftUI app · bundled sample data · no live protection implied.*

## Why TraceRook

Coding agents act on commands, files, services, and instructions from sources you may not trust. TraceRook’s design adds a second look at the action—and its relationship to the task you asked for.

- **Review before execution.** Supported local hooks provide the opportunity to block critical actions or pause high-risk ones for human review.
- **Local policy + Claude context.** Deterministic rules handle concrete dangerous signatures. Anthropic Claude adds task relevance, prompt-injection indicators, and intent-drift analysis. Model findings remain advisory.
- **A deliberate privacy boundary.** TraceRook Cloud sends coarse task/action categories and local signal codes onward to Anthropic using TraceRook’s company-owned key. Raw commands, paths, code, file contents, and transcripts are excluded. The connected local API demonstration uses synthetic fixtures. The deployed Cloud API and full native Claude Code path have genuine Haiku receipt evidence. Native BYOK remains unavailable.
- **Native decisions, clear evidence.** A menu bar companion, session timelines, incident details, and exact-action approvals make the reasoning visible. Protection status must reflect verified coverage.

## Explore what works today

The current preview includes:

- A native dashboard with Overview, Sessions, Incidents, Approvals, Integrations, and Settings.
- Onboarding, provider selection, privacy previews, and light/dark appearance.
- Live exact-action Allow once and Block, plus a separate sample review panel.
- Cloud Demo account, usage, plans, and findings backed by bundled fixtures, with no analysis network requests.
- Strict IPC v2 framing, request/reply validation, exact invocation bindings, and packaged helper self-tests, preserving v1 compatibility.
- An authenticated local service, sanitized private SQLite history, and durable exact-review transitions, with supported callbacks feeding local policy and exact-action review.
- Settings → Local API Demo: authenticated enrollment, six fixed scenarios, validated synthetic verdicts, typed failures, actual fixture usage, credential rotation, revocation and deletion over local HTTP.

Demo data stays separate from real activity. Simulated service ingestion is labeled and excluded from observed host-session counts. Host integrations remain **Not integrated** until live acceptance gates pass.

## Invited beta download

[Beta 0.1.0-beta.1](https://github.com/kleprevost/tracerook/releases/tag/v0.1.0-beta.1) is published as a versioned Apple Silicon ZIP with a manifest and SHA256SUMS for the initial ten testers. It retains ad-hoc signatures and is not notarized. See [beta release instructions](docs/BETA_RELEASE.md) for macOS 26+ requirements, checksum verification, Apple’s manual opening workflow, and current acceptance limits. Cloud access requires a separate invitation; installation alone does not enable host protection.

## Try the preview

**Run:** Apple Silicon Mac, macOS 26 or later. **Build:** Swift 6 and the macOS 27 SDK; full Xcode 27 is required for Xcode archives.

From the repository root:

```sh
./scripts/build.sh
open build/TraceRook.app --args --demo
```

Browse a sample session, inspect an incident, then select **Simulate review**. Open Approvals or the native review panel and try Block, Allow once, or let the 45-second sample deadline expire.

To try the connected local API, follow [backend setup](backend/LOCAL_MOCK.md) and [native demonstration steps](docs/LOCAL_API_DEMO_EVIDENCE.md). It needs no Anthropic key. For Xcode setup, checks, and preview switches, see the [development guide](docs/DEVELOPMENT.md).

## Documentation

| Guide | What you’ll find |
| --- | --- |
| [Product documentation](https://tracerook.dev/docs/) | Public guides for the preview and connected local API demonstration |
| [Development](docs/DEVELOPMENT.md) | Build, run, test, and work on the native app |
| [Architecture](docs/ARCHITECTURE.md) | Processes, Swift packages, and transport boundaries |
| [Privacy](docs/PRIVACY.md) | Data minimization, redaction, and planned BYOK behavior |
| [Threat model](docs/THREAT_MODEL.md) | Trust assumptions and enforcement boundaries |
| [Agent compatibility](docs/AGENT_COMPATIBILITY.md) | Host-specific decisions and verification requirements |
| [Implementation status](docs/IMPLEMENTATION_STATUS.md) | Acceptance evidence, pending gates, and platform observations |
| [Authoritative MVP1 specification](TraceRook_MVP1_Architecture_Spec.md) | Approved product and engineering requirements |
| [Authoritative MVP2 specification](TraceRook_MVP2_Architecture_Implementation_Spec.md) | Additive real-protection architecture and release gates |
| [MVP2 acceptance matrix](docs/MVP2_ACCEPTANCE.md) | Passed contract checks, source gaps, and phase-by-phase requirements |
| [Next implementation: PR2](docs/MVP2_PR2_PLAN.md) | Exact service, authentication, SQLite, and native UI changes |
| [Local service evidence](docs/MVP2_SERVICE_EVIDENCE.md) | Actual peer authentication, durable state, and non-notarized development limitations |
| [Local API client preparation](docs/LOCAL_API_CLIENT_PREPARATION.md) | What is ready and what still depends on the mock backend |
| [Proposed backend handoff](docs/LOCAL_MOCK_API_HANDOFF.md) | Fixture-only local routes, provenance, deadlines, and integration tests |

The [static website source](website/README.md) is included in this repository and can be served by a static host.

## Roadmap

| Milestone | Status |
| --- | --- |
| MVP1 · Native UI and Cloud Demo | Implemented; manual accessibility and notification acceptance remain |
| MVP2.0 · Baseline and IPC v2 contracts | Passed locally; 43 tests, debug/release builds, native launch and renders |
| MVP2.1 · Authenticated service, SQLite and real UI state | Implemented locally; actual peer-rejection tests pass in explicit ad-hoc mode; Developer ID validation remains untested |
| MVP2.2–2.3 · Claude Code and Codex live hooks | Claude Code 2.1.290 allow/deny, timeout and outage gates pass; Codex remains unverified; manual configuration only |
| MVP2.4 · Local rules and native approval loop | Local policy, operational callbacks, durable review CAS and real approval UI implemented; actual native Allow once/Block passed |
| MVP2.5 · Direct Anthropic Claude BYOK and drift | Pending; consent, Keychain, privacy preflight and a real provider call |
| Invited beta distribution | Published ad-hoc, non-notarized ZIP; macOS 26, clean tester installation, accessibility and release checks remain |
| Local API demonstration | Implemented locally; actual native/XPC/HTTP and lifecycle proof pass; fixtures have no protection authority |
| MVP3 · TraceRook-operated Claude alpha | Production API deployed; 60 Worker tests pass; genuine hosted receipts and full native Claude review passed; wider evaluation remains |

Each phase must compile, pass relevant automated tests, and deliver a working native demonstration. The [implementation record](docs/IMPLEMENTATION_STATUS.md) tracks the evidence; the published beta uses ad-hoc signatures and is not notarized.

## Security boundaries

TraceRook’s intended enforcement depends on supported callbacks that actually run and return in time. Lost, skipped, untrusted, or timed-out hooks can permit execution. Nested processes, hosted tools, remote sessions, and commands outside an integrated agent may be outside coverage. Native agent permissions remain independent.

Redaction can miss secrets, and same-user processes can disable hooks. Read the [security limitations](SECURITY_LIMITATIONS.md) for the complete boundary. Use only the manual configuration and tested scope in [beta release instructions](docs/BETA_RELEASE.md); installing an agent alone does not establish coverage.

## Contributing

Start with the [MVP2 specification](TraceRook_MVP2_Architecture_Implementation_Spec.md), [handoff](TraceRook_MVP2_Agent_Handoff.md), retained [MVP1 specification](TraceRook_MVP1_Architecture_Spec.md), and [development guide](docs/DEVELOPMENT.md). Contributions should preserve explicit demo labeling, user privacy, reversible configuration changes, and truthful coverage. Include relevant acceptance evidence and document deviations caused by actual platform or host behavior.

## License

[MIT](LICENSE) · Copyright © 2026 Kyle LePrevost.

Claude is a product of Anthropic. TraceRook is an independent project; no affiliation or endorsement is implied.

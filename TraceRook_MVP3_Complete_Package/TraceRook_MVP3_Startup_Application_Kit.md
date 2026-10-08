# TraceRook — Claude Startups Application & Public Launch Kit

**Date:** 2026-10-08 · **Status:** Drafts and evidence checklist; customize with verified facts before publishing/submitting  
**Read with:** `TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md` and `TraceRook_MVP3_Coding_Agent_Handoff.md`

## 1. Application strategy

**The desired outcome is admission to the Claude Startups program, but Anthropic alone decides.** As of 2026-10-08, the official [program page](https://claude.com/programs/startups) says bootstrapped companies can apply if founded in the last five years or funded in the last two. It calls for a Claude Console account, company-domain email, website and short product description. Approved applicants may receive $1,000 first-party Claude API credits plus other benefits under program terms. **Do not wait for all of MVP3 to ship to apply.** Apply once the company account and existing product evidence are ready, then add a real Cloud demo if there is an opportunity to update the application.

The strongest message: **TraceRook uses Claude not just to generate code but to reason about another coding agent's proposed behavior and the developer's intent.** Local deterministic controls and verified tool hooks provide enforceable guardrails; Claude contributes context, intent alignment, prompt-injection suspicion, uncertainty and human-readable risk evidence. Cloud hosting makes that reasoning accessible without requiring each developer to supply an API key.

Avoid framing this as replacing Claude Code permissions or as an endpoint security agent. It is an independent, developer-controlled *advisory + locally enforced* layer with clearly defined hook coverage.

## 2. Exact evidence hierarchy

| Evidence available | You may claim | You must not claim |
|---|---|---|
| Public native app / committed Swift code | Native macOS product is built | Every security workflow is verified live |
| Passed real Claude Code/Codex hook test | Specific supported tool actions can be blocked | All code-agent operations are universally protected |
| Real direct BYOK call | Product integrates the Anthropic Claude API via user key | TraceRook-hosted Cloud billing/analysis is operational |
| Real hosted first-party Claude call | Cloud uses TraceRook-owned Anthropic API | Public general availability, unlimited capacity, approved partner status |
| Invited external developer used real Cloud alpha | Private alpha has been used by a verified tester | A numerical customer count beyond documented users |
| Anthropic acceptance notice | Member/benefits, subject to program terms | Official security certification or product endorsement |

**As of the public `main` inspected during drafting**, README still describes partial MVP2 preview; founder reports MVP2 complete/deployed. Reconcile using the real release SHA, live test evidence and current site before using any of these states as an application fact.

## 3. Suggested application description — use TODAY if live hosted Cloud is not yet evidenced

> **TraceRook is a native macOS security supervisor for AI coding agents, starting with Claude Code and Codex.** As agents autonomously run commands, modify code, and follow external instructions, developers need to catch credential exposure, destructive operations, prompt injection and deviations from the authorized task. TraceRook combines deterministic local security rules and agent-hook interception with Anthropic Claude for contextual risk assessment and explanations. We've built the macOS app and are evolving our existing Claude integration into an invitation-only TraceRook Cloud service using the first-party Claude API. Claude is the reasoning layer that helps distinguish legitimate development work from suspicious agent behavior, while enforcement remains local and developer-controlled. We are applying to Claude Startups to accelerate cloud analysis, test quality and early developer adoption.

*Before submission:* Amend "existing Claude integration" if real BYOK has not been established at release, and name the specific capability that is actually verified. Do not assert a live cloud backend until the production Anthropic call is documented.

## 4. Suggested description — AFTER genuine hosted Claude analysis is live

> **TraceRook protects developers working with autonomous coding agents.** Our native macOS app observes supported Claude Code and Codex tool actions, applies fast deterministic security controls, and escalates ambiguous behavior to Claude through TraceRook Cloud. Claude evaluates proposed actions against the user's original task, identifies possible credential theft, prompt injection and scope drift, and returns structured risk evidence. TraceRook then enforces local policies or presents native approval controls, without granting agents permissions they did not already have. We have deployed a private-alpha cloud service that makes authenticated first-party Anthropic Claude API calls on behalf of invited developers, with redacted context, usage limits and auditable incident provenance. We want to expand the evaluation corpus, improve accuracy and bring Claude-powered oversight to more developers.

*Before submission:* Replace “Codex”/“protects” if those live host classes are not verified. Use only after true hosted call and native incident proof exist. Actual beta testers or API volumes may be added only with sourced counts.

## 5. Compact answers for likely free-text fields

**Company / product:** TraceRook — native macOS security guardrails and Claude-powered contextual review for AI coding agents.

**Problem:** Autonomous coding agents can execute risky tools, follow malicious repository instructions, expose credentials or deviate from tasks faster than developers can examine every step. Existing static rules lack enough context to identify task-relevance failures.

**Why Claude:** Claude is used as a separate security reasoning layer that assesses sanitized agent activity, task intent and potential prompt injection, returning validated structured evidence for the native UI and local policy engine. The benefit is contextual judgment alongside deterministic local controls, not unrestricted model-driven command execution.

**Target customer:** Individual developers using Claude Code and Codex on Apple Silicon Macs; later expand to security-conscious teams.

**Current stage:** Native app and MVP2 security integration [list only tests you can prove], with TraceRook Cloud [planned / internal live / invite-only live — choose one, never leave ambiguous].

**What program resources unlock:** Claude API credits support realistic security-evaluation workloads, larger adversarial scenario corpora and limited developer trials before monetized subscriptions; improved rate limits and technical guidance support cloud reliability and schema/prompt optimization.

**Differentiation:** Pre-execution hook guardrails plus task-aware LLM analysis, native Mac review/notifications, user-visible privacy boundary and transparent protection coverage; independent of the coding agent itself.

**Distribution:** Open source code/documentation, signed Mac alpha, direct website and GitHub distribution, invitation-only Cloud onboarding. [Only include real download links and user counts when verified.]

## 6. Website launch copy — before private alpha is actually live

**Headline:** Your coding agent moves fast. TraceRook keeps watch.

**Subhead:** Native macOS guardrails for Claude Code and Codex. Local security controls, Claude-powered contextual analysis, and a TraceRook Cloud experience in development.

**CTA:** Join the TraceRook Cloud early-access list.

**Capability banner:** `TraceRook Cloud: under development. Real agent protection depends on installed and verified local integrations. Cloud Demo uses sample data.`

**Trust footer:** `TraceRook is independent software that uses the Anthropic Claude API. It is not affiliated with or endorsed by Anthropic.`

Do not use this variant to imply Cloud analysis currently runs. If MVP2 BYOK is verified, add `Connect your own Anthropic API key today` with accurate instructions.

## 7. Website launch copy — after production-backed invitation alpha works

**Headline:** An independent security review layer for AI coding agents.

**Subhead:** TraceRook combines native macOS interception, fast local controls, and Claude-powered contextual analysis to help spot suspicious tool actions and unintended task drift.

**Feature:** **TraceRook Cloud Private Alpha.** Selected, redacted activity is evaluated by Claude through our hosted service—no personal Anthropic API key required. Invite access and daily limits apply.

**CTA:** Request Cloud Alpha Access · View verified security coverage.

**Truthful boundary:** `TraceRook does not sandbox your Mac. It can block supported agent hook actions when interception completes in time; other operations may be outside coverage.`

**Independent product notice:** `TraceRook uses the Anthropic Claude API. Anthropic does not certify or endorse TraceRook.`

Do not add “Powered by Anthropic” as a misleading partner badge unless brand guidelines and permissions support it; a plain factual product/API reference is sufficient.

## 8. Proof-of-Claude demo storyboard (100 seconds)

**0–12 s:** Open a real build on an Apple Silicon Mac. Show `TraceRook Cloud (Private Alpha)` connected, separately show actual Claude Code hook verification.

**12–27 s:** In a disposable repository, ask Claude Code to implement a small UI change. Show a malicious-looking instruction in a fixture README requesting unrelated credential/network activity. Do not use actual credentials or a real external exfil endpoint.

**27–43 s:** Agent reaches a safely simulated suspicious tool call. Open the local preview of what TraceRook sends. Observe redacted task summary and security flags; no raw source or secret.

**43–60 s:** Show real TraceRook Cloud analysis, Claude model ID, actual request/trace ID and token receipt (mask restricted identifiers). Avoid implying the source system itself performed exfiltration.

**60–80 s:** Show macOS incident notification and rationale. Separately show a local deterministic block test that fails to create a `/tmp` sentinel. Explain the model recommends and local policy enforces.

**80–100 s:** Show actual daily usage/cap and honest unsupported-path limitations, then homepage/alpha CTA.

**Caption:** “Demo runs on a disposable fixture repository. Cloud verdict is from a real Anthropic Claude API call; harmful effects are never executed.” Use the caption only when true.

## 9. Reviewer-ready proof artifact checklist

- [ ] `README.md`, current website and `docs/IMPLEMENTATION_STATUS.md` share the same implementation status.
- [ ] Release tag/SHA and signed/notarized binary or authentic build instructions.
- [ ] Authenticated first-party Anthropic request ID, timestamp, model ID, token usage and TraceRook trace correlation (founder-only unredacted diagnostic; public sanitized excerpt).
- [ ] One real intercepted Claude Code action and real Cloud verdict in Mac incident.
- [ ] One harmless verified local deny execution test, clearly distinguished from Claude inference.
- [ ] Cloud privacy/evaluation limitations and egress preview.
- [ ] A genuine alpha access form/invite issuance process and response contact.
- [ ] Founder identities, roles and company-domain email present/consistent; use verified data only.
- [ ] At least one actual live model request recorded in a TraceRook-controlled Anthropic Console account; ideally repeatable.
- [ ] Product screenshots/videos never show fixture usage as real or suggest unsupported host coverage.
- [ ] Program application submitted using correct company information, not presumed accepted.

## 10. How to apply without waiting for deployment

The Startup application is a separate founder action: use a company email that matches `tracerook.dev` and a Console account, and submit the **truthful current-stage version** above. Meanwhile build MVP3's real hosted Claude path. If the team is contacted for further review, send the updated evidence and production demo. There is no need to inflate statuses to overcome a supposed chicken-and-egg barrier; the current program openly allows early-stage companies to apply.

**Official program:** https://claude.com/programs/startups  
**Claude Console:** https://platform.claude.com/  
**Source project:** https://github.com/kleprevost/tracerook  
**Product site:** https://tracerook.dev/

## 11. Metrics to track honestly (not marketing claims yet)

| Metric | Collection method | How to explain to reviewers |
|---|---|---|
| Real Claude Cloud requests | TraceRook server receipt ↔ Anthropic upstream request ID | Demonstrates authentic API usage in product workflow |
| Tokens/model and error rate | Returned first-party usage + server statuses | Supports planned operating cost and reliability |
| Redaction blocks | Local preflight reason codes only | Shows proactive privacy boundary; no stored secret content |
| Warning/review rates | Sanitized decision categories and local actions | Indicates product usage, not guaranteed security accuracy |
| Verified blocked actions | Local hook deny + absent harmless sentinel | Demonstrates supported gate effectiveness on tested host paths |
| Synthetic evaluation quality | Reproducible labeled corpus of ≥60 cases | Evidence of development rigor, not real-world breach prevention rate |
| Alpha invite usage | Server-enrolled devices and active-analyzed users | Use exact real counts with privacy protections |

**Final rule:** Let the real release, actual API usage and specific verified host paths be more persuasive than a claim of broad production readiness. Honest demonstration is an asset during security-product diligence.

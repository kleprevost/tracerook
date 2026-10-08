# Security

## Reporting a vulnerability

Report vulnerabilities privately through [GitHub security advisories](https://github.com/kleprevost/tracerook/security/advisories/new) rather than a public issue. Include the affected component (app, service, hook bridge, TraceRook Cloud or website), reproduction steps and the impact you observed. Leave secrets, prompts and private source out of reports.

## Security model

- **Where TraceRook acts.** TraceRook reviews the tool calls that Claude Code routes through its synchronous `PreToolUse` hook. Commands you type yourself and child processes started by a command you approved run outside that review.
- **Who decides.** Enabled critical rules with concrete local evidence block automatically. Claude's verdicts are advisory: they can request a human review, never grant a permission, and never override a critical local rule.
- **Allow once.** Clears TraceRook's review for one exact pending invocation. Claude Code's own permission prompts still apply.
- **Approvals.** The background service owns pending reviews, deadlines and expiry. Reviews are bound to the action fingerprint and invocation nonce, resolve exactly once, and only the signed app can resolve them over authenticated XPC. The hook socket has no approval or trust methods. A service restart never restores a pending review as approved.
- **Cloud.** Device credentials are opaque 256-bit tokens checked by keyed digest. Requests are strictly parsed, re-scanned for secrets and bounded in size and time. Model output must match a strict schema, the expected model and first-party provenance before it is accepted.
- **Data.** Raw commands, paths, code, file contents and transcripts stay on the Mac. See [docs/PRIVACY.md](docs/PRIVACY.md).

The full trust-boundary breakdown is in [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md).

# Local policy engine — initial implementation evidence

`LocalPolicy.evaluate` now inspects bounded original shell and structured file inputs. Its 50-case shell corpus plus structured patch/configuration and symlink/scope tests pass locally. The full suite passed with 53 test functions before client API preparation.

Implemented checks include concrete credential transfer, recursive destructive targets, security-hook deletion/disabling, sensitive and environment-file access, privilege requests, fetch-and-execute and encoded pipelines, out-of-task publication, repeated denial, and uncertain inspection. Quoting, wrappers, comments, static nested shells, pipe continuity, scoped cleanup, structured Write/Edit and patch inputs have positive and near-miss fixtures. Uninspectable grammar produces reviewable uncertainty rather than a safe verdict.

This is an initial deterministic engine, **not completed MVP2.4 or operational enforcement**. The hook CLI remains disabled and the service's transport probe still returns `policy_unavailable`. No real host was intercepted or denied by these tests. Original input is transient; rule evidence contains bounded categorical summaries.

Remaining work includes task-anchor and repository-instruction families, broader tool/grammar coverage, integration into the shared fallback/decision engine, service-owned live review, and actual host canary denial and native-permission tests. The bounded parser is not a shell interpreter or a sandbox. Passing this corpus does not establish comprehensive detection or measured efficacy.

Evidence: `Tests/RulesTests/PolicyTests.swift`; local logs under ignored `build/mvp2-live/rules-tests.log`. No agent configuration changed.

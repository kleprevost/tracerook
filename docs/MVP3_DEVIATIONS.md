# MVP3 deviations and unresolved baseline assumptions

Reviewed **2026-10-08**, PR 0, source `e2615b8e9f3b47e4330360a0b77f5dc97f2dfaf7`. Authority: [MVP3 specification](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Claude_Cloud_Alpha_Spec.md) and [handoff](../TraceRook_MVP3_Complete_Package/TraceRook_MVP3_Coding_Agent_Handoff.md).

**No architecture or security requirement is waived.** PR 0 introduces no runtime substitution. The original package is preserved unchanged. This record distinguishes observed gaps from permission to fabricate or rebuild shipping behavior.

| Assumption / constraint | Actual observation | Required treatment |
|---|---|---|
| Package reports completed/deployed MVP2 runtime | Accessible main is a foundation preview; no separate tag/release/source/install discovered; current service/bridge refuse ordinary operation | Keep shipping identity unresolved and obtain actual SHA/app. Audit only the available preview; do not label it the shipping release or downgrade an unavailable external release |
| Existing BYOK / service / SQLite / rules are available to extend | Their runtime implementations are absent in the inspected checkout | Do not claim preservation tests for nonexistent source. Prepare isolated Cloud contracts behind fake transport; real integration requires the supplied runtime or separately reviewed MVP2 completion |
| Current flat Cloud DTOs match MVP3's canonical live protocol | Old fixture/future contracts have different fields and can be constructed from demo input | Preserve readers; plan additive strict live Cloud v1 types and an explicit projection/origin boundary, rather than silently changing the old schema |
| Native signed/notarized app can be regression-tested | Only ad-hoc local bundles found; Gatekeeper rejects them; no stapled ticket; full Xcode and Developer ID unavailable | Record failed development distribution assessment and not-run shipping acceptance separately. Do not weaken caller checks, Gatekeeper or notarization requirements |
| Backend default stack and model/cost assumptions are available | No Cloud API implementation/deployment verified; proposed model/API terms and infrastructure compatibility have not been release-validated | Verify official platform/model behavior during the relevant implementation PR. No substitute model, paid plan, spend authorization or API readiness is inferred from the spec |
| Default Cloud architecture vs user's Cloudflare free-tier requirement | Free-tier requirement remains active; PR 0 provisions nothing | Verify free-tier support and limits before infrastructure changes. Document an actual incompatibility and reviewed equivalent if necessary; no automatic paid upgrade |

These are baseline observations and future dependencies, not implemented alternative functionality. [Acceptance](MVP3_ACCEPTANCE.md) records exact passed, failed and not-run checks. Platform-driven implementation deviations must be appended with official/API evidence and regression results when they actually arise.

## User-directed local demonstration scope

After the baseline audit, the user explicitly requested a locally running mock backend connected to the client, with no backend deployment. The supplied Python/FastAPI backend was hardened by a Sol subagent; [connected API evidence](LOCAL_API_DEMO_EVIDENCE.md) records the working local subset. A distinct mock namespace, mandatory simulation field and fixture provenance are implemented so sample requests cannot reach the production analysis route. The offline Cloud Demo remains unchanged. The synthetic types are not live providers or host authorization inputs.

This is a scope clarification authorized by the user, not a platform-driven waiver of the hosted alpha. Production authentication, privacy preflight, actual Anthropic inference, hosted quota/retention and live enforcement requirements remain open. No mock result may be described as real Claude analysis or proprietary backend evidence.

## Haiku 5.5 and provided local backend

The user explicitly selected Haiku 5.5 for Anthropic testing. The separate legacy analyzer and opt-in diagnostic use `claude-haiku-5-5` instead of the MVP3 specification's proposed Sonnet default. One bounded real diagnostic validated this exact model with 798 input/178 output tokens in 3,006 ms. Following [Anthropic's migration guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide), Haiku uses low effort, structured output, no sampling overrides and no server-fallback beta; refusal, malformed output and mismatched models fail without retries or fallbacks. The remaining hosted MVP3 model/cost acceptance has not been met. This is a user-directed model change, not evidence the specification was platform-incompatible.

The supplied Python/FastAPI stack is retained for the user's loopback demonstration instead of provisioning the proposed hosted stack. The default mock factory does not instantiate the legacy inference/database path. Native demo credentials are memory-only and available only in explicit developer mode; they are not production Keychain credentials. Mock budgets are narrowed to 1–4 seconds inside the five-second XPC budget, and payloads are fixed synthetic contexts only. No production auth, privacy or deployment requirement is waived by these local choices.

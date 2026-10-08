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

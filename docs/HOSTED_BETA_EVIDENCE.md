# Hosted beta verification, 2026-10-08

The production Worker is reachable at `https://api.tracerook.dev`. The parent enabled deployment version `8e12a88d-b314-47a0-a2f1-34d9c5bf4723` and authorized a maximum of ten hosted analysis attempts. This document distinguishes provisioning, authenticated readiness, and genuine inference success.

## Operator scripts

`node cloud/scripts/provision-beta.mjs --origin https://api.tracerook.dev` creates one testing account and one-use invitation in production D1 using an HMAC digest, enrolls one device through the real endpoint, and stores the returned credential and beta access code in ignored `build/deployment-private` files with mode 0600 and directory mode 0700. It never reads the Anthropic key, touches Keychain, deploys, or changes Worker configuration. Console output contains generated identifiers and status counts only. The digest secret is read in memory from the existing private digest file; SQL contains identifiers and an irreversible invitation digest, and temporary SQL is deleted afterward.

The native probe consumes the **flat** `beta-credential.json` with exactly `schema_version`, `device_id`, `device_token`, `token_expires_at`, and `limits`. The separate operator manifest is `beta-provision-state.json`; the private entry code is `beta-access-code.txt`. No private content is committed or printed. The `trb_` encoding sorts all JSON keys recursively, emits explicit null limit fields, normalizes UUID to uppercase like Foundation UUID Codable, and uses unpadded base64url. The operator manifest is not a native credential DTO.

A failed initial provisioning run exposed Wrangler's status-line prefix before its `--file --json` output. After correcting parsing, `--resume true` recovered the **same** generated account and invitation with idempotent D1 inserts. It did not generate another account or automatically replay enrollment. The final provisioning and enrollment succeeded.

`node cloud/scripts/hosted-smoke.mjs --confirmed-enabled true --requests 10` verifies real health, authenticated capabilities and usage, then issues at most ten fresh request IDs with coarse privacy-safe context. It stops on the first failure, performs no provider retry, validates response binding/provenance/usage, and checks successful requests against D1 metadata receipts containing upstream request IDs. Public console output contains IDs, counts, token totals and a bounded error code; it never prints tokens or model rationale. Private evidence contains bounded receipt metadata and usage counters, with no credential or raw transcript.

Node resolves only the fixed `api.tracerook.dev` hostname through DNS 1.1.1.1 to work around the machine's stale default resolver. Requests retain normal HTTPS certificate verification and SNI for that hostname. The scripts do not accept an IP origin, weaken TLS, or replace the native contract origin.

## Executed results

| Gate | Result | Evidence |
|---|---|---|
| Script syntax | passed | Both Node scripts parse |
| Production account and device enrollment | passed | One account, one enrolled device; secret files saved privately |
| Flat native credential shape | passed | Exactly five top-level contract fields; operator wrapper saved separately |
| Foundation sorted JSON/base64url parity | passed | Actual private credential matched an independent Foundation UUID Codable + JSONEncoder sortedKeys/withoutEscapingSlashes/base64url check; stdin-only, boolean-only output |
| Real production health | passed | `/v1/healthz` returned schema 1, status ok |
| Authenticated capabilities | passed | Real bearer accepted; provider Anthropic, cloud transport, expected model, analysis enabled |
| Genuine hosted analysis | failed | First request returned HTTP 503 `provider_unavailable`; zero validated successful responses |
| Remaining nine analysis attempts | not run | Stop-on-first-failure rule; no automatic retry or additional spend |
| Verified real upstream receipts | zero | No matching successful analysis receipts found in D1 |
| Native host → hosted provider → incident | not run by this script | Separate parent-owned native probe/host integration gate |

The smoke inputs are coarse test cases, not real host transcripts and not a security classification calibration dataset. No protection efficacy, tester count, provider partnership or genuine inference success is inferred from enrollment, enabled capabilities, local model doubles, or the failed upstream attempt. A `provider_unavailable` response does not establish whether Anthropic accepted/billed an ambiguous upstream request; reserved usage counters remain the conservative authority until the parent investigates. Credentials stay private and the Worker owns the Anthropic secret.

## Provider failure diagnostic patch, pending deployment

The actual 503 did not disclose its upstream stage. `cloud/src/anthropic.ts` now emits a bounded operator diagnostic containing only a constant validation stage and numeric upstream HTTP status. It never logs provider response bodies, submitted context, credentials, request headers, or exception text. A meaningful integration test verifies both HTTP 400 diagnostics and empty-category validation failure diagnostics exclude private canaries and device credentials. TypeScript checking passed and all 56 cloud tests passed after this patch.

The response schema also now requires `category.minItems: 1`, matching the already enforced 1–2-category validator. [Anthropic's structured-output documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) explicitly supports `minItems` 0 or 1. The validator remains strict; no invalid response is converted into an allow verdict. This fixes a proven schema consistency gap without asserting it caused the first hosted failure. Another hosted attempt is held until the parent deploys the diagnostic patch and coordinates observation.

## Second bounded hosted attempt and actual runtime diagnosis

After the parent deployed diagnostic version `dcef0c8f-929e-40d5-b17d-a31f8ce54ad7`, exactly one additional analysis was sent and stopped with HTTP 503 `provider_unavailable`, zero validated success and zero successful upstream receipts. Total script analysis attempts to this point: **two**, with no retries. The parent's filtered live tail observed only `stage=request`, `upstream_status=0`, and a non-aborted controller: failure before any provider HTTP response. The category-schema consistency fix was therefore not the cause of that observed failure.

An independent **real workerd Request constructor** test then reproduced the platform error for `redirect: "error"`, without making a network call or using the fetch double. The exact error was safely classified as `TypeError/invalid_redirect`. Tested versions: Wrangler `4.148.0`, workerd `1.20261006.1`. [Cloudflare's current Request documentation](https://developers.cloudflare.com/workers/runtime-apis/request/) lists `error` among redirect options; the actual installed runtime rejects it. This is an explicit runtime/documentation deviation.

The provider transport now uses `redirect: "manual"`; its existing exact-200 status requirement rejects every 3xx without following or retrying. A real Request constructor test validates the selected request option, and regression checks cover 301/302/303/307/308. This maintains the fixed Anthropic endpoint and prevents credential forwarding to redirect targets. TypeScript checking and all **59 cloud tests** passed after this change. Another genuine request remains held until the parent deploys this fix and authorizes the next bounded canary.

Operator diagnostics now also emit only a whitelisted error type, finite known-error classification, and a boolean key-format check. Unknown exception text is never emitted. Tests verify unknown errors and private canaries remain absent from diagnostics. No provider bodies, API keys, request headers, or submitted context are logged.

## Third bounded request: genuine inference and matching upstream receipt passed

After deployment `bb2cd48a-2471-43a1-a239-66864af7ebed` incorporated the verified manual-redirect fix, the third analysis attempt returned a valid genuine response. Request `16e9393a-a8dc-48cd-baae-c7cf4d0cc889`, trace `tr_cf53ad3f-f529-4a76-b04a-a0de17e7d8f5`, and upstream request `req_011CfqK6x4DNn5n4y43mkzc3` matched production D1 metadata for the expected Anthropic model. Returned actual usage: **931 input tokens, 231 output tokens**, one billed unit. Advisory severity was `low`, recommendation `allow`; no model rationale is included in this evidence.

The initial receipt-verification step failed because Wrangler's `--file` path imports SQL and returns import statistics instead of SELECT row data. Read-only metadata verification was corrected to use `--command SELECT` containing only a generated account identifier. It then matched request, analysis, trace, model and actual token totals without sending another analysis. `--verify-receipts true` performs this metadata-only check; it cannot turn an unsuccessful analysis into a success. Subsequent actual runs archive bounded private evidence alongside the latest summary.

Current script totals: **three actual analysis attempts, one genuine validated response with one independently matched upstream receipt, two failed pre-response attempts, zero retries**. The remaining seven requests remain on hold for the parent. The earlier table records the initial attempt and is historical; this section records the later executed correction and success. This is genuine server-owned first-party inference with metadata evidence, separate from the local Claude model doubles and the parent-owned native host-to-cloud gate.

## Parent host-to-cloud attempt and harness deadline correction

The parent observed a genuine native Settings “Validated Claude response” timestamp `2026-10-08T19:22:39.729Z` after a real installed Claude Bash event reached the enrolled signed service. However, the hosted callback attempt captured only one completed callback: the harness's earlier ten-second hook limit could terminate the benign callback before the helper's eighty-second deadline and permit host fail-open behavior. That run is **inconclusive for full host enforcement**, even though the separate native provider receipt was real. It must not be promoted to a successful security gate.

The deny-case harness now gives the hook 85 seconds around the helper's 80-second limit and requires **exactly two completed callbacks**, including the benign callback's exit-zero/empty-stdout native permission-preserving result. Benign sentinel execution alone cannot satisfy that gate. Actual canary denial and absent denial sentinel are still required. Timeout/outage cases retain their ten-second hook timeout. `--cloud-host` labels a parent-coordinated enrolled-service run, but does not itself certify hosted inference; native and upstream receipt evidence must establish that separately. No additional host or analysis request was issued while applying this correction.

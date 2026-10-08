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

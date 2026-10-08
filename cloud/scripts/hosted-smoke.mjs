#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import {
  options,
  exact,
  privateDirectory,
  privateWrite,
  validateCredential,
  requestJSON,
  d1,
} from "./provision-beta.mjs";
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
function receipt(value, request) {
  exact(value, [
    "schema_version",
    "request_id",
    "analysis_id",
    "verdict",
    "provenance",
    "usage",
    "server_elapsed_ms",
  ]);
  exact(value.provenance, [
    "provider",
    "transport",
    "model_id",
    "policy_version",
    "prompt_version",
    "trace_id",
    "validated_at",
  ]);
  exact(value.usage, ["input_tokens", "output_tokens", "billed_units"]);
  exact(value.verdict, [
    "schema_version",
    "category",
    "severity",
    "confidence",
    "suspicious",
    "rationale",
    "evidence",
    "recommended_action",
    "session_drift",
    "limitations",
  ]);
  const p = value.provenance,
    v = value.verdict,
    u = value.usage,
    age = Date.now() - Date.parse(p.validated_at);
  if (
    value.schema_version !== 1 ||
    value.request_id.toLowerCase() !== request.request_id.toLowerCase() ||
    !uuid.test(value.analysis_id.slice(3)) ||
    !value.analysis_id.startsWith("an_") ||
    !p.trace_id.startsWith("tr_") ||
    !uuid.test(p.trace_id.slice(3))
  )
    throw new Error("receipt_binding_invalid");
  if (
    p.provider !== "anthropic" ||
    p.transport !== "tracerook_cloud" ||
    p.model_id !== "claude-haiku-5-5" ||
    p.policy_version !== 1 ||
    p.prompt_version !== "risk-eval-v1" ||
    !(age >= -30000 && age <= 600000)
  )
    throw new Error("provenance_invalid");
  if (
    !Number.isInteger(value.server_elapsed_ms) ||
    value.server_elapsed_ms < 0 ||
    value.server_elapsed_ms > request.deadline_ms ||
    u.billed_units !== 1 ||
    !Number.isInteger(u.input_tokens) ||
    u.input_tokens < 1 ||
    u.input_tokens > 16384 ||
    !Number.isInteger(u.output_tokens) ||
    u.output_tokens < 1 ||
    u.output_tokens > 1024
  )
    throw new Error("usage_invalid");
  if (
    v.schema_version !== 1 ||
    !Array.isArray(v.category) ||
    v.category.length < 1 ||
    v.category.length > 2 ||
    new Set(v.category).size !== v.category.length ||
    v.category.some(
      (c) => !["unsafe_action", "agent_misbehavior"].includes(c),
    ) ||
    !["critical", "high", "medium", "low", "unknown"].includes(v.severity) ||
    !Number.isFinite(v.confidence) ||
    v.confidence < 0 ||
    v.confidence > 1 ||
    typeof v.suspicious !== "boolean" ||
    typeof v.session_drift !== "boolean" ||
    !["allow", "warn_allow", "request_approval"].includes(
      v.recommended_action,
    ) ||
    typeof v.rationale !== "string" ||
    Buffer.byteLength(v.rationale) > 2048
  )
    throw new Error("verdict_invalid");
  for (const name of ["evidence", "limitations"])
    if (
      !Array.isArray(v[name]) ||
      v[name].length > 10 ||
      v[name].some((s) => typeof s !== "string" || Buffer.byteLength(s) > 512)
    )
      throw new Error("verdict_invalid");
  return {
    request_id: value.request_id,
    analysis_id: value.analysis_id,
    trace_id: p.trace_id,
    model_id: p.model_id,
    validated_at: p.validated_at,
    input_tokens: u.input_tokens,
    output_tokens: u.output_tokens,
    billed_units: u.billed_units,
    server_elapsed_ms: value.server_elapsed_ms,
    severity: v.severity,
    recommendation: v.recommended_action,
  };
}
function upstreamReceipts(safe, accountID) {
  const rows = d1(
    `SELECT request_id,analysis_id,model_id,upstream_request_id,trace_id,input_tokens,output_tokens,elapsed_ms FROM analysis_receipts WHERE account_id='${accountID}' ORDER BY created_at DESC LIMIT 20;`,
    "production",
    true,
  ).flatMap((result) => result.results || []);
  const matched = safe
    .map((receipt) =>
      rows.find(
        (row) =>
          typeof row.request_id === "string" &&
          row.request_id.toLowerCase() === receipt.request_id.toLowerCase(),
      ),
    )
    .filter(Boolean);
  if (
    matched.length !== safe.length ||
    matched.some(
      (row) =>
        !/^req_[A-Za-z0-9_-]{1,150}$/.test(row.upstream_request_id) ||
        row.model_id !== "claude-haiku-5-5" ||
        !safe.some(
          (receipt) =>
            receipt.analysis_id === row.analysis_id &&
            receipt.trace_id === row.trace_id &&
            receipt.input_tokens === row.input_tokens &&
            receipt.output_tokens === row.output_tokens,
        ),
    )
  )
    throw new Error("upstream_receipt_mismatch");
  return matched;
}
async function main() {
  const args = options(process.argv.slice(2));
  if (args["confirmed-enabled"] !== "true")
    throw new Error("operator_enable_confirmation_required");
  const count = Number(args.requests || 10);
  if (!Number.isInteger(count) || count < 1 || count > 10)
    throw new Error("request_bound_invalid");
  const path = join(privateDirectory, "beta-provision-state.json");
  if ((statSync(path).mode & 0o077) !== 0)
    throw new Error("credential_file_permissions");
  const state = JSON.parse(readFileSync(path, "utf8"));
  validateCredential(state.credential);
  if (state.phase !== "enrolled" || !uuid.test(state.account_id))
    throw new Error("enrollment_required");
  const origin = state.origin,
    token = state.credential.device_token;
  if (args["verify-receipts"] === "true") {
    const path = join(privateDirectory, "hosted-smoke-evidence.json");
    const evidence = JSON.parse(readFileSync(path, "utf8"));
    if (
      !Array.isArray(evidence.receipts) ||
      evidence.receipts.length === 0 ||
      ![
        null,
        "usage_or_receipt_verification_failed",
        "upstream_receipt_mismatch",
      ].includes(evidence.failure)
    )
      throw new Error("successful_prior_analysis_required");
    evidence.upstream_receipts = upstreamReceipts(
      evidence.receipts,
      state.account_id,
    );
    evidence.usage_after = await requestJSON(
      origin,
      "GET",
      "/v1/usage",
      undefined,
      token,
    );
    evidence.failure = null;
    privateWrite(path, evidence);
    console.log(
      JSON.stringify({
        kind: "hosted_receipt_metadata_verified",
        additional_analysis_requests: 0,
        verified_upstream_receipts: evidence.upstream_receipts.length,
        input_tokens: evidence.receipts.reduce(
          (sum, item) => sum + item.input_tokens,
          0,
        ),
        output_tokens: evidence.receipts.reduce(
          (sum, item) => sum + item.output_tokens,
          0,
        ),
        request_ids: evidence.receipts.map((item) => item.request_id),
        upstream_request_ids: evidence.upstream_receipts.map(
          (item) => item.upstream_request_id,
        ),
      }),
    );
    return;
  }

  const health = await requestJSON(origin, "GET", "/v1/healthz");
  exact(health, ["schema_version", "status"]);
  if (health.schema_version !== 1 || health.status !== "ok")
    throw new Error("health_invalid");
  const capabilities = await requestJSON(
    origin,
    "GET",
    "/v1/capabilities",
    undefined,
    token,
  );
  exact(capabilities, [
    "schema_version",
    "provider",
    "transport",
    "model_id",
    "analysis_enabled",
    "privacy_policy_version",
    "retention",
    "limits",
  ]);
  if (
    capabilities.schema_version !== 1 ||
    capabilities.provider !== "anthropic" ||
    capabilities.transport !== "tracerook_cloud" ||
    capabilities.model_id !== "claude-haiku-5-5" ||
    capabilities.analysis_enabled !== true ||
    capabilities.privacy_policy_version !== 2
  )
    throw new Error("inference_not_enabled");
  const before = await requestJSON(
    origin,
    "GET",
    "/v1/usage",
    undefined,
    token,
  );
  const safe = [];
  let attempted = 0,
    failure;
  // Deliberately coarse inputs, not host transcripts or a calibration/effectiveness
  // dataset. Every request has a fresh UUID; no replay and no provider retry.
  const actions = ["shell_exec", "file_read", "file_write", "other", "network"];
  const signals = [
    [],
    ["sensitive_config_read"],
    ["writes_repo_config"],
    ["task_mismatch"],
    ["outbound_transfer"],
    [],
    ["untrusted_instructions"],
    ["privilege_change"],
    ["destructive_delete"],
    ["session_drift"],
  ];
  for (let i = 0; i < count; i++) {
    const action = actions[i % actions.length];
    const request = {
      schema_version: 1,
      request_id: randomUUID(),
      device_id: state.credential.device_id,
      session_pseudonym: randomUUID(),
      source: "claude_code",
      event: "pre_tool_use",
      deadline_ms: 12000,
      privacy_policy_version: 2,
      context: {
        task_summary: "Validate a project with tests",
        action_class: action,
        proposed_action_summary:
          "Perform a locally classified project operation with raw arguments omitted",
        local_signals: signals[i],
        recent_activity: [],
        contains_code_excerpts: false,
      },
    };
    attempted++;
    try {
      safe.push({
        ...receipt(
          await requestJSON(
            origin,
            "POST",
            "/v1/analysis",
            request,
            token,
            14000,
          ),
          request,
        ),
        case_index: i + 1,
      });
    } catch (error) {
      failure = /^[a-z0-9_]{1,80}$/.test(error.message)
        ? error.message
        : "analysis_failed";
      break;
    }
  }
  let after,
    upstream = [];
  try {
    after = await requestJSON(origin, "GET", "/v1/usage", undefined, token);
    upstream = upstreamReceipts(safe, state.account_id);
  } catch {
    failure ||= "usage_or_receipt_verification_failed";
  }
  const result = {
    kind: "genuine_hosted_anthropic_smoke",
    origin,
    account_id: state.account_id,
    device_id: state.credential.device_id,
    attempted_requests: attempted,
    validated_successes: safe.length,
    no_retries: true,
    maximum_requests: 10,
    capabilities_enabled: true,
    usage_before: before,
    usage_after: after || null,
    receipts: safe,
    upstream_receipts: upstream,
    failure: failure || null,
  };
  privateWrite(
    join(privateDirectory, "hosted-smoke-run-" + randomUUID() + ".json"),
    result,
    true,
  );
  privateWrite(join(privateDirectory, "hosted-smoke-evidence.json"), result);
  console.log(
    JSON.stringify({
      kind: result.kind,
      attempted_requests: attempted,
      validated_successes: safe.length,
      verified_upstream_receipts: upstream.length,
      input_tokens: safe.reduce((n, r) => n + r.input_tokens, 0),
      output_tokens: safe.reduce((n, r) => n + r.output_tokens, 0),
      request_ids: safe.map((r) => r.request_id),
      trace_ids: safe.map((r) => r.trace_id),
      upstream_request_ids: upstream.map((r) => r.upstream_request_id),
      failure: failure || null,
    }),
  );
  if (failure || safe.length !== count) process.exitCode = 1;
}
main().catch((error) => {
  console.error(
    JSON.stringify({
      kind: "hosted_smoke_failed",
      code: /^[a-z0-9_]{1,80}$/.test(error.message)
        ? error.message
        : "operator_error",
    }),
  );
  process.exitCode = 1;
});

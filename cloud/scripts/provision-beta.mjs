#!/usr/bin/env node
import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  chmodSync,
  statSync,
  mkdtempSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import https from "node:https";
import { Resolver } from "node:dns";
export const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
export const privateDirectory = join(root, "build/deployment-private");
export function canonical(value) {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value !== null && typeof value === "object")
    return (
      "{" +
      Object.keys(value)
        .sort()
        .map((k) => JSON.stringify(k) + ":" + canonical(value[k]))
        .join(",") +
      "}"
    );
  return JSON.stringify(value);
}
export function exact(value, keys) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).sort().join("|") !== [...keys].sort().join("|")
  )
    throw new Error("invalid_response_shape");
}
export function validateCredential(value) {
  exact(value, [
    "schema_version",
    "device_id",
    "device_token",
    "token_expires_at",
    "limits",
  ]);
  exact(value.limits, [
    "evaluations_per_day",
    "input_tokens_per_day",
    "output_tokens_per_day",
    "devices_per_account",
  ]);
  if (
    value.schema_version !== 1 ||
    !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
      value.device_id,
    ) ||
    !/^[A-Za-z0-9_-]{43,256}$/.test(value.device_token)
  )
    throw new Error("invalid_credential");
  const lifetime = Date.parse(value.token_expires_at) - Date.now();
  if (
    !(lifetime > 0 && lifetime <= 31 * 86400000) ||
    !Number.isInteger(value.limits.devices_per_account) ||
    value.limits.devices_per_account < 1 ||
    value.limits.devices_per_account > 3
  )
    throw new Error("invalid_credential");
  for (const name of [
    "evaluations_per_day",
    "input_tokens_per_day",
    "output_tokens_per_day",
  ])
    if (
      value.limits[name] !== null &&
      (!Number.isInteger(value.limits[name]) ||
        value.limits[name] < 0 ||
        value.limits[name] > 1e9)
    )
      throw new Error("invalid_limits");
}
export function accessCode(credential) {
  validateCredential(credential);
  // Foundation UUID Codable emits uppercase hex; WireCodec sorts keys recursively
  // and does not escape slashes. All credential strings are ASCII.
  return (
    "trb_" +
    Buffer.from(
      canonical({
        ...credential,
        device_id: credential.device_id.toUpperCase(),
      }),
    ).toString("base64url")
  );
}
export function privateWrite(path, value, exclusive = false) {
  if (!resolve(path).startsWith(privateDirectory + "/"))
    throw new Error("private_path_required");
  mkdirSync(privateDirectory, { recursive: true, mode: 0o700 });
  chmodSync(privateDirectory, 0o700);
  writeFileSync(
    path,
    typeof value === "string" ? value : JSON.stringify(value, null, 2) + "\n",
    { mode: 0o600, flag: exclusive ? "wx" : "w" },
  );
  chmodSync(path, 0o600);
}
export function options(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i]?.startsWith("--") || argv[i + 1] === undefined)
      throw new Error("invalid_arguments");
    out[argv[i].slice(2)] = argv[i + 1];
  }
  return out;
}
export async function requestJSON(
  origin,
  method,
  path,
  body,
  token,
  timeout = 15000,
) {
  const base = new URL(origin);
  if (
    base.protocol !== "https:" ||
    base.hostname !== "api.tracerook.dev" ||
    base.port ||
    base.pathname !== "/" ||
    base.search ||
    base.hash
  )
    throw new Error("fixed_origin_required");
  const resolver = new Resolver();
  resolver.setServers(["1.1.1.1"]);
  // Resolve only the fixed hostname via public DNS; HTTPS keeps normal certificate
  // verification and SNI for api.tracerook.dev. No IP-origin or TLS bypass.
  const lookup = (host, settings, done) => {
    if (host !== base.hostname) return done(new Error("unexpected_host"));
    resolver.resolve4(host, (err, addresses) =>
      err
        ? done(err)
        : settings?.all
          ? done(
              null,
              addresses.map((address) => ({ address, family: 4 })),
            )
          : done(null, addresses[0], 4),
    );
  };
  return await new Promise((resolveResult, reject) => {
    const bytes = body === undefined ? undefined : Buffer.from(canonical(body));
    const headers = { Accept: "application/json" };
    if (bytes) {
      headers["Content-Type"] = "application/json";
      headers["Content-Length"] = bytes.length;
    }
    if (token) headers.Authorization = "Bearer " + token;
    const req = https.request(
      new URL(path, base),
      { method, headers, lookup, servername: base.hostname },
      (res) => {
        const pieces = [];
        let size = 0;
        res.on("data", (chunk) => {
          size += chunk.length;
          if (size > 32768) req.destroy(new Error("response_oversized"));
          else pieces.push(chunk);
        });
        res.on("error", () => reject(new Error("network_response_failed")));
        res.on("end", () => {
          clearTimeout(timer);
          try {
            if (
              !(res.headers["content-type"] || "").startsWith(
                "application/json",
              )
            )
              throw new Error("non_json_response");
            const value = JSON.parse(Buffer.concat(pieces).toString("utf8"));
            if (res.statusCode !== 200) {
              const code =
                typeof value.error?.code === "string" &&
                /^[a-z_]{1,40}$/.test(value.error.code)
                  ? value.error.code
                  : "http_error";
              reject(new Error("http_" + res.statusCode + "_" + code));
              return;
            }
            resolveResult(value);
          } catch {
            reject(new Error("response_validation_failed"));
          }
        });
      },
    );
    const timer = setTimeout(
      () => req.destroy(new Error("request_deadline")),
      timeout,
    );
    req.on("error", () => {
      clearTimeout(timer);
      reject(new Error("network_request_failed"));
    });
    req.end(bytes);
  });
}
export function d1(sql, environment = "production", readOnly = false) {
  if (readOnly && !/^SELECT\s/i.test(sql.trim()))
    throw new Error("read_only_query_required");
  const directory = mkdtempSync(join(tmpdir(), "tracerook-beta-sql-"));
  try {
    const file = join(directory, "operation.sql");
    writeFileSync(file, sql, { mode: 0o600 });
    const result = spawnSync(
      "npx",
      [
        "--no-install",
        "wrangler",
        "d1",
        "execute",
        "tracerook-cloud-" + environment,
        "--env",
        environment,
        "--remote",
        "--json",
        readOnly ? "--command" : "--file",
        readOnly ? sql : file,
      ],
      {
        cwd: join(root, "cloud"),
        encoding: "utf8",
        timeout: 60000,
        maxBuffer: 2e6,
        shell: false,
      },
    );
    if (result.status !== 0) throw new Error("d1_operation_failed");
    // Wrangler --file prepends an import status line even with --json.
    const first = result.stdout.indexOf("[\n");
    const parsed = JSON.parse(
      first >= 0 ? result.stdout.slice(first) : result.stdout,
    );
    if (!Array.isArray(parsed) || parsed.some((r) => r.success !== true))
      throw new Error("d1_operation_failed");
    return parsed;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
async function main() {
  const args = options(process.argv.slice(2)),
    origin = args.origin || "https://api.tracerook.dev";
  const statePath = join(privateDirectory, "beta-provision-state.json");
  const secretPath = join(privateDirectory, "digest-secrets.json");
  if ((statSync(secretPath).mode & 0o077) !== 0)
    throw new Error("digest_file_permissions");
  const key = JSON.parse(readFileSync(secretPath, "utf8")).production;
  if (typeof key !== "string" || key.length < 32)
    throw new Error("digest_secret_invalid");
  const now = Date.now();
  const state =
    args.resume === "true"
      ? JSON.parse(readFileSync(statePath, "utf8"))
      : {
          schema_version: 1,
          origin,
          account_id: randomUUID(),
          invite_id: randomUUID(),
          device_id: randomUUID(),
          invitation: "tri_" + randomBytes(32).toString("hex"),
          phase: "prepared",
        };
  if (
    state.origin !== origin ||
    !["prepared", "invite_issued"].includes(state.phase) ||
    !/^tri_[a-f0-9]{64}$/.test(state.invitation)
  )
    throw new Error("invalid_resume_state");
  for (const id of [state.account_id, state.invite_id, state.device_id])
    if (!/^[a-f0-9-]{36}$/.test(id)) throw new Error("invalid_resume_state");
  const {
    account_id: accountID,
    invite_id: inviteID,
    device_id: deviceID,
    invitation,
  } = state;
  if (args.resume !== "true") privateWrite(statePath, state, true); // Never overwrite a credential.

  const hash = createHmac("sha256", key).update(invitation).digest("hex");
  d1(
    `INSERT OR IGNORE INTO accounts(id,created_at) VALUES('${accountID}',${now});\nINSERT OR IGNORE INTO invites(id,invite_digest,account_id,expires_at,max_uses) VALUES('${inviteID}','${hash}','${accountID}',${now + 7 * 86400000},1);`,
  );
  state.phase = "invite_issued";
  privateWrite(statePath, state);
  const credential = await requestJSON(origin, "POST", "/v1/alpha/enroll", {
    schema_version: 1,
    invitation,
    device_id: deviceID,
    app_version: "0.1.0",
    privacy_policy_version: 2,
  });
  validateCredential(credential);
  if (credential.device_id.toLowerCase() !== deviceID.toLowerCase())
    throw new Error("enrollment_wrong_device");
  state.phase = "enrolled";
  state.credential = credential;
  state.access_code = accessCode(credential);
  delete state.invitation;
  privateWrite(statePath, state);
  privateWrite(join(privateDirectory, "beta-credential.json"), credential);
  privateWrite(
    join(privateDirectory, "beta-access-code.txt"),
    state.access_code + "\n",
  );
  console.log(
    JSON.stringify({
      operation: "beta_provisioned",
      account_id: accountID,
      device_id: deviceID,
      issued_devices: 1,
      credential_stored: true,
      access_code_stored: true,
    }),
  );
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  main().catch((error) => {
    console.error(
      JSON.stringify({
        operation: "beta_provision_failed",
        code: /^[a-z0-9_]{1,80}$/.test(error.message)
          ? error.message
          : "operator_error",
      }),
    );
    process.exitCode = 1;
  });

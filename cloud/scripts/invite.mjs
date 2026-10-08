#!/usr/bin/env node
// Run interactively; never print plaintext invitation to CI logs or persist it.
import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const [environment] = process.argv.slice(2);
if (
  !["staging", "production"].includes(environment) ||
  process.argv.length !== 3 ||
  !process.stdin.isTTY ||
  !process.stdout.isTTY
) {
  process.stderr.write(
    "Run interactively: npm run invite -- staging|production\n",
  );
  process.exit(2);
}
async function hidden() {
  process.stderr.write(
    "AUTH_DIGEST_KEY (hidden; same environment runtime secret): ",
  );
  process.stdin.setRawMode(true);
  process.stdin.resume();
  let value = "";
  return await new Promise((resolve, reject) => {
    const handler = (data) => {
      for (const c of data.toString()) {
        if (c === "\u0003") {
          process.stdin.removeListener("data", handler);
          process.stdin.setRawMode(false);
          process.stdin.pause();
          reject(new Error("cancelled"));
          return;
        }
        if (c === "\r" || c === "\n") {
          process.stdin.removeListener("data", handler);
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.stderr.write("\n");
          resolve(value);
          return;
        }
        if (c === "\u007f") value = value.slice(0, -1);
        else if (c.charCodeAt(0) >= 32 && value.length < 4096) value += c;
      }
    };
    process.stdin.on("data", handler);
  });
}
let directory;
try {
  let key = await hidden();
  if (key.length < 32 || key.length > 4096) throw new Error("invalid secret");
  const invitation = "tri_" + randomBytes(32).toString("hex");
  const digest = createHmac("sha256", key).update(invitation).digest("hex");
  key = "";
  const account = randomUUID(),
    inviteID = randomUUID(),
    created = Date.now(),
    expires = created + 7 * 86400000;
  directory = mkdtempSync(join(tmpdir(), "tracerook-invite-"));
  const path = join(directory, "invite.sql");
  // SQL contains only generated identifiers, digest and timestamps, never invitation/key/email.
  writeFileSync(
    path,
    `INSERT INTO accounts(id,created_at) VALUES('${account}',${created});\nINSERT INTO invites(id,invite_digest,account_id,expires_at,max_uses) VALUES('${inviteID}','${digest}','${account}',${expires},1);\n`,
    { mode: 0o600 },
  );
  const result = spawnSync(
    "npx",
    [
      "--no-install",
      "wrangler",
      "d1",
      "execute",
      `tracerook-cloud-${environment}`,
      "--env",
      environment,
      "--remote",
      "--file",
      path,
    ],
    { stdio: "inherit", shell: false },
  );
  if (result.status !== 0) throw new Error("invitation creation failed");
  process.stdout.write(
    `One-use invitation (expires in 7 days; deliver privately, do not save in logs):\n${invitation}\n`,
  );
} catch {
  process.stderr.write("Invitation was not issued.\n");
  process.exitCode = 1;
} finally {
  if (directory) rmSync(directory, { recursive: true, force: true });
}

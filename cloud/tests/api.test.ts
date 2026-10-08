import { describe, it, expect, vi } from "vitest";
import {
  env,
  SELF,
  runInDurableObject,
  runDurableObjectAlarm,
  abortAllDurableObjects,
} from "cloudflare:test";
import {
  hmac,
  strictJSON,
  analysis,
  canonical,
  digest,
} from "../src/validation";
import { replies, upstreamCalls } from "./setup";
import { MAX_INPUT, MAX_OUTPUT, MODEL, VERDICT_SCHEMA } from "../src/anthropic";
const device = () => crypto.randomUUID();
const verdict = {
  schema_version: 1,
  category: ["unsafe_action"],
  severity: "low",
  confidence: 0.5,
  suspicious: false,
  rationale: "Action serves the task.",
  evidence: [],
  recommended_action: "allow",
  session_drift: false,
  limitations: [],
};
const input = (id: string, request_id = crypto.randomUUID()) => ({
  schema_version: 1,
  request_id,
  device_id: id,
  session_pseudonym: crypto.randomUUID(),
  source: "claude_code",
  event: "pre_tool_use",
  deadline_ms: 9000,
  privacy_policy_version: 2,
  context: {
    task_summary: "Build a checkout button",
    action_class: "shell_exec",
    proposed_action_summary: "Run project tests",
    local_signals: [],
    recent_activity: [],
    contains_code_excerpts: false,
  },
});
async function call(
  path: string,
  body?: unknown,
  bearer?: string,
  headers: Record<string, string> = {},
) {
  return SELF.fetch("https://api.tracerook.dev/v1/" + path, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      ...(body !== undefined ? { "content-type": "application/json" } : {}),
      ...(bearer ? { authorization: "Bearer " + bearer } : {}),
      ...headers,
    },
    body:
      body === undefined
        ? undefined
        : typeof body === "string"
          ? body
          : JSON.stringify(body),
  });
}
async function invitation(maxUses = 1) {
  const account = crypto.randomUUID(),
    invite =
      "tri_" +
      [...crypto.getRandomValues(new Uint8Array(32))]
        .map((x) => x.toString(16).padStart(2, "0"))
        .join(""),
    hash = await hmac(env.AUTH_DIGEST_KEY, invite);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO accounts VALUES(?,?)").bind(
      account,
      Date.now(),
    ),
    env.DB.prepare(
      "INSERT INTO invites(id,invite_digest,account_id,expires_at,max_uses) VALUES(?,?,?,?,?)",
    ).bind(crypto.randomUUID(), hash, account, Date.now() + 86400000, maxUses),
  ]);
  return { account, invite };
}
async function enroll(invite?: string, id = device()) {
  if (!invite) invite = (await invitation()).invite;
  const r = await call("alpha/enroll", {
    schema_version: 1,
    invitation: invite,
    device_id: id,
    app_version: "0.3.0",
    privacy_policy_version: 2,
  });
  expect(r.status).toBe(200);
  return (await r.json()) as any;
}
function upstream(
  body: unknown = {
    model: MODEL,
    stop_reason: "end_turn",
    content: [{ type: "text", text: JSON.stringify(verdict) }],
    usage: { input_tokens: 100, output_tokens: 50 },
  },
  status = 200,
  delay = 0,
) {
  replies.push({
    body: JSON.stringify(body),
    status,
    delay,
    headers: {
      "content-type": "application/json",
      "request-id": "req_test_only_123",
    },
  });
}
const stub = () => env.COORDINATOR.get(env.COORDINATOR.idFromName("alpha-v1"));
async function setConfig(key: string, value: string) {
  await runInDurableObject(stub(), (instance: any) => {
    instance.env[key] = value;
  });
}
describe("real Workers, D1 and SQLite Durable Object API", () => {
  it("health never asserts model readiness and browser/query transport is rejected", async () => {
    expect(await (await call("healthz")).json()).toEqual({
      schema_version: 1,
      status: "ok",
    });
    expect(
      (
        await call("healthz", undefined, undefined, {
          origin: "https://attacker.invalid",
        })
      ).status,
    ).toBe(400);
    expect(
      (await SELF.fetch("https://api.tracerook.dev/v1/healthz?token=x")).status,
    ).toBe(400);
  });
  it("enrolls with only digests persisted and strict nullable limits", async () => {
    const e = await enroll();
    expect(e.device_token).toMatch(/^trd_[a-f0-9]{64}$/);
    expect(e.limits.evaluations_per_day).toBeNull();
    const row = await env.DB.prepare("SELECT * FROM devices").first();
    expect(JSON.stringify(row)).not.toContain(e.device_token);
    expect((await call("usage", undefined, e.device_token)).status).toBe(200);
  });
  it("one invitation redemption under concurrency", async () => {
    const i = await invitation();
    const replies = await Promise.all(
      Array.from({ length: 5 }, () =>
        call("alpha/enroll", {
          schema_version: 1,
          invitation: i.invite,
          device_id: device(),
          app_version: "1",
          privacy_policy_version: 2,
        }),
      ),
    );
    expect(replies.filter((r) => r.status === 200)).toHaveLength(1);
    expect(replies.filter((r) => r.status === 403)).toHaveLength(4);
    expect(
      (await env.DB.prepare("SELECT uses FROM invites").first())?.uses,
    ).toBe(1);
  });
  it("device count bound and invalid invite attempts", async () => {
    const i = await invitation(4);
    await enroll(i.invite);
    await enroll(i.invite);
    await enroll(i.invite);
    expect(
      (
        await call("alpha/enroll", {
          schema_version: 1,
          invitation: i.invite,
          device_id: device(),
          app_version: "1",
          privacy_policy_version: 2,
        })
      ).status,
    ).toBe(403);
  });
  it("requires auth, consent, own device and bounded strictly parsed JSON", async () => {
    const e = await enroll();
    expect((await call("analysis", input(e.device_id))).status).toBe(401);
    expect(
      (await call("analysis", input(device()), e.device_token)).status,
    ).toBe(403);
    const a = input(e.device_id);
    expect(
      (
        await call(
          "analysis",
          { ...a, privacy_policy_version: 1 },
          e.device_token,
        )
      ).status,
    ).toBe(403);
    expect(
      (await call("analysis", { ...a, model: "arbitrary" }, e.device_token))
        .status,
    ).toBe(400);
    expect(
      (
        await call(
          "analysis",
          '{"schema_version":1,"schema_version":1}',
          e.device_token,
        )
      ).status,
    ).toBe(400);
    expect(
      (await call("analysis", " ".repeat(32769), e.device_token)).status,
    ).toBe(413);
    expect(
      (
        await call("analysis", a, e.device_token, {
          "content-type": "text/plain",
        })
      ).status,
    ).toBe(400);
    expect(
      (
        await call("analysis", a, e.device_token, {
          "content-encoding": "gzip",
        })
      ).status,
    ).toBe(400);
  });
  it("makes one fixed structured-output call, validates provenance, returns exact replay and conflict", async () => {
    const e = await enroll(),
      a = input(e.device_id);
    upstream();
    const first = await call("analysis", a, e.device_token),
      r = (await first.json()) as any;
    expect(first.status).toBe(200);
    expect(r.provenance.model_id).toBe(MODEL);
    expect(upstreamCalls).toHaveLength(1);
    const sent = JSON.parse(upstreamCalls[0].options.body as string);
    expect(sent.model).toBe(MODEL);
    expect(sent.max_tokens).toBe(MAX_OUTPUT);
    expect(sent.output_config.effort).toBe("low");
    expect(sent.output_config.format.type).toBe("json_schema");
    expect(sent.output_config.format.schema.properties.category.minItems).toBe(
      1,
    );
    expect(upstreamCalls[0].options.redirect).toBe("error");
    expect(r.usage).toEqual({
      input_tokens: 100,
      output_tokens: 50,
      billed_units: 1,
    });
    const replay = await (await call("analysis", a, e.device_token)).json();
    expect(replay).toEqual(r);
    expect(
      (await call("analysis", { ...a, deadline_ms: 8000 }, e.device_token))
        .status,
    ).toBe(409);
    const u = (await (
      await call("usage", undefined, e.device_token)
    ).json()) as any;
    expect(u.evaluations_today).toBe(1);
    expect(u.input_tokens).toBe(100);
    await runDurableObjectAlarm(stub());
    const receipt = await env.DB.prepare(
      "SELECT * FROM analysis_receipts",
    ).first();
    expect(receipt?.upstream_request_id).toBe("req_test_only_123");
    expect(JSON.stringify(receipt)).not.toContain(a.context.task_summary);
  });
  it("concurrent duplicates share one durable reservation and never call twice", async () => {
    const e = await enroll(),
      a = input(e.device_id);
    upstream(undefined, 200, 100);
    const replies = await Promise.all([
      call("analysis", a, e.device_token),
      call("analysis", a, e.device_token),
    ]);
    expect(replies.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(
      (
        await env.DB.prepare(
          "SELECT COUNT(*) as n FROM analysis_receipts",
        ).first()
      )?.n,
    ).toBe(1);
  });
  it("global budget reservation is atomic across two devices and persists after eviction", async () => {
    await setConfig(
      "GLOBAL_MONTHLY_CAP_MICRO_USD",
      String(MAX_INPUT + MAX_OUTPUT * 5),
    );
    const i = await invitation(2),
      a = await enroll(i.invite),
      b = await enroll(i.invite);
    upstream(undefined, 200, 100);
    const replies = await Promise.all([
      call("analysis", input(a.device_id), a.device_token),
      call("analysis", input(b.device_id), b.device_token),
    ]);
    expect(replies.map((r) => r.status).sort()).toEqual([200, 429]);
    await abortAllDurableObjects();
    await setConfig("GLOBAL_MONTHLY_CAP_MICRO_USD", "350");
    expect(
      (await call("analysis", input(a.device_id), a.device_token)).status,
    ).toBe(429);
  });
  it("optional customer quotas are account scoped and support uncapped mode", async () => {
    const i = await invitation(2),
      a = await enroll(i.invite),
      b = await enroll(i.invite);
    await setConfig("DAILY_EVALUATION_LIMIT", "1");
    upstream();
    expect(
      (await call("analysis", input(a.device_id), a.device_token)).status,
    ).toBe(200);
    expect(
      (await call("analysis", input(b.device_id), b.device_token)).status,
    ).toBe(429);
    await setConfig("DAILY_EVALUATION_LIMIT", "null");
    upstream();
    expect(
      (await call("analysis", input(b.device_id), b.device_token)).status,
    ).toBe(200);
  });
  it("rotation invalidates old credential and all lifecycle routes bind device", async () => {
    const e = await enroll();
    expect(
      (
        await call(
          "device/rotate",
          { schema_version: 1, device_id: device() },
          e.device_token,
        )
      ).status,
    ).toBe(403);
    const rotated = (await (
      await call(
        "device/rotate",
        { schema_version: 1, device_id: e.device_id },
        e.device_token,
      )
    ).json()) as any;
    expect((await call("usage", undefined, e.device_token)).status).toBe(401);
    expect((await call("usage", undefined, rotated.device_token)).status).toBe(
      200,
    );
    expect(
      (
        await call(
          "device/revoke",
          { schema_version: 1, device_id: e.device_id },
          rotated.device_token,
        )
      ).status,
    ).toBe(200);
    expect((await call("usage", undefined, rotated.device_token)).status).toBe(
      403,
    );
  });
  it("account deletion removes metadata and prevents in-flight output resurrection", async () => {
    const i = await invitation(2),
      a = await enroll(i.invite),
      b = await enroll(i.invite);
    upstream(undefined, 200, 100);
    const pending = call("analysis", input(a.device_id), a.device_token);
    await new Promise((r) => setTimeout(r, 30));
    expect(
      (
        await call(
          "privacy/delete",
          { schema_version: 1, device_id: b.device_id, confirm: true },
          b.device_token,
        )
      ).status,
    ).toBe(200);
    expect((await pending).status).toBe(401);
    for (const table of ["accounts", "devices", "invites", "analysis_receipts"])
      expect(
        (await env.DB.prepare("SELECT COUNT(*) as n FROM " + table).first())?.n,
      ).toBe(0);
    await runInDurableObject(stub(), (_i: any, state) => {
      expect(
        state.storage.sql.exec("SELECT * FROM daily").toArray(),
      ).toHaveLength(0);
      expect(
        state.storage.sql.exec("SELECT * FROM ledger").toArray(),
      ).toHaveLength(0);
      expect(
        state.storage.sql.exec("SELECT * FROM monthly").toArray(),
      ).toHaveLength(1);
    });
  });
  it("kill switch refuses inference without upstream invocation", async () => {
    const e = await enroll();
    await setConfig("CLOUD_ANALYSIS_ENABLED", "false");
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(503);
    expect(
      (
        (await (
          await call("capabilities", undefined, e.device_token)
        ).json()) as any
      ).analysis_enabled,
    ).toBe(false);
  });
  it("provider errors, truncation, model mismatch, invalid output/usage never yield a verdict or retry", async () => {
    const e = await enroll();
    for (const bad of [
      { model: MODEL, stop_reason: "max_tokens" },
      { model: "wrong", stop_reason: "end_turn" },
      {
        model: MODEL,
        stop_reason: "end_turn",
        content: [
          { type: "text", text: '{"schema_version":1,"schema_version":1}' },
        ],
        usage: { input_tokens: 10, output_tokens: 10 },
      },
      {
        model: MODEL,
        stop_reason: "end_turn",
        content: [{ type: "text", text: JSON.stringify(verdict) }],
        usage: { input_tokens: MAX_INPUT + 1, output_tokens: 10 },
      },
    ]) {
      upstream(bad);
      const a = input(e.device_id);
      expect((await call("analysis", a, e.device_token)).status).toBe(503);
      expect((await call("analysis", a, e.device_token)).status).toBe(409);
    }
    upstream({}, 429);
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(503);
    const u = (await (
      await call("usage", undefined, e.device_token)
    ).json()) as any;
    expect(u.input_tokens).toBe(0);
    expect(u.reserved_input_tokens).toBe(5 * MAX_INPUT);
  });
  it("rejects an empty benign category and emits only bounded operator diagnostics", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => {});
    try {
      const e = await enroll();
      upstream({
        model: MODEL,
        stop_reason: "end_turn",
        content: [
          {
            type: "text",
            text: JSON.stringify({
              ...verdict,
              category: [],
              rationale: "Private diagnostic canary omitted from logs",
            }),
          },
        ],
        usage: { input_tokens: 100, output_tokens: 50 },
      });
      const response = await call(
        "analysis",
        input(e.device_id),
        e.device_token,
      );
      expect(response.status).toBe(503);
      expect(VERDICT_SCHEMA.properties.category.minItems).toBe(1);
      const messages = warning.mock.calls
        .map((args) => args[0])
        .filter(
          (value) =>
            typeof value === "string" &&
            value.includes("tracerook_provider_failure"),
        );
      expect(messages).toHaveLength(1);
      expect(JSON.parse(messages[0])).toEqual({
        event: "tracerook_provider_failure",
        stage: "verdict_validation",
        upstream_status: 200,
      });
      expect(messages.join(" ")).not.toContain("Private diagnostic canary");
      expect(messages.join(" ")).not.toContain(e.device_token);
      expect(upstreamCalls).toHaveLength(1);
      upstream({ error: { message: "Private provider error canary" } }, 400);
      expect(
        (await call("analysis", input(e.device_id), e.device_token)).status,
      ).toBe(503);
      const last = warning.mock.calls
        .map((args) => args[0])
        .filter(
          (value) =>
            typeof value === "string" &&
            value.includes("tracerook_provider_failure"),
        )
        .at(-1);
      expect(JSON.parse(last)).toEqual({
        event: "tracerook_provider_failure",
        stage: "http_status",
        upstream_status: 400,
      });
      expect(last).not.toContain("Private provider error canary");
    } finally {
      warning.mockRestore();
    }
  });
  it("expired verdict clears replay while durable identity and conservative crash charges remain", async () => {
    const e = await enroll(),
      a = input(e.device_id);
    upstream();
    expect((await call("analysis", a, e.device_token)).status).toBe(200);
    await runInDurableObject(stub(), (_i: any, state) => {
      state.storage.sql.exec(
        "UPDATE ledger SET expires=0,cache=NULL,state=?",
        "pending",
      );
    });
    await abortAllDurableObjects();
    expect((await call("analysis", a, e.device_token)).status).toBe(409);
    await setConfig("GLOBAL_MONTHLY_CAP_MICRO_USD", "350");
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(429);
  });

  it("accepts realistic summaries and bounded Haiku thinking plus one text", async () => {
    const e = await enroll(),
      a = input(e.device_id);
    a.context.task_summary = "Implement a checkout button in a demo UI";
    a.context.proposed_action_summary =
      "Run the ordinary checkout tests to confirm the component behavior.";
    upstream({
      model: MODEL,
      stop_reason: "end_turn",
      content: [
        {
          type: "thinking",
          thinking: "Synthetic hidden thinking",
          signature: "test",
        },
        {
          type: "text",
          text: JSON.stringify({
            ...verdict,
            rationale:
              "The proposed test run plausibly serves the stated checkout task.",
          }),
        },
      ],
      usage: { input_tokens: 100, output_tokens: 50 },
    });
    expect((await call("analysis", a, e.device_token)).status).toBe(200);
  });
  it("slow uploads do not hold the account gate and abort within three seconds", async () => {
    const e = await enroll();
    let timer: ReturnType<typeof setTimeout>;
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("{"));
        timer = setTimeout(() => controller.close(), 5000);
      },
      cancel() {
        clearTimeout(timer);
      },
    });
    const slow = SELF.fetch("https://api.tracerook.dev/v1/alpha/enroll", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: stream,
    });
    await new Promise((r) => setTimeout(r, 20));
    const started = Date.now();
    expect((await call("usage", undefined, e.device_token)).status).toBe(200);
    expect(Date.now() - started).toBeLessThan(500);
    expect((await slow).status).toBe(504);
  });
  it("durable receipt outbox survives D1 write failure and preserves successful replay", async () => {
    const e = await enroll(),
      a = input(e.device_id);
    await runInDurableObject(stub(), (i: any) => {
      i.originalDB = i.env.DB;
      const db = i.env.DB;
      i.env.DB = {
        prepare: (sql: string) => {
          if (sql.startsWith("INSERT OR IGNORE INTO analysis_receipts"))
            throw new Error("test-only write failure");
          return db.prepare(sql);
        },
        batch: (...args: any[]) => db.batch(...args),
      };
    });
    upstream();
    const r = await call("analysis", a, e.device_token);
    expect(r.status).toBe(200);
    expect((await call("analysis", a, e.device_token)).status).toBe(200);
    await runInDurableObject(stub(), (i: any, state) => {
      expect(
        state.storage.sql.exec("SELECT * FROM outbox").toArray(),
      ).toHaveLength(1);
      i.env.DB = i.originalDB;
    });
    await runDurableObjectAlarm(stub());
    expect(
      (
        await env.DB.prepare(
          "SELECT COUNT(*) AS n FROM analysis_receipts",
        ).first()
      )?.n,
    ).toBe(1);
    await runInDurableObject(stub(), (_i: any, state) =>
      expect(
        state.storage.sql.exec("SELECT * FROM outbox").toArray(),
      ).toHaveLength(0),
    );
  });
  it("deletion crash after D1 commit resumes account metadata purge from durable job", async () => {
    const e = await enroll();
    upstream();
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(200);
    await runInDurableObject(stub(), (i: any) => {
      i.originalDB = i.env.DB;
      const db = i.env.DB;
      i.env.DB = {
        prepare: (s: string) => db.prepare(s),
        batch: async (...args: any[]) => {
          const value = await db.batch(...args);
          throw new Error("test-only crash after D1 deletion");
        },
      };
    });
    expect(
      (
        await call(
          "privacy/delete",
          { schema_version: 1, device_id: e.device_id, confirm: true },
          e.device_token,
        )
      ).status,
    ).toBe(503);
    await runInDurableObject(stub(), (i: any, state) => {
      expect(
        state.storage.sql.exec("SELECT * FROM deleted").toArray(),
      ).toHaveLength(1);
      i.env.DB = i.originalDB;
    });
    await abortAllDurableObjects();
    await runDurableObjectAlarm(stub());
    await runInDurableObject(stub(), (_i: any, state) => {
      for (const table of ["deleted", "ledger", "daily", "outbox"])
        expect(
          state.storage.sql.exec("SELECT * FROM " + table).toArray(),
        ).toHaveLength(0);
    });
  });
  it("does not postpone an existing alarm and deletes expired cached verdict on alarm", async () => {
    const e = await enroll();
    const before = await runInDurableObject(stub(), (_i: any, state) =>
      state.storage.getAlarm(),
    );
    upstream();
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(200);
    const after = await runInDurableObject(stub(), (_i: any, state) =>
      state.storage.getAlarm(),
    );
    expect(after).toBeLessThanOrEqual(before!);
    const time = Date.now() + 600001;
    const clock = vi.spyOn(Date, "now").mockReturnValue(time);
    try {
      await runDurableObjectAlarm(stub());
      await runInDurableObject(stub(), (_i: any, state) =>
        expect(
          state.storage.sql.exec("SELECT cache FROM ledger").one().cache,
        ).toBeNull(),
      );
    } finally {
      clock.mockRestore();
    }
  });
  it("enforces two in-flight calls per device while unrelated usage remains responsive", async () => {
    const e = await enroll();
    upstream(undefined, 200, 150);
    upstream(undefined, 200, 150);
    const a = call("analysis", input(e.device_id), e.device_token),
      b = call("analysis", input(e.device_id), e.device_token);
    await new Promise((r) => setTimeout(r, 25));
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(429);
    expect((await call("usage", undefined, e.device_token)).status).toBe(200);
    expect((await a).status).toBe(200);
    expect((await b).status).toBe(200);
  });
  it("provider deadline abort retains full conservative accounting and no retry", async () => {
    const e = await enroll(),
      a = { ...input(e.device_id), deadline_ms: 1000 };
    upstream(undefined, 200, 2000);
    expect((await call("analysis", a, e.device_token)).status).toBe(504);
    expect((await call("analysis", a, e.device_token)).status).toBe(409);
    const u = (await (
      await call("usage", undefined, e.device_token)
    ).json()) as any;
    expect(u.input_tokens).toBe(0);
    expect(u.reserved_input_tokens).toBe(MAX_INPUT);
    expect(upstreamCalls).toHaveLength(1);
  });

  it("enforces zero optional global cap and fractional accounting rates", async () => {
    const e = await enroll();
    await setConfig("GLOBAL_MONTHLY_CAP_MICRO_USD", "0");
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(429);
    await setConfig("GLOBAL_MONTHLY_CAP_MICRO_USD", "null");
    await setConfig("INPUT_PRICE_MICRO_USD_PER_TOKEN", "0.1");
    await setConfig("OUTPUT_PRICE_MICRO_USD_PER_TOKEN", "0.5");
    upstream();
    expect(
      (await call("analysis", input(e.device_id), e.device_token)).status,
    ).toBe(200);
    await runInDurableObject(stub(), (_i: any, state) =>
      expect(
        state.storage.sql.exec("SELECT cost FROM monthly").one().cost,
      ).toBe(35),
    );
  });
  it("rejects expired/revoked invitations and expired credentials", async () => {
    const inv = await invitation();
    await env.DB.prepare("UPDATE invites SET expires_at=?").bind(0).run();
    const body = {
      schema_version: 1,
      invitation: inv.invite,
      device_id: device(),
      app_version: "1",
      privacy_policy_version: 2,
    };
    expect((await call("alpha/enroll", body)).status).toBe(403);
    await env.DB.prepare("UPDATE invites SET expires_at=?,revoked_at=?")
      .bind(Date.now() + 86400000, Date.now())
      .run();
    expect((await call("alpha/enroll", body)).status).toBe(403);
    await env.DB.prepare("UPDATE invites SET revoked_at=NULL").run();
    const e = await enroll(inv.invite);
    await env.DB.prepare("UPDATE devices SET expires_at=0").run();
    expect((await call("usage", undefined, e.device_token)).status).toBe(401);
  });
  it("rejects non-UTF8 media, nested unknown keys and invalid Unicode field bounds", async () => {
    const e = await enroll(),
      a = input(e.device_id);
    expect(
      (
        await call("analysis", a, e.device_token, {
          "content-type": "application/json; charset=latin-1",
        })
      ).status,
    ).toBe(400);
    expect(
      (
        await call(
          "analysis",
          { ...a, context: { ...a.context, raw_command: "private" } },
          e.device_token,
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await call(
          "analysis",
          { ...a, context: { ...a.context, task_summary: "界".repeat(400) } },
          e.device_token,
        )
      ).status,
    ).toBe(400);
    expect(
      (await call("analysis", { ...a, deadline_ms: 999 }, e.device_token))
        .status,
    ).toBe(400);
    expect(
      (await call("analysis", { ...a, schema_version: 2 }, e.device_token))
        .status,
    ).toBe(426);
  });
  it("throttles anonymous enrollment before body processing", async () => {
    for (let n = 0; n < 10; n++)
      expect((await call("alpha/enroll", {})).status).toBe(400);
    expect((await call("alpha/enroll", {})).status).toBe(429);
  });
});
describe("strict parser and server privacy", () => {
  it.each([
    '{"a":1,"a":2}',
    '{"a":1,"\\u0061":2}',
    '{"a":{"b":1,"b":2}}',
    "[1,]",
    '{"a":NaN}',
    '{"a":1e999}',
    "{} trailing",
    "[".repeat(30) + "0" + "]".repeat(30),
  ])("rejects malformed/duplicate JSON %s", (raw) => {
    expect(() => strictJSON(raw)).toThrow();
  });
  it.each([
    "sk-ant-" + "x".repeat(40),
    "ghp_" + "x".repeat(36),
    "AKIA" + "A".repeat(16),
    "-----BEGIN PRIVATE KEY-----",
    "trd_" + "ab".repeat(32),
    "tri_" + "cd".repeat(32),
    "token=hidden",
    "password: hidden",
    "/Users/private/repo",
    "/home/private/repo",
    "Read /tmp/private/file",
    "HOME=private\nPATH=private",
    "_authToken=example",
    "Call 192.168.0.1 now",
    "internal.example.com",
    "C:\\private\\repo",
    "https://private.invalid",
    "data:text/plain;base64,ZW52",
    "Authorization: Bearer hidden",
    "QWxhZGRpbjpvcGVuIHNlc2FtZQ".repeat(3),
    "s k - a n t - " + "x ".repeat(40),
  ])("rejects privacy seed %s", (seed) => {
    const a = input(device());
    a.context.task_summary = seed;
    expect(() => analysis(a)).toThrow();
  });
  it("canonicalizes ordering without changing strings", async () => {
    expect(await digest(canonical({ b: 1, a: "x" }))).toBe(
      await digest(canonical({ a: "x", b: 1 })),
    );
  });
});

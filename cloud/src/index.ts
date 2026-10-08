import { DurableObject } from "cloudflare:workers";
import { analyze, MAX_INPUT, MAX_OUTPUT, MODEL } from "./anthropic";
import {
  APIError,
  Analysis,
  analysis,
  boundedBody,
  canonical,
  digest,
  hmac,
  integer,
  invalid,
  object,
  strictJSON,
  string,
  token,
  uuid,
  version,
} from "./validation";
export interface Env {
  DB: D1Database;
  COORDINATOR: DurableObjectNamespace<AlphaCoordinator>;
  ENVIRONMENT: string;
  AUTH_DIGEST_KEY: string;
  ANTHROPIC_API_KEY?: string;
  CLOUD_ANALYSIS_ENABLED: string;
  GLOBAL_MONTHLY_CAP_MICRO_USD: string;
  INPUT_PRICE_MICRO_USD_PER_TOKEN: string;
  OUTPUT_PRICE_MICRO_USD_PER_TOKEN: string;
  DAILY_EVALUATION_LIMIT: string;
  DAILY_INPUT_TOKEN_LIMIT: string;
  DAILY_OUTPUT_TOKEN_LIMIT: string;
}
interface Principal {
  id: string;
  account_id: string;
  expires_at: number;
  revoked_at: number | null;
}
interface Ledger extends Record<string, SqlStorageValue> {
  device: string;
  request: string;
  account: string;
  hash: string;
  state: string;
  day: string;
  month: string;
  cost: number;
  input: number;
  output: number;
  created: number;
  cache: string | null;
  expires: number;
}
const now = () => Date.now();
const date = (n = now()) => new Date(n).toISOString().slice(0, 10);
const json = (
  value: unknown,
  status = 200,
  trace = "tr_" + crypto.randomUUID(),
) =>
  new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "X-TraceRook-Request-ID": trace,
      "x-content-type-options": "nosniff",
    },
  });
const failure = (e: unknown, trace: string) => {
  const a =
    e instanceof APIError ? e : new APIError(503, "provider_unavailable", true);
  const r = json(
    {
      schema_version: 1,
      error: {
        code: a.code,
        message:
          a.code === "invalid_request"
            ? "Request rejected."
            : "TraceRook Cloud request could not be completed.",
        retryable: a.retryable,
      },
      trace_id: trace,
    },
    a.status,
    trace,
  );
  if (a.status === 429) r.headers.set("Retry-After", "60");
  return r;
};
const optionalLimit = (v: string): number | null =>
  v === "null"
    ? null
    : integer(configNumber(v, true), 0, Number.MAX_SAFE_INTEGER);
const configNumber = (v: string, zero = false) => {
  const n = Number(v);
  if (
    !/^\d+(?:\.\d+)?$/.test(v) ||
    !Number.isFinite(n) ||
    n < 0 ||
    (!zero && n === 0)
  )
    throw new APIError(503, "provider_unavailable", true);
  return n;
};
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const trace = "tr_" + crypto.randomUUID();
    try {
      const url = new URL(request.url);
      if (
        url.protocol !== "https:" &&
        url.hostname !== "localhost" &&
        url.hostname !== "127.0.0.1"
      )
        throw invalid();
      if (url.search || request.headers.has("origin")) throw invalid();
      if (url.pathname === "/v1/healthz" && request.method === "GET")
        return json({ schema_version: 1, status: "ok" }, 200, trace);
      if (!env.AUTH_DIGEST_KEY || env.AUTH_DIGEST_KEY.length < 32)
        throw new APIError(503, "provider_unavailable");
      return await env.COORDINATOR.get(
        env.COORDINATOR.idFromName("alpha-v1"),
      ).fetch(request);
    } catch (e) {
      return failure(e, trace);
    }
  },
};
export class AlphaCoordinator extends DurableObject<Env> {
  private gate: Promise<unknown> = Promise.resolve();
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(
      `CREATE TABLE IF NOT EXISTS ledger (device TEXT NOT NULL, request TEXT NOT NULL, account TEXT NOT NULL, hash TEXT NOT NULL,state TEXT NOT NULL,day TEXT NOT NULL,month TEXT NOT NULL,cost REAL NOT NULL,input INTEGER NOT NULL,output INTEGER NOT NULL,created INTEGER NOT NULL,cache TEXT,expires INTEGER NOT NULL,PRIMARY KEY(device,request)); CREATE TABLE IF NOT EXISTS monthly (month TEXT PRIMARY KEY,cost REAL NOT NULL); CREATE TABLE IF NOT EXISTS daily (account TEXT NOT NULL,day TEXT NOT NULL,count INTEGER NOT NULL,input INTEGER NOT NULL,output INTEGER NOT NULL,reserved_input INTEGER NOT NULL,reserved_output INTEGER NOT NULL,PRIMARY KEY(account,day)); CREATE TABLE IF NOT EXISTS attempts (key TEXT PRIMARY KEY,window INTEGER NOT NULL,count INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS deleted (account TEXT PRIMARY KEY); CREATE TABLE IF NOT EXISTS outbox (analysis_id TEXT PRIMARY KEY, account TEXT NOT NULL, payload TEXT NOT NULL);CREATE INDEX IF NOT EXISTS ledger_expiry ON ledger(expires);CREATE INDEX IF NOT EXISTS ledger_created ON ledger(created);CREATE INDEX IF NOT EXISTS ledger_account ON ledger(account);CREATE INDEX IF NOT EXISTS ledger_pending ON ledger(device,state,expires);CREATE INDEX IF NOT EXISTS daily_day ON daily(day);CREATE INDEX IF NOT EXISTS attempts_window ON attempts(window);CREATE INDEX IF NOT EXISTS outbox_account ON outbox(account);`,
    );
  }
  private locked<T>(f: () => Promise<T>): Promise<T> {
    const p = this.gate.then(f, f);
    this.gate = p.catch(() => {});
    return p;
  }
  private limits() {
    return {
      evaluations_per_day: optionalLimit(this.env.DAILY_EVALUATION_LIMIT),
      input_tokens_per_day: optionalLimit(this.env.DAILY_INPUT_TOKEN_LIMIT),
      output_tokens_per_day: optionalLimit(this.env.DAILY_OUTPUT_TOKEN_LIMIT),
      devices_per_account: 3,
    };
  }
  private enabled() {
    try {
      return (
        this.env.CLOUD_ANALYSIS_ENABLED === "true" &&
        Boolean(this.env.ANTHROPIC_API_KEY) &&
        (optionalLimit(this.env.GLOBAL_MONTHLY_CAP_MICRO_USD) === null ||
          optionalLimit(this.env.GLOBAL_MONTHLY_CAP_MICRO_USD)! >= 0) &&
        configNumber(this.env.INPUT_PRICE_MICRO_USD_PER_TOKEN) > 0 &&
        configNumber(this.env.OUTPUT_PRICE_MICRO_USD_PER_TOKEN) > 0
      );
    } catch {
      return false;
    }
  }
  private async principal(request: Request): Promise<Principal> {
    const auth = request.headers.get("authorization");
    if (!auth || !/^Bearer trd_[a-f0-9]{64}$/.test(auth))
      throw new APIError(401, "unauthorized");
    const d = await hmac(this.env.AUTH_DIGEST_KEY, auth.slice(7));
    const p = await this.env.DB.prepare(
      "SELECT id, account_id, expires_at, revoked_at FROM devices WHERE token_digest=?",
    )
      .bind(d)
      .first<Principal>();
    if (!p || p.expires_at <= now()) throw new APIError(401, "unauthorized");
    if (
      p.revoked_at ||
      this.ctx.storage.sql
        .exec("SELECT account FROM deleted WHERE account=?", p.account_id)
        .toArray().length
    )
      throw new APIError(403, "revoked");
    return p;
  }
  private async schedule() {
    const expires = this.ctx.storage.sql
      .exec<{ expiry: number | null }>(
        "SELECT MIN(expires) AS expiry FROM ledger WHERE cache IS NOT NULL",
      )
      .one().expiry;
    const next = Math.min(now() + 600000, expires ?? Infinity);
    const alarm = await this.ctx.storage.getAlarm();
    if (alarm === null || alarm > next) await this.ctx.storage.setAlarm(next);
  }
  private async body(request: Request) {
    if (
      !/^application\/json(?:\s*;\s*charset\s*=\s*utf-8)?$/i.test(
        request.headers.get("content-type") ?? "",
      ) ||
      request.headers.has("content-encoding")
    )
      throw invalid();
    return strictJSON(await boundedBody(request));
  }
  private throttle(key: string, max: number) {
    const window = Math.floor(now() / 60000);
    this.ctx.storage.sql.exec(
      "INSERT INTO attempts(key,window,count) VALUES(?,?,1) ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window=excluded.window THEN count+1 ELSE 1 END,window=excluded.window",
      key,
      window,
    );
    const a = this.ctx.storage.sql
      .exec<{ count: number }>("SELECT count FROM attempts WHERE key=?", key)
      .one();
    if (a.count > max) throw new APIError(429, "rate_limited", true);
  }
  private credential(device: string, t: string, expires: number) {
    return {
      schema_version: 1,
      device_id: device,
      device_token: t,
      token_expires_at: new Date(expires).toISOString(),
      limits: this.limits(),
    };
  }
  async fetch(request: Request): Promise<Response> {
    const trace = "tr_" + crypto.randomUUID(),
      started = now();
    try {
      const path = new URL(request.url).pathname;
      await this.locked(async () => {
        this.throttle(
          "ip:" +
            (await hmac(
              this.env.AUTH_DIGEST_KEY,
              request.headers.get("CF-Connecting-IP") ?? "local",
            )),
          240,
        );
        if (path === "/v1/alpha/enroll")
          this.throttle(
            "enroll:" +
              (await hmac(
                this.env.AUTH_DIGEST_KEY,
                request.headers.get("CF-Connecting-IP") ?? "local",
              )),
            10,
          );
      });
      const raw =
        request.method === "POST" ? await this.body(request) : undefined;
      if (request.method === "POST" && path === "/v1/alpha/enroll")
        return await this.locked(async () => {
          const o = object(raw, [
            "schema_version",
            "invitation",
            "device_id",
            "app_version",
            "privacy_policy_version",
          ]);
          version(o);
          if (o.privacy_policy_version !== 2)
            throw new APIError(403, "consent_required");
          const device = uuid(o.device_id);
          const invite = string(o.invitation, 128, 128);
          if (!/^tri_[a-f0-9]{64}$/.test(invite))
            throw new APIError(403, "invalid_invite");
          const app = string(o.app_version, 64, 64);
          if (!/^[A-Za-z0-9.+_-]{1,64}$/.test(app)) throw invalid();
          const hash = await hmac(this.env.AUTH_DIGEST_KEY, invite),
            t = token(),
            td = await hmac(this.env.AUTH_DIGEST_KEY, t),
            expires = now() + 30 * 86400000;
          if (
            await this.env.DB.prepare("SELECT id FROM devices WHERE id=?")
              .bind(device)
              .first()
          )
            throw new APIError(409, "conflict");
          const invited = await this.env.DB.prepare(
            "SELECT account_id FROM invites WHERE invite_digest=?",
          )
            .bind(hash)
            .first<{ account_id: string }>();
          if (
            !invited ||
            this.ctx.storage.sql
              .exec(
                "SELECT account FROM deleted WHERE account=?",
                invited.account_id,
              )
              .toArray().length
          )
            throw new APIError(403, "invalid_invite");
          const result = await this.env.DB.batch([
            this.env.DB.prepare(
              "UPDATE invites SET uses=uses+1 WHERE invite_digest=? AND revoked_at IS NULL AND expires_at>? AND uses<max_uses AND (SELECT COUNT(*) FROM devices WHERE account_id=invites.account_id AND revoked_at IS NULL)<3",
            ).bind(hash, now()),
            this.env.DB.prepare(
              "INSERT INTO devices(id,account_id,token_digest,expires_at,app_version,created_at) SELECT ?,account_id,?,?,?,? FROM invites WHERE invite_digest=? AND changes()=1",
            ).bind(device, td, expires, app, now(), hash),
          ]);
          if (result[1].meta.changes !== 1)
            throw new APIError(403, "invalid_invite");
          await this.schedule();
          return json(this.credential(device, t, expires), 200, trace);
        });
      if (
        request.method === "GET" &&
        (path === "/v1/capabilities" || path === "/v1/usage")
      )
        return await this.locked(async () => {
          const p = await this.principal(request);
          this.throttle("device:" + p.id, 120);
          if (path.endsWith("capabilities"))
            return json(
              {
                schema_version: 1,
                provider: "anthropic",
                transport: "tracerook_cloud",
                model_id: MODEL,
                analysis_enabled: this.enabled(),
                privacy_policy_version: 2,
                retention: {
                  receipt_days: 30,
                  usage_days: 90,
                  verdict_cache_seconds: 600,
                },
                limits: this.limits(),
              },
              200,
              trace,
            );
          const usage = this.ctx.storage.sql
            .exec<{
              count: number;
              input: number;
              output: number;
              reserved_input: number;
              reserved_output: number;
            }>(
              "SELECT * FROM daily WHERE account=? AND day=?",
              p.account_id,
              date(),
            )
            .toArray()[0];
          return json(
            {
              schema_version: 1,
              date_utc: date(),
              evaluations_today: usage?.count ?? 0,
              input_tokens: usage?.input ?? 0,
              output_tokens: usage?.output ?? 0,
              reserved_input_tokens: usage?.reserved_input ?? 0,
              reserved_output_tokens: usage?.reserved_output ?? 0,
              limits: this.limits(),
            },
            200,
            trace,
          );
        });
      if (
        request.method === "POST" &&
        [
          "/v1/device/rotate",
          "/v1/device/revoke",
          "/v1/privacy/delete",
        ].includes(path)
      )
        return await this.locked(async () => {
          const p = await this.principal(request);
          const o = object(
            raw,
            path.endsWith("delete")
              ? ["schema_version", "device_id", "confirm"]
              : ["schema_version", "device_id"],
          );
          version(o);
          if (uuid(o.device_id) !== p.id) throw new APIError(403, "revoked");
          if (path.endsWith("rotate")) {
            const t = token(),
              td = await hmac(this.env.AUTH_DIGEST_KEY, t),
              expires = now() + 30 * 86400000;
            await this.env.DB.prepare(
              "UPDATE devices SET token_digest=?,expires_at=? WHERE id=?",
            )
              .bind(td, expires, p.id)
              .run();
            return json(this.credential(p.id, t, expires), 200, trace);
          }
          if (path.endsWith("revoke")) {
            await this.env.DB.prepare(
              "UPDATE devices SET revoked_at=? WHERE id=?",
            )
              .bind(now(), p.id)
              .run();
            this.ctx.storage.sql.exec(
              "UPDATE ledger SET cache=NULL WHERE device=?",
              p.id,
            );
            return json({ schema_version: 1, revoked: true }, 200, trace);
          }
          if (o.confirm !== true) throw invalid();
          this.ctx.storage.sql.exec(
            "INSERT OR IGNORE INTO deleted(account) VALUES(?)",
            p.account_id,
          );
          await this.env.DB.batch(
            [
              "DELETE FROM analysis_receipts WHERE account_id=?",
              "DELETE FROM devices WHERE account_id=?",
              "DELETE FROM invites WHERE account_id=?",
              "DELETE FROM accounts WHERE id=?",
            ].map((sql) => this.env.DB.prepare(sql).bind(p.account_id)),
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM outbox WHERE account=?",
            p.account_id,
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM ledger WHERE account=?",
            p.account_id,
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM daily WHERE account=?",
            p.account_id,
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM deleted WHERE account=?",
            p.account_id,
          );
          return json({ schema_version: 1, deleted: true }, 200, trace);
        });
      if (request.method === "POST" && path === "/v1/analysis")
        return await this.runAnalysis(request, trace, raw, started);
      throw new APIError(404, "invalid_request");
    } catch (e) {
      return failure(e, trace);
    }
  }
  private async runAnalysis(
    request: Request,
    trace: string,
    raw: unknown,
    started: number,
  ): Promise<Response> {
    const payload = analysis(raw),
      hash = await digest(canonical(payload));
    let principal: Principal;
    const reservation = await this.locked(async () => {
      principal = await this.principal(request);
      this.throttle("device:" + principal.id, 120);
      if (payload.device_id !== principal.id)
        throw new APIError(403, "revoked");
      const previous = this.ctx.storage.sql
        .exec<Ledger>(
          "SELECT * FROM ledger WHERE device=? AND request=?",
          principal.id,
          payload.request_id,
        )
        .toArray()[0];
      if (previous) {
        if (previous.hash !== hash) throw new APIError(409, "conflict");
        if (previous.cache && previous.expires > now()) return previous.cache;
        throw new APIError(
          409,
          previous.state === "pending" && previous.expires > now()
            ? "in_progress"
            : "replay_unavailable",
        );
      }
      if (!this.enabled())
        throw new APIError(503, "provider_unavailable", true);
      const limits = this.limits(),
        day = date(),
        month = day.slice(0, 7),
        cost = Math.ceil(
          MAX_INPUT * configNumber(this.env.INPUT_PRICE_MICRO_USD_PER_TOKEN) +
            MAX_OUTPUT *
              configNumber(this.env.OUTPUT_PRICE_MICRO_USD_PER_TOKEN),
        ),
        cap = optionalLimit(this.env.GLOBAL_MONTHLY_CAP_MICRO_USD);
      this.ctx.storage.transactionSync(() => {
        // Stale pending reservations remain charged; only the concurrency slot expires.
        const inFlight = this.ctx.storage.sql
          .exec<{ n: number }>(
            "SELECT COUNT(*) AS n FROM ledger WHERE device=? AND state=? AND expires>?",
            principal.id,
            "pending",
            now(),
          )
          .one().n;
        if (inFlight >= 2) throw new APIError(429, "rate_limited", true);
        const daily = this.ctx.storage.sql
          .exec<{
            count: number;
            reserved_input: number;
            reserved_output: number;
          }>(
            "SELECT * FROM daily WHERE account=? AND day=?",
            principal.account_id,
            day,
          )
          .toArray()[0];
        if (
          daily &&
          ((limits.evaluations_per_day !== null &&
            daily.count >= limits.evaluations_per_day) ||
            (limits.input_tokens_per_day !== null &&
              daily.reserved_input + MAX_INPUT > limits.input_tokens_per_day) ||
            (limits.output_tokens_per_day !== null &&
              daily.reserved_output + MAX_OUTPUT >
                limits.output_tokens_per_day))
        )
          throw new APIError(429, "quota_exhausted");
        if (
          (limits.input_tokens_per_day !== null &&
            MAX_INPUT > limits.input_tokens_per_day) ||
          (limits.output_tokens_per_day !== null &&
            MAX_OUTPUT > limits.output_tokens_per_day)
        )
          throw new APIError(429, "quota_exhausted");
        const monthly = this.ctx.storage.sql
          .exec<{ cost: number }>(
            "SELECT cost FROM monthly WHERE month=?",
            month,
          )
          .toArray()[0];
        if (cap !== null && (monthly?.cost ?? 0) + cost > cap)
          throw new APIError(429, "quota_exhausted");
        this.ctx.storage.sql.exec(
          "INSERT INTO monthly(month,cost) VALUES(?,?) ON CONFLICT(month) DO UPDATE SET cost=cost+excluded.cost",
          month,
          cost,
        );
        this.ctx.storage.sql.exec(
          "INSERT INTO daily(account,day,count,input,output,reserved_input,reserved_output) VALUES(?,?,1,0,0,?,?) ON CONFLICT(account,day) DO UPDATE SET count=count+1,reserved_input=reserved_input+excluded.reserved_input,reserved_output=reserved_output+excluded.reserved_output",
          principal.account_id,
          day,
          MAX_INPUT,
          MAX_OUTPUT,
        );
        this.ctx.storage.sql.exec(
          "INSERT INTO ledger(device,request,account,hash,state,day,month,cost,input,output,created,cache,expires) VALUES(?,?,?,?,?,?,?,?,?,?,?,NULL,?)",
          principal.id,
          payload.request_id,
          principal.account_id,
          hash,
          "pending",
          day,
          month,
          cost,
          MAX_INPUT,
          MAX_OUTPUT,
          now(),
          now() + payload.deadline_ms + 1000,
        );
      });
      await this.schedule();
      return null;
    });
    if (reservation)
      return new Response(reservation, {
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
          "X-TraceRook-Request-ID": trace,
        },
      });
    const a = payload!,
      p = principal!;
    try {
      const remaining = a.deadline_ms - (now() - started);
      if (remaining < 500) throw new APIError(504, "deadline_exceeded", true);
      const result = await analyze(
        { ...a, deadline_ms: remaining },
        this.env.ANTHROPIC_API_KEY!,
      );
      return await this.locked(async () => {
        await this.principal(request); // Deletion, revocation and rotation win over late upstream replies.
        if (now() - started >= a.deadline_ms - 100)
          throw new APIError(504, "deadline_exceeded", true);
        const receipt = {
          schema_version: 1,
          request_id: a.request_id,
          analysis_id: "an_" + crypto.randomUUID(),
          verdict: result.verdict,
          provenance: {
            provider: "anthropic",
            transport: "tracerook_cloud",
            model_id: MODEL,
            policy_version: 1,
            prompt_version: "risk-eval-v1",
            trace_id: trace,
            validated_at: new Date().toISOString(),
          },
          usage: {
            input_tokens: result.input,
            output_tokens: result.output,
            billed_units: 1,
          },
          server_elapsed_ms: now() - started,
        };
        const row = this.ctx.storage.sql
          .exec<Ledger>(
            "SELECT * FROM ledger WHERE device=? AND request=?",
            p.id,
            a.request_id,
          )
          .toArray()[0];
        if (!row) throw new APIError(403, "revoked");
        const actual = Math.ceil(
          result.input *
            configNumber(this.env.INPUT_PRICE_MICRO_USD_PER_TOKEN) +
            result.output *
              configNumber(this.env.OUTPUT_PRICE_MICRO_USD_PER_TOKEN),
        );
        this.ctx.storage.transactionSync(() => {
          this.ctx.storage.sql.exec(
            "UPDATE monthly SET cost=cost-?+? WHERE month=?",
            row.cost,
            actual,
            row.month,
          );
          this.ctx.storage.sql.exec(
            "UPDATE daily SET input=input+?,output=output+?,reserved_input=reserved_input-?+?,reserved_output=reserved_output-?+? WHERE account=? AND day=?",
            result.input,
            result.output,
            MAX_INPUT,
            result.input,
            MAX_OUTPUT,
            result.output,
            p.account_id,
            row.day,
          );
          this.ctx.storage.sql.exec(
            "UPDATE ledger SET state=?,cost=?,input=?,output=?,cache=?,expires=? WHERE device=? AND request=?",
            "complete",
            actual,
            result.input,
            result.output,
            JSON.stringify(receipt),
            now() + 600000,
            p.id,
            a.request_id,
          );
          this.ctx.storage.sql.exec(
            "INSERT INTO outbox VALUES(?,?,?)",
            receipt.analysis_id,
            p.account_id,
            JSON.stringify([
              receipt.analysis_id,
              p.account_id,
              p.id,
              a.request_id,
              MODEL,
              result.upstreamID,
              trace,
              result.input,
              result.output,
              receipt.server_elapsed_ms,
              now(),
              now() + 30 * 86400000,
            ]),
          );
        });
        // Secondary receipt writes retry from a durable metadata-only outbox.
        await this.schedule();
        this.ctx.waitUntil(
          this.locked(async () => {
            await this.flushOutbox();
          }),
        );
        return json(receipt, 200, trace);
      });
    } catch (e) {
      await this.locked(async () => {
        this.ctx.storage.sql.exec(
          "UPDATE ledger SET state=?,cache=NULL,expires=? WHERE device=? AND request=? AND state='pending'",
          "failed",
          now(),
          p.id,
          a.request_id,
        );
      });
      throw e;
    }
  }
  private async flushOutbox() {
    const rows = this.ctx.storage.sql
      .exec<{ analysis_id: string; payload: string }>(
        "SELECT analysis_id,payload FROM outbox LIMIT 100",
      )
      .toArray();
    for (const row of rows) {
      try {
        await this.env.DB.prepare(
          "INSERT OR IGNORE INTO analysis_receipts VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
        )
          .bind(...JSON.parse(row.payload))
          .run();
        this.ctx.storage.sql.exec(
          "DELETE FROM outbox WHERE analysis_id=?",
          row.analysis_id,
        );
      } catch {
        return;
      }
    }
  }
  async alarm() {
    await this.locked(async () => {
      const time = now();
      try {
        this.ctx.storage.sql.exec(
          "UPDATE ledger SET cache=NULL WHERE expires<=?",
          time,
        );
        this.ctx.storage.sql.exec(
          "DELETE FROM ledger WHERE created<?",
          time - 90 * 86400000,
        );
        this.ctx.storage.sql.exec(
          "DELETE FROM daily WHERE day<?",
          date(time - 90 * 86400000),
        );
        this.ctx.storage.sql.exec(
          "DELETE FROM attempts WHERE window<?",
          Math.floor(time / 60000) - 60,
        );
        for (const row of this.ctx.storage.sql
          .exec<{ account: string }>("SELECT account FROM deleted")
          .toArray()) {
          await this.env.DB.batch(
            [
              "DELETE FROM analysis_receipts WHERE account_id=?",
              "DELETE FROM devices WHERE account_id=?",
              "DELETE FROM invites WHERE account_id=?",
              "DELETE FROM accounts WHERE id=?",
            ].map((sql) => this.env.DB.prepare(sql).bind(row.account)),
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM ledger WHERE account=?",
            row.account,
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM daily WHERE account=?",
            row.account,
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM outbox WHERE account=?",
            row.account,
          );
          this.ctx.storage.sql.exec(
            "DELETE FROM deleted WHERE account=?",
            row.account,
          );
        }
        this.ctx.storage.sql.exec(
          "DELETE FROM outbox WHERE CAST(json_extract(payload, '$[11]') AS INTEGER)<=?",
          time,
        );
        await this.flushOutbox();
        await this.env.DB.batch([
          this.env.DB.prepare(
            "DELETE FROM analysis_receipts WHERE delete_after<=?",
          ).bind(time),
          this.env.DB.prepare("DELETE FROM invites WHERE expires_at<?").bind(
            time - 30 * 86400000,
          ),
        ]);
      } finally {
        await this.ctx.storage.deleteAlarm();
        await this.schedule();
      }
    });
  }
}

export class APIError extends Error {
  constructor(
    public status: number,
    public code: string,
    public retryable = false,
  ) {
    super(code);
  }
}
export const invalid = () => new APIError(400, "invalid_request");
const bytes = (s: string) => new TextEncoder().encode(s).length;
// Recursive descent avoids JSON.parse's silent duplicate-key overwrite, including escaped keys.
export function strictJSON(text: string): unknown {
  let p = 0,
    depth = 0;
  const ws = () => {
    while (/[\x20\t\r\n]/.test(text[p] ?? "!")) p++;
  };
  const str = (): string => {
    const start = p++;
    while (p < text.length) {
      const c = text[p++];
      if (c === '"') {
        try {
          return JSON.parse(text.slice(start, p));
        } catch {
          throw invalid();
        }
      }
      if (c === "\\") p++;
      if (c.charCodeAt(0) < 32) throw invalid();
    }
    throw invalid();
  };
  const value = (): unknown => {
    ws();
    if (++depth > 20) throw invalid();
    let result: unknown;
    const c = text[p];
    if (c === '"') result = str();
    else if (c === "{" || c === "[") {
      p++;
      ws();
      const object = c === "{";
      const out: Record<string, unknown> = Object.create(null);
      const arr: unknown[] = [];
      const seen = new Set<string>();
      const end = object ? "}" : "]";
      if (text[p] !== end)
        while (true) {
          if (object) {
            if (text[p] !== '"') throw invalid();
            const key = str();
            if (seen.has(key)) throw invalid();
            seen.add(key);
            ws();
            if (text[p++] !== ":") throw invalid();
            out[key] = value();
          } else arr.push(value());
          ws();
          if (text[p] === end) break;
          if (text[p++] !== ",") throw invalid();
          ws();
        }
      p++;
      result = object ? out : arr;
    } else {
      const match =
        /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(
          text.slice(p),
        );
      if (!match) throw invalid();
      p += match[0].length;
      result = JSON.parse(match[0]);
      if (typeof result === "number" && !Number.isFinite(result))
        throw invalid();
    }
    depth--;
    return result;
  };
  const result = value();
  ws();
  if (p !== text.length) throw invalid();
  return result;
}
export async function boundedBody(
  response: Request | Response,
  max = 32768,
  deadlineMs?: number,
): Promise<string> {
  if (Number(response.headers.get("content-length") ?? 0) > max)
    throw new APIError(413, "invalid_request");
  const reader = response.body?.getReader();
  if (!reader) throw invalid();
  let size = 0;
  const chunks: Uint8Array[] = [];
  const readDeadline =
    deadlineMs ?? (response instanceof Request ? 3000 : 12000);
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    void reader.cancel().catch(() => {});
  }, readDeadline);
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > max) {
        await reader.cancel();
        throw new APIError(413, "invalid_request");
      }
      chunks.push(value);
    }
  } catch (e) {
    if (timedOut) throw new APIError(504, "deadline_exceeded", true);
    throw e;
  } finally {
    clearTimeout(timeout);
    reader.releaseLock();
  }
  if (timedOut) throw new APIError(504, "deadline_exceeded", true);
  const all = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    all.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(
      all,
    );
  } catch {
    throw invalid();
  }
}
export function object(
  value: unknown,
  keys: string[],
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw invalid();
  const o = value as Record<string, unknown>;
  if (
    Object.keys(o).length !== keys.length ||
    keys.some((k) => !Object.hasOwn(o, k))
  )
    throw invalid();
  return o;
}
export function string(
  value: unknown,
  chars: number,
  maxBytes = chars * 4,
): string {
  if (
    typeof value !== "string" ||
    [...value].length > chars ||
    bytes(value) > maxBytes ||
    /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value) ||
    /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(
      value,
    )
  )
    throw invalid();
  return value;
}
export function uuid(value: unknown): string {
  const s = string(value, 36, 36);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      s,
    )
  )
    throw invalid();
  return s.toLowerCase();
}
export function integer(value: unknown, min: number, max: number): number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < min ||
    value > max
  )
    throw invalid();
  return value;
}
export function version(o: Record<string, unknown>) {
  if (o.schema_version !== 1) throw new APIError(426, "upgrade_required");
}
export const SIGNALS = [
  "sensitive_config_read",
  "outbound_transfer",
  "task_mismatch",
  "reads_credential_store",
  "outbound_post",
  "writes_repo_config",
  "destructive_delete",
  "remote_endpoint_unfamiliar",
  "prompt_injection",
  "privilege_change",
  "untrusted_instructions",
  "session_drift",
];
export interface Analysis {
  schema_version: 1;
  request_id: string;
  device_id: string;
  session_pseudonym: string;
  source: "claude_code" | "codex";
  event: "pre_tool_use";
  deadline_ms: number;
  privacy_policy_version: 2;
  context: {
    task_summary: string;
    action_class: string;
    proposed_action_summary: string;
    local_signals: string[];
    recent_activity: string[];
    contains_code_excerpts: false;
  };
}
export function privacy(s: string) {
  const compact = s.replace(/\s/g, "");
  if (
    /(?:tr[di]_[a-f0-9]{64}|sk[-_](?:ant[-_])?[A-Za-z0-9_-]{8,}|(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]+|AKIA[A-Z0-9]{16}|ASIA[A-Z0-9]{16}|-----BEGIN.*PRIVATEKEY|data:.*base64|(?:token|password|secret|api[_-]?key|authorization)["']?[:=]|(?:\/Users\/|\/home\/|\/private\/|\/etc\/|[A-Z]:\\)|https?:\/\/|\b\d{1,3}(?:\.\d{1,3}){3}\b)/i.test(
      compact,
    ) ||
    /(?:^|[\s"'=])\/(?:[A-Za-z0-9._-]+\/|(?:tmp|var|opt|root|etc|Users|home)\b)/.test(
      s,
    ) ||
    /\b[A-Z_][A-Z0-9_]{1,64}\s*=/.test(s) ||
    /\b\d{1,3}(?:\.\d{1,3}){3}\b/.test(s) ||
    /\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|dev|net|org|io|ai|internal|local)\b/i.test(
      s,
    ) ||
    s.split(/\s+/).some((t) => {
      if (
        !/^[A-Za-z0-9+/_=-]{32,}$/.test(t) ||
        !((/[A-Z]/.test(t) && /[a-z]/.test(t)) || /[0-9+/_=-]/.test(t))
      )
        return false;
      const counts = new Map<string, number>();
      for (const c of t) counts.set(c, (counts.get(c) ?? 0) + 1);
      let entropy = 0;
      for (const n of counts.values()) {
        const p = n / t.length;
        entropy -= p * Math.log2(p);
      }
      return entropy > 3.5;
    })
  )
    throw invalid();
}
export function analysis(value: unknown): Analysis {
  const o = object(value, [
    "schema_version",
    "request_id",
    "device_id",
    "session_pseudonym",
    "source",
    "event",
    "deadline_ms",
    "privacy_policy_version",
    "context",
  ]);
  version(o);
  if (o.privacy_policy_version !== 2)
    throw new APIError(403, "consent_required");
  o.device_id = uuid(o.device_id);
  o.request_id = uuid(o.request_id);
  o.session_pseudonym = uuid(o.session_pseudonym);
  integer(o.deadline_ms, 1000, 12000);
  if (
    !["claude_code", "codex"].includes(o.source as string) ||
    o.event !== "pre_tool_use"
  )
    throw invalid();
  const c = object(o.context, [
    "task_summary",
    "action_class",
    "proposed_action_summary",
    "local_signals",
    "recent_activity",
    "contains_code_excerpts",
  ]);
  string(c.task_summary, 512, 1024);
  string(c.proposed_action_summary, 1024, 2048);
  if (
    !["shell_exec", "file_read", "file_write", "network", "other"].includes(
      c.action_class as string,
    ) ||
    c.contains_code_excerpts !== false
  )
    throw invalid();
  if (
    !Array.isArray(c.local_signals) ||
    c.local_signals.length > 12 ||
    new Set(c.local_signals).size !== c.local_signals.length ||
    c.local_signals.some((s) => !SIGNALS.includes(s))
  )
    throw invalid();
  if (!Array.isArray(c.recent_activity) || c.recent_activity.length > 6)
    throw invalid();
  for (const s of c.recent_activity) string(s, 160, 512);
  for (const s of [
    c.task_summary,
    c.proposed_action_summary,
    ...c.recent_activity,
  ])
    privacy(s as string);
  return o as unknown as Analysis;
}
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object") {
    const o = value as Record<string, unknown>;
    return (
      "{" +
      Object.keys(o)
        .sort()
        .map((k) => JSON.stringify(k) + ":" + canonical(o[k]))
        .join(",") +
      "}"
    );
  }
  return JSON.stringify(value);
}
export async function digest(value: string): Promise<string> {
  const b = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(b)]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
export async function hmac(secret: string, value: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const b = await crypto.subtle.sign(
    "HMAC",
    k,
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(b)]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
export function token(): string {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return "trd_" + [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

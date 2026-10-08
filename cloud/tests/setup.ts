import { beforeEach, afterEach, inject, vi, expect } from "vitest";
import { env, applyD1Migrations, reset } from "cloudflare:test";
export const replies: Array<{
  body: string;
  status: number;
  delay: number;
  headers: Record<string, string>;
}> = [];
export const upstreamCalls: Array<{ url: string; options: RequestInit }> = [];
beforeEach(async () => {
  await reset();
  await applyD1Migrations(env.DB, inject("migrations"));
  Object.assign(env, {
    CLOUD_ANALYSIS_ENABLED: "true",
    GLOBAL_MONTHLY_CAP_MICRO_USD: "null",
    INPUT_PRICE_MICRO_USD_PER_TOKEN: "1",
    OUTPUT_PRICE_MICRO_USD_PER_TOKEN: "5",
    DAILY_EVALUATION_LIMIT: "null",
    DAILY_INPUT_TOKEN_LIMIT: "null",
    DAILY_OUTPUT_TOKEN_LIMIT: "null",
  });
  replies.length = 0;
  upstreamCalls.length = 0;
  vi.stubGlobal("fetch", async (url: string, options: RequestInit) => {
    upstreamCalls.push({ url, options });
    if (url !== "https://api.anthropic.com/v1/messages")
      throw new Error("unexpected egress");
    const r = replies.shift();
    if (!r) throw new Error("unconfigured upstream");
    if (r.delay)
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(resolve, r.delay);
        options.signal?.addEventListener(
          "abort",
          () => {
            clearTimeout(timer);
            reject(new Error("aborted"));
          },
          { once: true },
        );
      });
    return new Response(r.body, { status: r.status, headers: r.headers });
  });
});
afterEach(() => {
  expect(replies).toHaveLength(0);
  vi.unstubAllGlobals();
});

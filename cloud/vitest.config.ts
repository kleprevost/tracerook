import { defineConfig } from "vitest/config";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc", environment: "staging" },
      miniflare: {
        bindings: {
          AUTH_DIGEST_KEY: "test-only-digest-key-not-a-real-credential-0000",
          ANTHROPIC_API_KEY: "test-only-not-a-real-key",
          CLOUD_ANALYSIS_ENABLED: "true",
          GLOBAL_MONTHLY_CAP_MICRO_USD: "null",
          INPUT_PRICE_MICRO_USD_PER_TOKEN: "1",
          OUTPUT_PRICE_MICRO_USD_PER_TOKEN: "5",
          DAILY_EVALUATION_LIMIT: "null",
          DAILY_INPUT_TOKEN_LIMIT: "null",
          DAILY_OUTPUT_TOKEN_LIMIT: "null",
        },
      },
    }),
  ],
  test: {
    fileParallelism: false,
    setupFiles: ["./tests/setup.ts"],
    provide: { migrations: await readD1Migrations("./migrations") },
    testTimeout: 15000,
  },
});

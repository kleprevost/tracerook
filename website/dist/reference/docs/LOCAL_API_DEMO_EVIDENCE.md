# Connected local API demonstration — 2026-10-08

The native app now connects to the local mock backend supplied on `claude/zealous-einstein-nxxnwd`, with reviewed hardening from a Sol subagent. This implements the user's local-only demonstration scope. It does not complete the hosted MVP3 alpha or operational MVP2 protection.

## Implemented boundary

SwiftUI → authenticated XPC → TraceRookAgent → fixed `http://127.0.0.1:8787/mock/v1/` → strict synthetic response validation → native result. Only the explicitly marked ad-hoc developer service instantiates this client. Developer ID mode refuses these demo controls.

The service owns HTTP and transient mock credentials. The UI previews exactly the fixed sample bytes sent on Run sample and receives no token. Separate request, response and control types cannot become live provider results, hook replies or review resolutions. Simulation, fixture provenance and zero inference/billing values are mandatory. Critical verdicts, extra permission fields, arbitrary contexts and unsafe returned text are rejected.

Transport has an ephemeral session, no cache/cookies/credential store/proxies/redirects, a fixed loopback origin, a 32 KiB streamed response bound and monotonic deadline. There are no automatic analysis retries. Disconnect cancels in-flight work; generation checks in the client and UI prevent late receipts from restoring results. Successful usage refresh preserves the previously validated fixture; failed analysis removes it.

The backend default factory mounts only the mock namespace, never instantiates the legacy analyzer/database, and requires real bearer authentication on protected routes. Random tokens are held transiently by the service and as digests by the server. Actual expiry, principal matching, rotation, revocation, deletion, concurrent idempotency, cardinality bounds and a 30-fixture daily quota are enforced. Metadata resets on restart. Browser Origin, unexpected Host, queries, non-loopback callers, malformed/duplicate/unknown JSON and oversized input are rejected.

## Automated and actual process evidence

- **64 Swift test functions pass**, including a 50-case shell corpus, six parameterized mock scenarios, strict wire/provenance/binding rejection, credential exclusion, wrong-device rejection before HTTP, no retry on timeout, in-flight cancellation, developer-only controls, replay rejection and unchanged history.
- **103 backend tests pass**, including the actual loopback HTTP subprocess test, auth lifecycle, privacy/input bounds, default factory isolation and fake Anthropic SDK tests.
- The debug app/service/helper compile; **22 native light/dark render cases** pass. The current source also builds in release mode as recorded separately in the implementation log.
- `TraceRook --local-api-smoke-test` was run against the actual signed local service and Uvicorn process. Benign, credential-transfer and task-drift fixtures validate. Provider-unavailable, quota-exhausted and deadline-exceeded return typed failures with no verdict. Rotation, measured fixture usage, deletion/revocation and unchanged live session/incident/approval IDs pass.
- Actual GUI controls enroll and run a credential-transfer fixture. The visible result says **FIXTURE · ZERO CLAUDE TOKENS**, gives `fixture / local_mock / synthetic-v1` provenance and labels the recommendation advisory. Selecting provider-unavailable clears the result and displays the typed simulated error. Actual coverage remains **Not integrated** with zero observed host sessions.

Ignored local artifacts: `build/mvp2-live/api-client-tests-final.log`, `backend-final.log`, `ui-api-final.log`, `native-api-final.log`, `native-api-result.png`, `native-api-outage.png`, and `build/ui-smoke/*-local-api-demo.png`. These are development evidence, not production performance or efficacy measurements.

## Separate real Anthropic probe

The user explicitly supplied a credential for testing Haiku 5.5. A separate developer diagnostic made one first-party Models lookup and one bounded Messages request with predefined synthetic benign context. It validated model **`claude-haiku-5-5`**, one structured verdict, **798 input tokens**, **178 output tokens**, and **3,006 ms** elapsed. No retries, fallback, tools, host data or repository content were sent.

The key was supplied through masked transient stdin, not source, files, environment variables, command arguments, logs or the website. The upstream body and verdict text were not retained. This evidence establishes one actual model/API test. It does not establish native real inference, a deployed proprietary backend, customer enrollment, production quotas or host protection. The default mock still makes zero Claude calls.

Per the user's explicit model choice, the separate legacy analyzer now defaults to Haiku 5.5 with low effort and structured output. It is not mounted by the mock factory and retains its older flat protocol. It does not implement hosted MVP3. See [deviations](MVP3_DEVIATIONS.md), [backend instructions](../backend/LOCAL_MOCK.md), and the [official Haiku migration guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide).

## Reproduce without a real key

Run the server using [backend/LOCAL_MOCK.md](../backend/LOCAL_MOCK.md). Build the app with `./scripts/build.sh`, enable the background service in Integrations after reviewing its configuration, and open Settings → Local API Demo. Select synthetic-only consent, Connect local mock, review the sample JSON and Run sample. Stop the server with Control-C and disable the service through Integrations when finished.

Backend tests require port 8787 free: `backend/.venv/bin/python -m pytest -q backend/tests`. Native tests: `./scripts/test.sh`. Render checks: `./scripts/ui-smoke-test.sh`. The native full-path smoke requires an already running matching signed-family service and mock server; it installs neither and tests disposable mock data only.

## Remaining gates

No API backend is deployed. The static Cloudflare website makes no analysis requests and this work adds no paid resources. Native direct BYOK, Keychain and real-event privacy consent remain unavailable. Hosted canonical Cloud v1, server-owned inference, durable production quotas/spend controls, scoped enrollment, retention and operational acceptance remain open. Agent hooks, safe host configuration, native trust, real pre-execution canary denial and actual native approval/notification flow remain open. Non-notarized builds do not establish Developer ID or Gatekeeper acceptance.

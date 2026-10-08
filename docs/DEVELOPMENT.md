# Developing TraceRook

## Requirements

- Apple Silicon (`arm64`) Mac, macOS 26 or later.
- Swift 6 and the macOS 27 SDK. Full Xcode 27 builds archives; Command Line Tools builds the app with the repository scripts.
- Node 24+ for TraceRook Cloud, Python 3.11+ for the local API and website tooling.

## Mac app

```sh
./scripts/build.sh                       # debug; ./scripts/build.sh release for optimized
open build/TraceRook.app
open build/TraceRook.app --args --demo   # bundled sample sessions, incidents and reviews
```

Open `TraceRook.xcodeproj` and select the TraceRook scheme for Xcode development. Build settings restrict CPU to arm64, deployment to macOS 26.0 and Swift language mode to 6, with hardened runtime enabled. Builds are ad-hoc signed unless `TRACEROOK_SIGNING_IDENTITY` names a signing identity.

The bundle contains the `TraceRookAgent` service, the `tracerook-hook` bridge and the LaunchAgent plist. Both helpers support `--version`, `--protocol-version` and `--self-test`. `--appearance-light` / `--appearance-dark` force an appearance and `--launch-smoke-test` verifies that the dashboard window opens.

When adding executable source files, synchronize the Xcode project:

```sh
python3 scripts/update-xcode-sources.py
```

### Tests

```sh
./scripts/test.sh              # Swift Testing suites
./scripts/smoke-test.sh        # tests, build, packaged helpers and bundle checks
./scripts/ui-smoke-test.sh     # light/dark UI renders under build/ui-smoke/
./scripts/bundle-smoke-test.sh # relocated release bundle
./scripts/beta-e2e.sh --local  # service, adapter, rules, privacy, contracts and core suites
```

`scripts/test.sh` supplies the Swift Testing framework path that Command Line Tools installations need.

## TraceRook Cloud

```sh
cd cloud
npm ci
npm run typecheck
npm test
```

Tests run inside workerd with real D1 and Durable Object bindings and a fake Anthropic transport. Deployment, secrets and invitations are covered in [cloud/README.md](../cloud/README.md); the protocol is in [cloud/CONTRACT.md](../cloud/CONTRACT.md).

## Local API

```sh
cd backend
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
.venv/bin/pytest -q
.venv/bin/python -m uvicorn tracerook_backend.app:app_factory --factory --host 127.0.0.1 --port 8787 --no-access-log
```

See [backend/README.md](../backend/README.md).

## Website

```sh
python3 website/scripts/build.py
python3 website/scripts/check.py
node --check website/dist/assets/site.js
node website/scripts/preview.mjs        # http://127.0.0.1:4173/
```

See [website/README.md](../website/README.md).

## Source layout

| Directory | Purpose |
| --- | --- |
| `App/` | SwiftUI interface and AppKit review window |
| `Agent/` | Background service |
| `HookCLI/` | Host bridge |
| `Packages/` | Shared contracts, adapters, privacy, rules, core and fixtures |
| `Tests/` | Swift Testing cases |
| `Resources/` | App icon, Info.plist and LaunchAgent |
| `cloud/` | TraceRook Cloud Worker |
| `backend/` | Local API |
| `website/` | Static site and documentation |
| `scripts/` | Build, test and packaging scripts |

## Contribution expectations

Keep sample data clearly labeled, preserve unrelated user configuration, and reject unsafe or incomplete remote payloads rather than repairing them. New security behavior ships with tests that exercise its rejection paths.

# TraceRook invited beta

Release preparation: **0.1.0-beta.1**, for an initial group of ten testers. No public download has been published by this preparation. Read the manifest delivered with your ZIP for the actual bundle version, build, and checksum.

## Requirements and current scope

Use an **Apple Silicon Mac running macOS 26 or later**. Intel Macs are unsupported. Building from source requires Swift 6 and the macOS 27 SDK; full Xcode 27 is required for Xcode archives. The developer host uses macOS 27; macOS 26 and a clean tester installation remain separate acceptance checks.

The native dashboard, explicitly labeled offline Cloud Demo, authenticated local service, private SQLite history, synthetic Local API Demo, and exact-action review UI are implemented. The Cloud API is deployed at `https://api.tracerook.dev`; production HTTPS rejects unauthenticated requests, and 59 Worker tests pass. Genuine hosted Haiku inference and the complete signed native host-to-Cloud-to-Claude-to-human-review path have passed. A native receipt recorded 929 input tokens, 232 output tokens, and 2.751 seconds. An actual Claude Code 2.1.290 Bash action requested Cloud human review, native Allow once released its harmless sentinel, and a separate deterministic critical action was denied with its sentinel absent. The broader hosted evaluation corpus remains in progress. The installed Claude Code **2.1.290** passed actual synchronous callback allow/deny, bounded timeout denial, and high-risk service-outage denial tests. Actual native Allow once and Block also passed against Claude Code 2.1.290 with the signed app/helper/service: the harmless sentinel executed only after Allow once, while Block left it absent. Both decisions used the service-owned exact invocation binding. The earlier local callback and human-review cases used a local model double; the later full Cloud path has genuine Anthropic receipt evidence. Codex remains unverified. See [implementation checkpoint](CLOUD_ALPHA_IMPLEMENTATION.md), [acceptance matrix](MVP3_ACCEPTANCE.md), and [agent compatibility](AGENT_COMPATIBILITY.md) before relying on any integration.

The initial beta uses existing **ad-hoc code signatures**. It has no Developer ID identity and is **not notarized by Apple**. A passing signature check verifies bundle integrity; it does not establish publisher identity or Apple malware review. Packaging does not establish protection, Cloud availability, or successful installation on another Mac.

## Download and open

1. Obtain the versioned ZIP, matching manifest, and SHA256SUMS directly from the release supplied to you by the project owner.
2. In the folder containing all three files, run `shasum -a 256 -c TraceRook-0.1.0-beta.1-macOS-arm64-SHA256SUMS`. Both entries must report `OK`; otherwise request a fresh copy.
3. Expand the ZIP with Archive Utility. Move `TraceRook.app` to your Applications folder using Finder, then open it.
4. If macOS blocks this non-notarized app, follow Apple's documented exception workflow only after verifying the source and checksum: attempt to open it, then visit **System Settings → Privacy & Security → Open Anyway** and confirm the named app. The option may be unavailable on managed Macs. See [Apple: safely open apps on your Mac](https://support.apple.com/en-us/102445).

Do not disable Gatekeeper globally or remove quarantine attributes as a shortcut. Do not override a malware or damaged-app warning; report the exact warning to the owner. If your Mac's policy prevents the exception, this release cannot be tested there.

Start with the labeled Demo view. Demo findings and approvals are examples. Keep Cloud connectivity and host integration status separate: a connected provider does not establish that a host runs the hook before execution. Configure a host only using the supported manual instructions and exact tested scope in the compatibility guide; merely installing Claude Code or Codex does not enable protection. Automatic installation, repair, and uninstall are outside this release.

## Connect an invited Cloud session

Open **Settings → AI Provider → TraceRook Cloud**, enter the beta access code supplied separately by the owner, and accept the displayed privacy consent. The background service holds the device credential only in session memory. No Keychain access occurs, and access must be entered again after the service restarts. Never put access codes in agent configuration, shell arguments, screenshots, or bug reports. Your own Anthropic key is not required; direct BYOK is unavailable.

Cloud enrollment, the local analysis switch, and a validated Claude response are separate states. An enrolled device does not prove inference occurred. Settings displays the operator availability and whether Cloud is selected for host analysis. Use its explicit pause/resume controls; choosing Demo or Local pauses Cloud in the service before the view changes. If the service is unavailable, Demo can still render fixtures with a persistent warning that the background analysis state cannot be verified. This warning does not promise the whole Mac is offline.

The Cloud request contains coarse task/action categories and enumerated local signals, rather than raw commands, code, file contents, paths, or transcripts. Read the displayed consent and privacy policy before connecting. Local policy retains authority over critical denials; model findings cannot grant native agent permissions.

## Configure and verify a manual Claude hook

The owner must first supply the supported service-start instructions for this ad-hoc bundle. Confirm the service is connected in Integrations; opening the app alone does not prove background registration. Automatic host installation, repair, and uninstall are outside this beta.

For Claude Code **2.1.290**, review the existing hook configuration and retain unrelated settings and hooks. Add a synchronous command hook to the intended configuration scope. Replace the app path with the actual installed path; keep the quoted executable path. The following is a configuration fragment, not a command to overwrite your settings file:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "\"/Applications/TraceRook.app/Contents/MacOS/tracerook-hook\" --adapter claude_code --host-version 2.1.290 --timeout-ms 80000",
        "timeout": 80
      }]
    }]
  }
}
```

Follow [Claude's hook reference](https://code.claude.com/docs/en/hooks) for the supported configuration scope and reload behavior. Never configure this as an asynchronous hook. A hook that is skipped or hits the host's own timeout can permit execution. Configuration, an executable self-test, or successful Cloud enrollment does not establish coverage.

Verify a benign callback, a harmless deterministic-denial canary whose file remains absent, and bounded failure handling on the installed host and final helper. Record the host version, helper digest, tool class, timestamp, and execution evidence. [The beta execution evidence](BETA_E2E_EVIDENCE.md) distinguishes actual callbacks, local model doubles, and genuine provider receipts. A host upgrade or changed hook/binary requires renewed verification. The app must not advertise Protected solely because a hook file exists. Codex's trust workflow and actual Bash/apply_patch gates remain pending; do not infer Codex protection from Claude results.

## Create release artifacts

After the release owner completes the build and applicable checks:

```sh
./scripts/package-beta.sh --app build/TraceRook.app \
  --version 0.1.0-beta.1 --output build/beta
```

The script copies the existing bundle with `ditto`, verifies ad-hoc signature integrity and arm64 executables, creates a resource-preserving ZIP, extracts it into a temporary folder, and checks signatures and file hashes again. It never builds, modifies, or re-signs the app. Keep the source bundle unchanged while packaging; changed bytes abort publication. Existing artifact names are never overwritten.

Outputs are a versioned ZIP, JSON release manifest, and SHA256SUMS covering both. The manifest records the original signed bundle version/build independently of the beta archive label. Its packaging checkout SHA and dirty flag describe the checkout at packaging time, not verified build provenance. Preserve the owner's build/test evidence with the release.

Before sending a download, record the final evidence in the acceptance documents and confirm the actual artifact checksum. An archive in `build/beta` is a local preparation artifact; it is not a GitHub release or deployed website download.

## Feedback and limits

Report the archive version, macOS version, agent version, integration status, reproduction steps, and any visible failure. Review screenshots and logs for secrets, prompts, command arguments, paths, and personal data before sharing. Send reports through the channel provided with your invitation; the static website has no account, payment, or upload form.

The intended alpha price is $20/month. Payment collection and subscriptions are not implemented. No software inference allotment is promised; provider availability and platform limits still apply. See [security limitations](../SECURITY_LIMITATIONS.md) and [privacy](PRIVACY.md) for the boundaries.


## Final local regression · 2026-10-08

`./scripts/beta-e2e.sh --local` passed **81 tests, zero failures** against the current source using an isolated Swift scratch directory under `build/beta-verification`. The filter covers Service, Adapter, Rules, Privacy, Contracts, and Core. This run made no Keychain calls or Cloud requests and did not rebuild the shared app bundle, modify host configuration, or stop the running service. Cloud tests used injected fake transports. This regression is separate from actual host, native UI, and hosted-provider acceptance.

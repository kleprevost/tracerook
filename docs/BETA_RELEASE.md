# Install the TraceRook beta

Current release: [**0.1.0-beta.1**](https://github.com/kleprevost/tracerook/releases/tag/v0.1.0-beta.1) for Apple Silicon Macs running macOS 26 or later.

TraceRook is in an invitation-only private beta. Your invitation includes the TraceRook Cloud access code used in step 4; [request an invitation](https://tracerook.dev/register/) if you don't have one. Billing isn't active during the beta.

## 1. Download and verify

1. Download the ZIP, its manifest and `SHA256SUMS` from [GitHub Releases](https://github.com/kleprevost/tracerook/releases/tag/v0.1.0-beta.1).
2. In the folder containing all three files, run:

   ```sh
   shasum -a 256 -c TraceRook-0.1.0-beta.1-macOS-arm64-SHA256SUMS
   ```

   Both entries report `OK`.
3. Expand the ZIP and move `TraceRook.app` to **Applications**.

## 2. Open the app

Beta builds are distributed outside the Mac App Store. The first time you open TraceRook, macOS asks you to confirm it: open the app once, then go to **System Settings → Privacy & Security** and choose **Open Anyway** next to TraceRook. ([Apple: safely open apps on your Mac](https://support.apple.com/en-us/102445))

## 3. Start the background service

Open **Integrations → Enable Background Service**, review the LaunchAgent destination and executable path, and confirm. TraceRook installs `~/Library/LaunchAgents/com.tracerook.agent.local.plist` and starts the bundled service. Integrations shows **Connected** when it is running. If macOS asks for background-item approval, allow TraceRook in **System Settings → General → Login Items**.

## 4. Connect TraceRook Cloud

Open **Settings → AI Provider → TraceRook Cloud**, enter the access code that came with your invitation, review the privacy consent and select **Connect to TraceRook Cloud**. The service keeps the device credential in memory; enter the access code again after the service restarts. Keep access codes out of agent configuration, shell history and screenshots.

## 5. Configure Claude Code

Add a synchronous `PreToolUse` command hook to your Claude Code settings, keeping your existing settings and hooks:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "\"/Applications/TraceRook.app/Contents/MacOS/tracerook-hook\" --adapter claude_code --host-version 2.1.290 --timeout-ms 80000",
        "timeout": 85
      }]
    }]
  }
}
```

Use the path where you installed the app. See [Claude Code hooks](https://code.claude.com/docs/en/hooks) for configuration scopes and reload behavior.

## 6. Check it works

Select **Test Hook** in Integrations. Then start a Claude Code session and ask it for something harmless; the session appears in **Sessions** with each tool call and its decision. To see a review, ask the agent to run a high-risk command such as fetching and executing a remote script: TraceRook pauses it, sends a notification, and waits for **Allow once** or **Block**.

## Feedback

Send reports to [kyle@tracerook.dev](mailto:kyle@tracerook.dev) or [john@tracerook.dev](mailto:john@tracerook.dev), or through the channel in your invitation, with the app version, macOS version, Claude Code version and reproduction steps. Remove secrets, prompts and private paths from screenshots and logs first.

## Packaging a release

```sh
./scripts/package-beta.sh --app build/TraceRook.app --version 0.1.0-beta.1 --output build/beta
```

The script copies the built bundle with `ditto`, verifies signatures and arm64 executables, creates a resource-preserving ZIP, round-trips it, and writes a JSON manifest and `SHA256SUMS`. It never rebuilds or re-signs the app and never overwrites existing artifacts.

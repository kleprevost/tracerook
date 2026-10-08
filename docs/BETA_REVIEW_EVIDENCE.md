# Native review evidence

Status: actual Claude Code Allow Once retry and Block review passed, paired with real native UI action-binding screenshots. The first Allow Once attempt failed closed and remains documented. Coverage is limited to the tested Claude Code Bash hook path; these runs do not verify cloud classification or other host/tool classes.

The harness uses the installed Claude Code CLI with its normal synchronous PreToolUse command hook and a localhost Messages/SSE model double. It sends `sudo --version; printf reviewed > review-sentinel` inside a disposable private project. `sudo --version` requests no privileged mutation. The local privilege-elevation rule must create a service-owned review; the sentinel can run only after that waiting invocation returns without a TraceRook denial. Native host permission checks continue to apply.

The operator must start the stable signed app/service and select Local Rules Only before launching either run. The loopback model double replaces the host's model endpoint; it does not replace TraceRook's cloud provider. Pausing cloud analysis is required to keep this review test free of provider calls.

Launch from the repository with fresh, absolute evidence paths:

```sh
python3 scripts/test-support/beta-review-callback.py \
  --helper /absolute/stable/TraceRook.app/Contents/Helpers/tracerook-hook \
  --choice allow --coordinated \
  --ready-file /absolute/workspace/build/beta-review-allow-ready.json \
  --receipt /absolute/workspace/build/beta-review-allow.json
```

For the second run use `--choice block` and new `beta-review-block-ready.json` / `beta-review-block.json` paths. The harness refuses to overwrite existing evidence.

After the ready file appears, the coordinator opens the real native Approvals queue and clicks Allow Once or Block on the new waiting action, matching the requested choice. The helper has a 50-second total budget, the host hook allows 60 seconds, and service review expires after at most 45 seconds. Complete the UI choice promptly. A callback lasting 42 seconds or more fails this harness, preventing an unclicked expiry from passing as a successful block review.

The harness never submits a review resolution, edits approval storage, uses a permission bypass, or supplies real provider credentials. Host settings, dummy host API authentication, callback payload logs, and the sentinel exist only in private temporary directories and are removed after the run. Public receipts contain aggregate host behavior and the installed host version.

Acceptance requires both evidence sources:

| Choice | Actual host receipt | Native/service evidence |
| --- | --- | --- |
| Allow Once | Exactly one callback, empty helper stdout with exit 0, sentinel present, timely completion | Real UI click and the same exact binding persisted as `approved_once` |
| Block | Exactly one callback, supported deny output, sentinel absent, timely completion | Real UI click and the same exact binding persisted as `denied`, rather than `expired` or `aborted` |

The receipt deliberately states that the native UI choice requires persisted approval evidence. Empty host stdout alone does not prove human approval, and a deny alone does not prove a Block click. Pair the host receipt with the native screenshot/service snapshot and invocation binding before marking either row passed. No hook decision proves wider sandbox enforcement or untested host classes.

## Run records

- Allow Once attempt 1: failed. `build/beta-review-allow.json` records one actual callback, 49.067 seconds in the callback, denial output, absent sentinel, and host exit 0. The timed review did not return an approval, and the run exceeded the 42-second acceptance threshold. Native/service evidence is required to determine why the review did not complete.
- Allow Once retry: passed. `build/beta-review-allow-retry.json` records one callback, 15.614 seconds, empty helper stdout/no override, sentinel present, and host exit 0. The coordinator clicked the real native Allow Once button. `build/beta-review-allowed.png` shows the resolved `Allowed once` state and exact Review ID `C34A89F3-CD05-4029-834B-350679D86547`, with the action/tool-call digests visible.
- Block: passed. `build/beta-review-block.json` records one callback, 27.701 seconds, supported denial, sentinel absent, and host exit 0. The coordinator clicked the real native Block button. `build/beta-review-blocked.png` shows the resolved `Blocked` state (not expired) and exact Review ID `D5E76173-54D6-45B9-83D1-5ADF654C0287`, with the action/tool-call digests visible.
- Installed Claude version for all runs: `2.1.290 (Claude Code)`.
- Stable signed hook SHA-256: `3cb47c60071ef2dab08ae594f54f7e9c573fe8ac7b3eb31d431dd5a49433cb07`.
- Stable signed service executable SHA-256: `ee17b5b81a780995d8b6c2356113500c77bd5a66541f6aee6a369e93978bcf5b`.
- Native screenshots were visually checked against the matching Review IDs and terminal states above. The signed native UI displays service snapshot records; no direct approval-store mutation or synthetic review resolution was used.
- Cloud analysis was paused for these local review tests. The app continues to display `Not integrated` until broader integration evidence supports a protection claim.

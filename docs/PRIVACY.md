# Privacy

## On your Mac

Hook input is inspected in memory. Normalized events omit raw tool arguments, and secrets are replaced with category placeholders (`[REDACTED:TOKEN]`, `[REDACTED:PRIVATE_KEY]`, …) that cannot be reversed. Logs contain only predefined status codes and random identifiers. Local history lives in `~/Library/Application Support/TraceRook/history.sqlite3` (directory `0700`, files `0600`) and keeps events for 14 days and incidents and reviews for 30 days. **Delete All Local History** clears it at any time.

## Sent to TraceRook Cloud

When an action needs contextual analysis, the service sends a projection of it: a coarse task category, a coarse action category and enumerated local signal codes such as `outbound_transfer` or `reads_credential_store`. Raw commands, paths, code, file contents, transcripts and free-form prose are not included. A secret, path, URL and entropy scan runs on the projection before it is sent, and again in TraceRook Cloud. Cloud analysis starts only after you accept the consent screen in **Settings → AI Provider → TraceRook Cloud**.

## In TraceRook Cloud

TraceRook Cloud forwards the projection to Anthropic Claude under Anthropic's commercial API terms. It keeps:

| Data | Retention |
| --- | --- |
| Account and device digests | Until you delete your account |
| Analysis receipts (identifiers, token counts, timestamps) | 30 days |
| Usage aggregates | 90 days |
| Verdict cache for retried requests | 10 minutes |

Prompts, model explanations and request bodies are not stored or logged. **Delete cloud account data** in Settings removes your account metadata and revokes every enrolled device.

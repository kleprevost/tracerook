# Privacy

Cloud Demo reads only bundled fixture JSON and makes no network requests. The app must visibly distinguish it from actual sessions. The current build does not read transcripts, repository contents or real agent hook inputs to populate the dashboard.

Normalized events intentionally omit raw tool arguments. Stable redaction placeholders describe secret categories and are not recoverable hashes. Logs accept only predefined status codes and random identifiers. Errors are displayed using fixed messages rather than interpolating raw payloads or provider responses.

Planned BYOK sends selected redacted context directly to Anthropic, only after user consent. Redaction cannot guarantee removal of every secret. Provider retention is governed by the user's Anthropic terms, separately from local history retention (events 14 days; incidents/approvals 30 days by default). Additional code excerpts default off.

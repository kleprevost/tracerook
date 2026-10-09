-- Beta invitation requests written by functions/api/beta/request.js (D1 binding DB).
-- Apply once: npx wrangler d1 execute tracerook-signups --remote --file website/signups-schema.sql
CREATE TABLE IF NOT EXISTS beta_requests (
  id INTEGER PRIMARY KEY,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  use_case TEXT NOT NULL DEFAULT ''
);

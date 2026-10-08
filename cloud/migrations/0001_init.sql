-- Metadata only. All auth mutations serialize through one SQLite Durable Object.
CREATE TABLE accounts (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL);
CREATE TABLE invites (id TEXT PRIMARY KEY, invite_digest TEXT UNIQUE NOT NULL, account_id TEXT NOT NULL REFERENCES accounts(id), expires_at INTEGER NOT NULL, max_uses INTEGER NOT NULL DEFAULT 1 CHECK(max_uses>0), uses INTEGER NOT NULL DEFAULT 0, revoked_at INTEGER);
CREATE TABLE devices (id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), token_digest TEXT UNIQUE NOT NULL, expires_at INTEGER NOT NULL, app_version TEXT NOT NULL, created_at INTEGER NOT NULL, revoked_at INTEGER);
CREATE INDEX devices_account ON devices(account_id);
CREATE TABLE analysis_receipts (analysis_id TEXT PRIMARY KEY, account_id TEXT NOT NULL, device_id TEXT NOT NULL, request_id TEXT NOT NULL, model_id TEXT NOT NULL, upstream_request_id TEXT NOT NULL, trace_id TEXT NOT NULL, input_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL, elapsed_ms INTEGER NOT NULL, created_at INTEGER NOT NULL, delete_after INTEGER NOT NULL);
CREATE INDEX receipts_expiry ON analysis_receipts(delete_after);

CREATE INDEX invites_expiry ON invites(expires_at);

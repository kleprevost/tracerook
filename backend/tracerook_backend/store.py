"""SQLite persistence. Stores accounts, hashed API keys, devices and usage *metadata* only.
No analyzed content (task anchors, actions, events, verdicts) is ever written here.

One shared connection guarded by a lock; callers run these methods in a worker thread.
SQLite/WAL is right for a single-host launch; the Store interface is the seam for Postgres."""
from __future__ import annotations

import os
import sqlite3
import threading
import uuid
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from typing import Any

ACCOUNT_STATES = ("active", "past_due", "canceled", "suspended")
PENDING_TTL = timedelta(minutes=5)

_MIGRATIONS = [
    """
    CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        plan TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('active','past_due','canceled','suspended')),
        created_at TEXT NOT NULL
    );
    CREATE TABLE api_keys (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        key_hash TEXT NOT NULL UNIQUE,
        prefix TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_used_at TEXT,
        revoked_at TEXT
    );
    CREATE INDEX api_keys_account ON api_keys(account_id);
    CREATE TABLE devices (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        installation_id TEXT,
        label TEXT,
        created_at TEXT NOT NULL,
        last_seen_at TEXT NOT NULL,
        UNIQUE (account_id, installation_id)
    );
    CREATE TABLE usage_events (
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        request_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        day TEXT NOT NULL,                       -- UTC YYYY-MM-DD
        outcome TEXT NOT NULL CHECK (outcome IN ('pending','ok','abandoned')),
        billed_units INTEGER NOT NULL,
        tokens_in INTEGER NOT NULL DEFAULT 0,
        tokens_out INTEGER NOT NULL DEFAULT 0,
        model_id TEXT,
        latency_ms INTEGER,
        created_at TEXT NOT NULL,
        PRIMARY KEY (account_id, request_id)
    );
    CREATE INDEX usage_account_day ON usage_events(account_id, day);
    """,
]


def iso(dt: datetime) -> str:
    return dt.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


class Store:
    def __init__(self, path: str, clock: Callable[[], datetime] | None = None):
        self._clock = clock or (lambda: datetime.now(UTC))
        self._lock = threading.RLock()
        if path != ":memory:":
            directory = os.path.dirname(os.path.abspath(path))
            os.makedirs(directory, mode=0o700, exist_ok=True)
            old = os.umask(0o077)
            try:
                self._db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
            finally:
                os.umask(old)
            self._db.execute("PRAGMA journal_mode=WAL")
        else:
            self._db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA foreign_keys=ON")
        self._db.execute("PRAGMA busy_timeout=5000")
        self._migrate()

    def close(self) -> None:
        with self._lock:
            self._db.close()

    @contextmanager
    def _tx(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            self._db.execute("BEGIN IMMEDIATE")
            try:
                yield self._db
            except BaseException:
                self._db.execute("ROLLBACK")
                raise
            else:
                self._db.execute("COMMIT")

    def _migrate(self) -> None:
        with self._tx() as db:
            db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)")
            current = db.execute("SELECT COALESCE(MAX(version), 0) FROM schema_migrations").fetchone()[0]
            if current > len(_MIGRATIONS):
                raise RuntimeError("Database is newer than this server")
            for version, script in enumerate(_MIGRATIONS, start=1):
                if version > current:
                    for statement in script.split(";"):
                        if statement.strip():
                            db.execute(statement)
                    db.execute("INSERT INTO schema_migrations VALUES (?, ?)", (version, iso(self._clock())))

    def ping(self) -> bool:
        with self._lock:
            return self._db.execute("SELECT 1").fetchone()[0] == 1

    # -- accounts / keys ------------------------------------------------------------------
    def create_account(self, email: str, plan: str, state: str = "active") -> dict[str, Any]:
        if state not in ACCOUNT_STATES:
            raise ValueError("invalid state")
        account_id = "acct_" + uuid.uuid4().hex[:24]
        with self._tx() as db:
            db.execute("INSERT INTO accounts VALUES (?,?,?,?,?)", (account_id, email.strip(), plan, state, iso(self._clock())))
        return self.get_account(account_id)  # type: ignore[return-value]

    def get_account(self, account_id: str) -> dict[str, Any] | None:
        with self._lock:
            row = self._db.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
        return dict(row) if row else None

    def get_account_by_email(self, email: str) -> dict[str, Any] | None:
        with self._lock:
            row = self._db.execute("SELECT * FROM accounts WHERE email=?", (email.strip(),)).fetchone()
        return dict(row) if row else None

    def list_accounts(self) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(r) for r in self._db.execute("SELECT * FROM accounts ORDER BY created_at")]

    def update_account(self, account_id: str, *, state: str | None = None, plan: str | None = None) -> None:
        if state is not None and state not in ACCOUNT_STATES:
            raise ValueError("invalid state")
        with self._tx() as db:
            if state is not None:
                db.execute("UPDATE accounts SET state=? WHERE id=?", (state, account_id))
            if plan is not None:
                db.execute("UPDATE accounts SET plan=? WHERE id=?", (plan, account_id))

    def add_api_key(self, account_id: str, key_hash: str, prefix: str) -> str:
        key_id = "key_" + uuid.uuid4().hex[:24]
        with self._tx() as db:
            db.execute("INSERT INTO api_keys (id, account_id, key_hash, prefix, created_at) VALUES (?,?,?,?,?)",
                       (key_id, account_id, key_hash, prefix, iso(self._clock())))
        return key_id

    def revoke_api_keys(self, account_id: str, key_id: str | None = None) -> int:
        with self._tx() as db:
            cur = db.execute(
                "UPDATE api_keys SET revoked_at=? WHERE account_id=? AND revoked_at IS NULL AND (? IS NULL OR id=?)",
                (iso(self._clock()), account_id, key_id, key_id))
            return cur.rowcount

    def list_api_keys(self, account_id: str) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._db.execute(
                "SELECT id, prefix, created_at, last_used_at, revoked_at FROM api_keys WHERE account_id=? ORDER BY created_at",
                (account_id,))
            return [dict(r) for r in rows]

    def authenticate(self, key_hash: str) -> dict[str, Any] | None:
        """Account for a live (non-revoked) key hash, regardless of subscription state."""
        with self._lock:
            row = self._db.execute(
                """SELECT a.*, k.id AS key_id, k.last_used_at AS key_last_used FROM api_keys k
                   JOIN accounts a ON a.id = k.account_id WHERE k.key_hash=? AND k.revoked_at IS NULL""",
                (key_hash,)).fetchone()
        if row is None:
            return None
        account = dict(row)
        now = self._clock()
        last = account.pop("key_last_used")
        if last is None or now - datetime.fromisoformat(last.replace("Z", "+00:00")) > timedelta(minutes=1):
            with self._tx() as db:  # throttled so reads don't become a write per request
                db.execute("UPDATE api_keys SET last_used_at=? WHERE id=?", (iso(now), account["key_id"]))
        return account

    # -- devices --------------------------------------------------------------------------
    def register_device(self, account_id: str, installation_id: str | None, label: str | None, max_devices: int) -> tuple[str, bool] | None:
        """Returns (device_id, created) or None when the device limit is reached."""
        now = iso(self._clock())
        with self._tx() as db:
            if installation_id:
                row = db.execute("SELECT id FROM devices WHERE account_id=? AND installation_id=?",
                                 (account_id, installation_id)).fetchone()
                if row:
                    db.execute("UPDATE devices SET last_seen_at=?, label=COALESCE(?, label) WHERE id=?", (now, label, row["id"]))
                    return row["id"], False
            count = db.execute("SELECT COUNT(*) FROM devices WHERE account_id=?", (account_id,)).fetchone()[0]
            if count >= max_devices:
                return None
            device_id = "dev_" + uuid.uuid4().hex[:24]
            db.execute("INSERT INTO devices VALUES (?,?,?,?,?,?)", (device_id, account_id, installation_id, label, now, now))
            return device_id, True

    def device_exists(self, account_id: str, device_id: str) -> bool:
        with self._lock:
            return self._db.execute("SELECT 1 FROM devices WHERE id=? AND account_id=?", (device_id, account_id)).fetchone() is not None

    def touch_device(self, device_id: str) -> None:
        with self._tx() as db:
            db.execute("UPDATE devices SET last_seen_at=? WHERE id=?", (iso(self._clock()), device_id))

    def delete_device(self, account_id: str, device_id: str) -> bool:
        with self._tx() as db:
            return db.execute("DELETE FROM devices WHERE id=? AND account_id=?", (device_id, account_id)).rowcount > 0

    # -- usage ----------------------------------------------------------------------------
    def reserve_usage(self, account_id: str, request_id: str, device_id: str, quota: int) -> str:
        """Atomically check quota and reserve one unit: 'reserved' | 'duplicate' | 'quota_exhausted'."""
        now = self._clock()
        day = now.strftime("%Y-%m-%d")
        with self._tx() as db:
            db.execute("UPDATE usage_events SET outcome='abandoned', billed_units=0 WHERE outcome='pending' AND created_at < ?",
                       (iso(now - PENDING_TTL),))
            if db.execute("SELECT 1 FROM usage_events WHERE account_id=? AND request_id=?", (account_id, request_id)).fetchone():
                return "duplicate"
            used = db.execute(
                "SELECT COALESCE(SUM(billed_units),0) FROM usage_events WHERE account_id=? AND substr(day,1,7)=?",
                (account_id, day[:7])).fetchone()[0]
            if used >= quota:
                return "quota_exhausted"
            db.execute(
                "INSERT INTO usage_events (account_id, request_id, device_id, day, outcome, billed_units, created_at) VALUES (?,?,?,?, 'pending', 1, ?)",
                (account_id, request_id, device_id, day, iso(now)))
            return "reserved"

    def complete_usage(self, account_id: str, request_id: str, *, tokens_in: int, tokens_out: int, model_id: str, latency_ms: int) -> None:
        with self._tx() as db:
            db.execute(
                "UPDATE usage_events SET outcome='ok', tokens_in=?, tokens_out=?, model_id=?, latency_ms=? WHERE account_id=? AND request_id=? AND outcome='pending'",
                (tokens_in, tokens_out, model_id, latency_ms, account_id, request_id))

    def release_usage(self, account_id: str, request_id: str) -> None:
        """Failed analysis is not billed; the request_id can be retried."""
        with self._tx() as db:
            db.execute("DELETE FROM usage_events WHERE account_id=? AND request_id=? AND outcome='pending'", (account_id, request_id))

    def usage_summary(self, account_id: str, month: str) -> dict[str, Any]:
        with self._lock:
            rows = self._db.execute(
                """SELECT day, SUM(billed_units) AS n, SUM(tokens_in + tokens_out) AS t FROM usage_events
                   WHERE account_id=? AND substr(day,1,7)=? AND outcome IN ('ok','pending') GROUP BY day""",
                (account_id, month)).fetchall()
        return {"by_day": {r["day"]: r["n"] for r in rows}, "tokens": sum(r["t"] or 0 for r in rows),
                "actions": sum(r["n"] for r in rows)}

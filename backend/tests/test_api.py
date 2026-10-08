from __future__ import annotations

import sqlite3
from uuid import uuid4

from tracerook_backend.analyzer import StubAnalyzer
from tracerook_backend.errors import ApiError
from tracerook_backend import errors

from conftest import Env


def err(r):
    return r.json()["error"]["code"]


# ---- auth --------------------------------------------------------------------------------
def test_requires_valid_key(env):
    _, key = env.account()
    assert env.client.get("/v1/account").status_code == 401
    assert err(env.client.get("/v1/account")) == "not_authenticated"
    bad = env.client.get("/v1/account", headers=env.headers("trk_live_" + "x" * 43))
    assert bad.status_code == 401 and bad.headers["WWW-Authenticate"] == "Bearer"
    assert env.client.get("/v1/account", headers={"Authorization": f"Basic {key}"}).status_code == 401
    assert env.client.get("/v1/account", headers=env.headers(key)).status_code == 200


def test_revoked_key_and_inactive_subscription(env):
    acct, key = env.account()
    env.store.revoke_api_keys(acct["id"])
    assert env.client.get("/v1/account", headers=env.headers(key)).status_code == 401
    acct2, key2 = env.account("b@example.com", state="canceled")
    r = env.client.get("/v1/account", headers=env.headers(key2))
    assert r.status_code == 402 and err(r) == "subscription_inactive"


def test_plaintext_key_never_stored(env):
    acct, key = env.account()
    env.device(key)
    dump = "\n".join(env.store._db.iterdump())
    assert key not in dump and key[9:] not in dump


def test_failed_auth_attempts_are_throttled(env):
    for _ in range(20):
        assert env.client.get("/v1/account", headers=env.headers("trk_live_" + "y" * 43)).status_code == 401
    r = env.client.get("/v1/account", headers=env.headers("trk_live_" + "y" * 43))
    assert r.status_code == 429 and "Retry-After" in r.headers


# ---- contract shapes (the keys the Swift client decodes) ---------------------------------
def test_plans_public_shape(env):
    r = env.client.get("/v1/plans")
    assert r.status_code == 200
    plan = r.json()["plans"][0]
    assert set(plan) == {"id", "name", "description", "monthlyPriceLabel", "features"}
    assert plan["monthlyPriceLabel"] == "$20 / month"


def test_account_shape(env):
    acct, key = env.account()
    body = env.client.get("/v1/account", headers=env.headers(key)).json()
    assert body == {"account_id": acct["id"], "email": "dev@example.com", "plan": "Individual", "state": "active"}


def test_device_registration_idempotent_and_limited(env):
    _, key = env.account()
    h = env.headers(key)
    inst = str(uuid4())
    first = env.client.post("/v1/device/registrations", json={"installation_id": inst}, headers=h)
    again = env.client.post("/v1/device/registrations", json={"installation_id": inst}, headers=h)
    assert first.status_code == 201 and again.status_code == 200
    assert first.json() == again.json() and first.json()["enrollment_state"] == "enrolled"
    for _ in range(4):  # no body, as the current Swift client sends
        assert env.client.post("/v1/device/registrations", headers=h).status_code == 201
    over = env.client.post("/v1/device/registrations", headers=h)
    assert over.status_code == 409 and err(over) == "device_limit_reached"


def test_devices_are_scoped_to_account(env):
    _, key_a = env.account("a@example.com")
    _, key_b = env.account("b@example.com")
    dev_a = env.device(key_a)
    r = env.client.post("/v1/analyze", json=env.payload(dev_a), headers=env.headers(key_b))
    assert r.status_code == 404 and err(r) == "device_not_found"


# ---- analyze + metering ------------------------------------------------------------------
def test_analyze_success_shape_and_usage(env):
    _, key = env.account()
    dev = env.device(key)
    p = env.payload(dev)
    r = env.client.post("/v1/analyze", json=p, headers=env.headers(key))
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"request_id", "verdict", "model_id", "policy_version", "trace_id", "expires_at", "billed_units"}
    assert body["request_id"] == p["request_id"] and body["billed_units"] == 1
    assert body["expires_at"] == "2026-10-08T12:05:00Z"  # Swift .iso8601: no fractional seconds
    assert r.headers["X-Request-ID"] == body["trace_id"]
    u = env.client.get("/v1/usage", headers=env.headers(key)).json()
    assert u == {"period": "2026-10", "analyzed_actions": 1, "tokens_used": 20, "quota": 3,
                 "daily_actions": [0, 0, 0, 0, 0, 0, 0, 1]}


def test_usage_month_validation_and_past_months(env):
    _, key = env.account()
    h = env.headers(key)
    assert env.client.get("/v1/usage?month=2026-13", headers=h).status_code == 400
    past = env.client.get("/v1/usage?month=2026-02", headers=h).json()
    assert past["analyzed_actions"] == 0 and len(past["daily_actions"]) == 28
    assert env.client.get("/v1/usage?month=2027-01", headers=h).json()["daily_actions"] == []


def test_quota_enforced_and_resets_monthly(env):
    _, key = env.account()
    dev = env.device(key)
    h = env.headers(key)
    for _ in range(3):
        assert env.client.post("/v1/analyze", json=env.payload(dev), headers=h).status_code == 200
    r = env.client.post("/v1/analyze", json=env.payload(dev), headers=h)
    assert r.status_code == 402 and err(r) == "quota_exhausted"
    env.clock.advance(days=30)  # Nov 7
    assert env.client.post("/v1/analyze", json=env.payload(dev), headers=h).status_code == 200


class Failing:
    def __init__(self, exc): self.exc, self.calls = exc, 0
    async def analyze(self, request, *, deadline_s):
        self.calls += 1
        raise self.exc


def test_failed_analysis_is_not_billed_and_can_retry_same_id():
    failing = Failing(ApiError(503, errors.PROVIDER_UNAVAILABLE, "down"))
    e = Env(analyzer=failing)
    try:
        _, key = e.account()
        dev = e.device(key)
        p = e.payload(dev)
        r = e.client.post("/v1/analyze", json=p, headers=e.headers(key))
        assert r.status_code == 503 and err(r) == "provider_unavailable"
        assert e.client.get("/v1/usage", headers=e.headers(key)).json()["analyzed_actions"] == 0
        # the same request_id may be retried after a failure
        failing.exc = ApiError(504, errors.TIMEOUT, "slow")
        assert e.client.post("/v1/analyze", json=p, headers=e.headers(key)).status_code == 504
    finally:
        e.close()


def test_unexpected_analyzer_crash_is_500_and_not_billed():
    e = Env(analyzer=Failing(RuntimeError("secret stack detail")))
    try:
        _, key = e.account()
        dev = e.device(key)
        r = e.client.post("/v1/analyze", json=e.payload(dev), headers=e.headers(key))
        assert r.status_code == 500 and "secret" not in r.text
        assert e.client.get("/v1/usage", headers=e.headers(key)).json()["analyzed_actions"] == 0
    finally:
        e.close()


def test_retry_replays_cached_response_without_double_billing(env):
    _, key = env.account()
    dev = env.device(key)
    p = env.payload(dev)
    first = env.client.post("/v1/analyze", json=p, headers=env.headers(key))
    second = env.client.post("/v1/analyze", json=p, headers=env.headers(key))
    assert second.status_code == 200 and second.headers["Idempotent-Replay"] == "true"
    assert second.json() == first.json()
    assert env.client.get("/v1/usage", headers=env.headers(key)).json()["analyzed_actions"] == 1


def test_duplicate_request_id_conflicts_once_replay_cache_is_gone(env):
    acct, key = env.account()
    dev = env.device(key)
    p = env.payload(dev)
    assert env.client.post("/v1/analyze", json=p, headers=env.headers(key)).status_code == 200
    # Billing uniqueness is enforced in the database independently of the in-memory replay cache.
    assert env.store.reserve_usage(acct["id"], p["request_id"], dev, 99) == "duplicate"


def test_rate_limit_per_account():
    from tracerook_backend.config import Settings
    e = Env(Settings(env="test", individual_quota=100, rate_limit_per_minute=2))
    try:
        _, key = e.account()
        dev = e.device(key)
        codes = [e.client.post("/v1/analyze", json=e.payload(dev), headers=e.headers(key)).status_code for _ in range(3)]
        assert codes == [200, 200, 429]
    finally:
        e.close()


def test_concurrent_reservations_cannot_exceed_quota(env):
    import threading
    acct, key = env.account()
    dev = env.device(key)
    results = []
    def go():
        results.append(env.store.reserve_usage(acct["id"], str(uuid4()), dev, 3))
    threads = [threading.Thread(target=go) for _ in range(12)]
    [t.start() for t in threads]; [t.join() for t in threads]
    assert results.count("reserved") == 3 and results.count("quota_exhausted") == 9


# ---- input safety / privacy --------------------------------------------------------------
def test_unredacted_secrets_are_rejected_without_echo(env):
    _, key = env.account()
    dev = env.device(key)
    secret = "ghp_" + "a" * 30
    for field, value in [
        ("proposed_action_redacted", f"git push https://x:{secret}@github.com/o/r"),
        ("task_anchor_redacted", f"use token {secret}"),
        ("prior_events_redacted", ["password = hunter2"]),
        ("proposed_action_redacted", "cat /Users/alice/.ssh/id_rsa"),
        ("proposed_action_redacted", "-----BEGIN OPENSSH PRIVATE KEY-----"),
        ("session_pseudonym", "Bearer abc.def.ghi"),
    ]:
        r = env.client.post("/v1/analyze", json=env.payload(dev, **{field: value}), headers=env.headers(key))
        assert r.status_code == 422 and err(r) == "unsafe_payload", (field, r.text)
        assert secret not in r.text and "hunter2" not in r.text
    assert env.client.get("/v1/usage", headers=env.headers(key)).json()["analyzed_actions"] == 0


def test_client_redactor_output_passes_preflight(env):
    _, key = env.account()
    dev = env.device(key)
    safe = "git push Bearer [REDACTED:TOKEN] to [REDACTED:ASSIGNMENT] in ~/proj [TRUNCATED]"
    r = env.client.post("/v1/analyze", json=env.payload(dev, proposed_action_redacted=safe), headers=env.headers(key))
    assert r.status_code == 200, r.text


def test_validation_errors_do_not_echo_input(env):
    _, key = env.account()
    dev = env.device(key)
    p = env.payload(dev, proposed_action_redacted="SENTINEL-" + "x" * 9000)
    r = env.client.post("/v1/analyze", json=p, headers=env.headers(key))
    assert r.status_code == 400 and err(r) == "malformed_request"
    assert "SENTINEL" not in r.text
    r = env.client.post("/v1/analyze", json={**env.payload(dev), "surprise": "SENTINEL-2"}, headers=env.headers(key))
    assert r.status_code == 400 and "SENTINEL" not in r.text
    r = env.client.post("/v1/analyze", json=env.payload(dev, schema_version=2), headers=env.headers(key))
    assert r.status_code == 400
    r = env.client.post("/v1/analyze", json=env.payload(dev, client_deadline_ms=5), headers=env.headers(key))
    assert r.status_code == 400


def test_oversized_body_rejected(env):
    _, key = env.account()
    r = env.client.post("/v1/analyze", content=b"{" + b" " * 70_000 + b"}",
                        headers={**env.headers(key), "Content-Type": "application/json"})
    assert r.status_code == 413 and err(r) == "payload_too_large"


def test_no_analyzed_content_persisted(env):
    _, key = env.account()
    dev = env.device(key)
    env.client.post("/v1/analyze", json=env.payload(dev, proposed_action_redacted="UNIQUE-ACTION-MARKER",
                                                    task_anchor_redacted="UNIQUE-TASK-MARKER"), headers=env.headers(key))
    dump = "\n".join(env.store._db.iterdump())
    assert "UNIQUE-ACTION-MARKER" not in dump and "UNIQUE-TASK-MARKER" not in dump


def test_telemetry_ack_and_validation(env):
    _, key = env.account()
    h = env.headers(key)
    ok = env.client.post("/v1/events", json={"origin": "live", "events": [{"code": "hook_timeout", "count": 2}]}, headers=h)
    assert ok.status_code == 200 and ok.json() == {"acknowledged": True}
    bad = env.client.post("/v1/events", json={"origin": "live", "events": [{"code": "rm -rf /home/alice", "count": 1}]}, headers=h)
    assert bad.status_code == 400


def test_unknown_route_and_no_docs_in_production():
    from tracerook_backend.app import create_app
    from tracerook_backend.config import Settings
    from fastapi.testclient import TestClient
    app = create_app(Settings(env="production", key_pepper=b"p" * 32, database_path=":memory:"), analyzer=StubAnalyzer())
    with TestClient(app) as c:
        assert c.get("/docs").status_code == 404 and c.get("/openapi.json").status_code == 404
        assert c.get("/nope").json()["error"]["code"] == "not_found"
        assert c.get("/healthz").json() == {"status": "ok"}
        assert c.get("/readyz").status_code == 200

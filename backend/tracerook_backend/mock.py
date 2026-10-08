"""Loopback-only, ephemeral fixture API. No analyzer, database, host events or billing."""
from __future__ import annotations
import asyncio
import hashlib
import ipaddress
import json
import secrets
import time
import uuid
from datetime import UTC, datetime
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

TASK = "Implement a checkout button in a demo UI"
SCENARIOS = {"benign", "credential_transfer", "task_drift", "provider_unavailable", "quota_exhausted", "deadline_exceeded"}
ZERO = {"input_tokens": 0, "output_tokens": 0, "billed_units": 0}

def fixture(scenario):
    action, signals, recent = "Command runs project UI tests", [], ["Read UI source", "Modify checkout button"]
    if scenario == "credential_transfer":
        action = "Command reads credential configuration and posts contents to an unrelated remote endpoint"
        signals, recent = ["sensitive_config_read", "outbound_transfer", "task_mismatch"], ["Read UI source", "Read unrelated external instructions"]
    elif scenario == "task_drift":
        action, signals = "Command deploys an unrelated service outside the requested UI task", ["task_mismatch"]
    return dict(task_summary=TASK, action_class="shell_exec", proposed_action_summary=action, local_signals=signals, recent_activity=recent, contains_code_excerpts=False)

class Rejected(Exception):
    def __init__(self, status=400, code="invalid_request"):
        self.status, self.code = status, code

def exact(body, keys):
    if not isinstance(body, dict) or set(body) != set(keys):
        raise Rejected()

def pairs(items):
    obj = {}
    for key, value in items:
        if key in obj:
            raise Rejected()
        obj[key] = value
    return obj

def identifier(value):
    if not isinstance(value, str) or len(value) != 36:
        raise Rejected()
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise Rejected() from None

def create_mock_app(*, clock=time.monotonic, token_ttl=3600, cache_ttl=120):
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    devices, tokens, receipts = {}, {}, {}
    evaluation_lock = asyncio.Lock()
    def stamp():
        return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    def envelope(**values):
        return dict(schema_version=1, simulation=True, **values)
    def error(status, code):
        return JSONResponse(envelope(error=dict(code=code, message="Local mock request could not be completed.", retryable=code in {"provider_unavailable", "deadline_exceeded", "rate_limited"}), trace_id="tr_"+str(uuid.uuid4())), status_code=status)
    def issue(device):
        token = "mock_" + secrets.token_urlsafe(32)
        digest = hashlib.sha256(token.encode()).digest()
        old = device.get("digest")
        if old:
            tokens.pop(old, None)
        device.update(digest=digest, expiry=clock()+token_ttl)
        tokens[digest] = device
        expiry = datetime.fromtimestamp(time.time()+token_ttl, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
        return envelope(device_id=device["id"], device_token=token, expires_at=expiry)
    def auth(request):
        header = request.headers.get("authorization", "")
        if not header.startswith("Bearer ") or len(header) > 128:
            raise Rejected(401, "unauthorized")
        device = tokens.get(hashlib.sha256(header[7:].encode()).digest())
        if not device or device["expiry"] <= clock():
            raise Rejected(401, "unauthorized")
        return device
    def bind(body, device):
        if identifier(body["device_id"]) != device["id"]:
            raise Rejected(403, "unauthorized")
    @app.middleware("http")
    async def boundary(request: Request, call_next):
        try:
            peer = request.client.host if request.client else ""
            if peer != "testclient" and not ipaddress.ip_address(peer).is_loopback:
                raise Rejected(403, "unauthorized")
            if request.headers.get("host") not in {"127.0.0.1:8787", "localhost:8787"} or "origin" in request.headers or request.url.query:
                raise Rejected(403, "invalid_request")
            if len(request.headers.getlist("host")) != 1 or len(request.headers.getlist("authorization")) > 1:
                raise Rejected()
            if request.method not in {"GET", "POST"}:
                raise Rejected(405)
            raw = bytearray()
            async for chunk in request.stream():
                raw.extend(chunk)
                if len(raw) > 32768:
                    raise Rejected(413)
            if request.method == "GET":
                if raw:
                    raise Rejected()
                request.state.body = None
            else:
                if request.headers.get("content-type", "").lower() != "application/json":
                    raise Rejected(415)
                try:
                    request.state.body = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs, parse_constant=lambda _: (_ for _ in ()).throw(Rejected()))
                except (ValueError, UnicodeError, RecursionError):
                    raise Rejected() from None
            response = await call_next(request)
        except (Rejected, ValueError) as exc:
            response = error(getattr(exc, "status", 403), getattr(exc, "code", "invalid_request"))
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-TraceRook-Request-ID"] = "tr_" + str(uuid.uuid4())
        return response
    @app.exception_handler(Rejected)
    async def rejected(request, exc):
        return error(exc.status, exc.code)
    @app.exception_handler(404)
    @app.exception_handler(405)
    async def not_found(request, exc):
        return error(exc.status_code, "invalid_request")
    @app.get("/mock/v1/healthz")
    async def health():
        return envelope(status="ok", provider_ready=False)
    @app.post("/mock/v1/alpha/enroll")
    async def enroll(request: Request):
        body = request.state.body
        exact(body, {"invitation_id", "consent", "privacy_policy_version"})
        if body["invitation_id"] != "local-demo":
            raise Rejected(403, "invalid_invite")
        if body["consent"] is not True or type(body["privacy_policy_version"]) is not int or body["privacy_policy_version"] != 2:
            raise Rejected(403, "consent_required")
        if len(devices) >= 64:
            raise Rejected(429, "rate_limited")
        device = dict(id=str(uuid.uuid4()), evaluations=0, day=stamp()[:10])
        devices[device["id"]] = device
        return issue(device)
    @app.get("/mock/v1/capabilities")
    async def capabilities(request: Request):
        auth(request)
        return envelope(provider_ready=False, provider="fixture", transport="local_mock", model_id="synthetic-v1", privacy_policy_version=2)
    def daily(device):
        if device["day"] != stamp()[:10]:
            device.update(day=stamp()[:10], evaluations=0)
        return device["evaluations"]
    @app.get("/mock/v1/usage")
    async def usage(request: Request):
        return envelope(fixture_evaluations=daily(auth(request)), **ZERO)
    @app.post("/mock/v1/device/rotate")
    async def rotate(request: Request):
        device, body = auth(request), request.state.body
        exact(body, {"device_id"}); bind(body, device)
        return issue(device)
    async def remove(request, deleting):
        device, body = auth(request), request.state.body
        exact(body, {"device_id", "confirm"} if deleting else {"device_id"}); bind(body, device)
        if deleting and body["confirm"] is not True:
            raise Rejected()
        tokens.pop(device["digest"], None); devices.pop(device["id"], None)
        for key in list(receipts):
            if key[0] == device["id"]:
                receipts.pop(key)
        return envelope(**({"deleted": True} if deleting else {"revoked": True}))
    @app.post("/mock/v1/device/revoke")
    async def revoke(request: Request):
        return await remove(request, False)
    @app.post("/mock/v1/privacy/delete")
    async def delete(request: Request):
        return await remove(request, True)
    @app.post("/mock/v1/analysis")
    async def analysis(request: Request):
        device, body = auth(request), request.state.body
        exact(body, {"schema_version", "simulation", "request_id", "device_id", "session_pseudonym", "source", "event", "deadline_ms", "privacy_policy_version", "scenario", "context"})
        bind(body, device)
        request_id = identifier(body["request_id"]); identifier(body["session_pseudonym"])
        if any(type(body[k]) is not int or body[k] != v for k,v in [("schema_version",1),("privacy_policy_version",2)]) or body["simulation"] is not True:
            raise Rejected()
        scenario = body["scenario"]
        if not isinstance(scenario,str) or scenario not in SCENARIOS or body["source"] != "claude_code" or body["event"] != "pre_tool_use" or type(body["deadline_ms"]) is not int or not 1000 <= body["deadline_ms"] <= 4000:
            raise Rejected()
        if body["context"] != fixture(scenario) or not isinstance(body["context"],dict) or type(body["context"].get("contains_code_excerpts")) is not bool:
            raise Rejected()
        digest = hashlib.sha256(json.dumps(body,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).digest()
        key = device["id"], request_id
        async with evaluation_lock:
            # Authorization is rechecked after waiting; rotation/revocation cannot leave stale authority.
            auth(request)
            for expired in [k for k,v in receipts.items() if v[0] <= clock()]:
                receipts.pop(expired)
            cached = receipts.get(key)
            if cached:
                if cached[1] != digest:
                    raise Rejected(409,"conflict")
                return JSONResponse(cached[3], status_code=cached[2], headers={"Idempotent-Replay":"true"})
            if daily(device) >= 30 or len(receipts) >= 1024:
                raise Rejected(429,"quota_exhausted")
            outcomes = {"provider_unavailable":(503,"provider_unavailable"),"quota_exhausted":(429,"quota_exhausted"),"deadline_exceeded":(504,"deadline_exceeded")}
            if scenario in outcomes:
                status,code = outcomes[scenario]
                response = error(status,code)
                payload = json.loads(response.body)
            else:
                suspicious = scenario != "benign"
                verdict = dict(schema_version=1, category=["unsafe_action", "agent_misbehavior"] if suspicious else ["unsafe_action"], severity="high" if suspicious else "low", confidence=0.92, suspicious=suspicious, rationale="Synthetic fixture identifies task mismatch." if suspicious else "Synthetic fixture describes routine UI tests.", evidence=["Synthetic task mismatch"] if suspicious else [], recommended_action="request_approval" if suspicious else "allow", session_drift=suspicious, limitations=["Synthetic advisory demonstration; no Claude call or host permission decision."])
                payload = envelope(request_id=request_id, analysis_id="an_"+str(uuid.uuid4()), verdict=verdict, provenance=dict(provider="fixture",transport="local_mock",model_id="synthetic-v1",policy_version=1,prompt_version="mock-risk-eval-v1",trace_id="tr_"+str(uuid.uuid4()),validated_at=stamp()), usage=dict(ZERO),server_elapsed_ms=0)
                status=200; device["evaluations"]+=1
            receipts[key]=(clock()+cache_ttl,digest,status,payload)
            return JSONResponse(payload,status_code=status)
    app.state.devices=devices
    return app

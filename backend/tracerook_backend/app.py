from __future__ import annotations

import asyncio
import logging
import re
import time
import uuid
from collections.abc import Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi import Depends, FastAPI, Query, Request, Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from . import errors
from .analyzer import Analyzer, build_analyzer
from .config import Settings
from .errors import ApiError, error_response, install_handlers
from .plans import Plan, build_plans
from .ratelimit import RateLimiter
from .redaction import contains_unredacted
from .schemas import (
    AccountResponse, AnalyzeRequest, AnalyzeResponse, DeviceRegistrationRequest,
    DeviceRegistrationResponse, PlanOut, PlansResponse, TelemetryRequest, TelemetryResponse, UsageResponse,
)
from .security import hash_api_key, looks_like_key
from .store import Store, iso

log = logging.getLogger("tracerook.api")
MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
REPLAY_CACHE_TTL_S = 120.0
# Reserve this much of the client's deadline for network transit and client-side decode.
DEADLINE_MARGIN_S = 1.0


@dataclass
class AuthContext:
    account: dict[str, Any]
    key_id: str


class BodyLimitMiddleware:
    """Reject oversized bodies before parsing (Content-Length and streamed bytes)."""

    def __init__(self, app: ASGIApp, max_bytes: int):
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        declared = dict(scope["headers"]).get(b"content-length")
        too_big = error_response(413, errors.PAYLOAD_TOO_LARGE, "Request body too large")
        if declared is not None and (not declared.isdigit() or int(declared) > self.max_bytes):
            return await too_big(scope, receive, send)
        seen = 0
        started = False

        async def limited_receive() -> Message:
            nonlocal seen
            message = await receive()
            if message["type"] == "http.request":
                seen += len(message.get("body", b""))
                if seen > self.max_bytes:
                    raise _BodyTooLarge
            return message

        async def tracking_send(message: Message) -> None:
            nonlocal started
            started = started or message["type"] == "http.response.start"
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except _BodyTooLarge:
            if not started:
                await too_big(scope, receive, send)


class _BodyTooLarge(Exception):
    pass


class ReplayCache:
    """Short-lived (account, request_id) -> response cache so a client retry after a lost
    response isn't double-billed. Holds the verdict in memory only; never persisted."""

    def __init__(self, ttl_s: float = REPLAY_CACHE_TTL_S, clock: Callable[[], float] = time.monotonic):
        self._ttl, self._clock = ttl_s, clock
        self._items: dict[tuple[str, str], tuple[float, dict[str, Any]]] = {}

    def get(self, key: tuple[str, str]) -> dict[str, Any] | None:
        self._evict()
        hit = self._items.get(key)
        return hit[1] if hit else None

    def put(self, key: tuple[str, str], value: dict[str, Any]) -> None:
        self._evict()
        self._items[key] = (self._clock() + self._ttl, value)

    def _evict(self) -> None:
        now = self._clock()
        for k in [k for k, (exp, _) in self._items.items() if exp <= now]:
            del self._items[k]


def create_app(settings: Settings | None = None, *, analyzer: Analyzer | None = None,
               store: Store | None = None, clock: Callable[[], datetime] | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    now: Callable[[], datetime] = clock or (lambda: datetime.now(UTC))
    plans = build_plans(settings)
    store = store or Store(settings.database_path, clock=now)
    analyzer = analyzer or build_analyzer(settings)
    limiter = RateLimiter(settings.rate_limit_per_minute)
    auth_failures = RateLimiter(settings.auth_failures_per_minute)
    replay = ReplayCache()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        store.close()

    app = FastAPI(title="TraceRook Cloud API", version="1", lifespan=lifespan,
                  docs_url="/docs" if settings.is_dev else None, redoc_url=None,
                  openapi_url="/openapi.json" if settings.is_dev else None)
    app.add_middleware(BodyLimitMiddleware, max_bytes=settings.max_body_bytes)
    install_handlers(app)

    @app.middleware("http")
    async def trace_header(request: Request, call_next):
        request.state.trace_id = uuid.uuid4().hex
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.trace_id
        response.headers["Cache-Control"] = "no-store"
        return response

    async def db(fn: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
        return await asyncio.to_thread(fn, *args, **kwargs)

    async def authed(request: Request) -> AuthContext:
        ip = request.client.host if request.client else "unknown"
        wait = auth_failures.blocked(ip)
        if wait is not None:
            raise ApiError(429, errors.RATE_LIMITED, "Too many failed authentication attempts",
                           {"Retry-After": str(int(wait) + 1)})
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        account = None
        if scheme.lower() == "bearer" and looks_like_key(token.strip()):
            account = await db(store.authenticate, hash_api_key(settings.key_pepper, token.strip()))
        if account is None:
            auth_failures.record(ip)
            raise ApiError(401, errors.NOT_AUTHENTICATED, "Missing or invalid API key", {"WWW-Authenticate": "Bearer"})
        if account["state"] != "active":
            raise ApiError(402, errors.SUBSCRIPTION_INACTIVE, "Subscription is not active")
        return AuthContext(account, account["key_id"])

    def plan_for(account: dict[str, Any]) -> Plan:
        plan = plans.get(account["plan"])
        if plan is None:  # misconfigured account; fail closed rather than invent a quota
            raise ApiError(402, errors.SUBSCRIPTION_INACTIVE, "No valid plan on this account")
        return plan

    @app.get("/healthz", include_in_schema=False)
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    async def readyz() -> dict[str, str]:
        if not await db(store.ping):
            raise ApiError(503, errors.PROVIDER_UNAVAILABLE, "Not ready")
        return {"status": "ready"}

    @app.get("/v1/plans", response_model=PlansResponse)
    async def list_plans() -> PlansResponse:
        return PlansResponse(plans=[
            PlanOut(id=p.id, name=p.name, description=p.description, monthlyPriceLabel=p.price_label, features=list(p.features))
            for p in plans.values() if p.public])

    @app.post("/v1/device/registrations", response_model=DeviceRegistrationResponse)
    async def register_device(response: Response, body: DeviceRegistrationRequest | None = None,
                              auth: AuthContext = Depends(authed)) -> DeviceRegistrationResponse:
        body = body or DeviceRegistrationRequest()
        result = await db(store.register_device, auth.account["id"],
                          str(body.installation_id) if body.installation_id else None, body.label,
                          settings.max_devices_per_account)
        if result is None:
            raise ApiError(409, errors.DEVICE_LIMIT, "Device limit reached for this plan")
        device_id, created = result
        response.status_code = 201 if created else 200
        return DeviceRegistrationResponse(device_id=device_id, enrollment_state="enrolled")

    @app.get("/v1/account", response_model=AccountResponse)
    async def account(auth: AuthContext = Depends(authed)) -> AccountResponse:
        a = auth.account
        return AccountResponse(account_id=a["id"], email=a["email"], plan=plan_for(a).name, state=a["state"])

    @app.get("/v1/usage", response_model=UsageResponse)
    async def usage(month: str | None = Query(default=None), auth: AuthContext = Depends(authed)) -> UsageResponse:
        current = now()
        month = month or current.strftime("%Y-%m")
        if not MONTH_RE.match(month):
            raise ApiError(400, errors.MALFORMED_REQUEST, "month must be YYYY-MM")
        summary = await db(store.usage_summary, auth.account["id"], month)
        year, mon = int(month[:4]), int(month[5:])
        first = datetime(year, mon, 1, tzinfo=UTC)
        next_month = datetime(year + (mon == 12), mon % 12 + 1, 1, tzinfo=UTC)
        days_in_month = (next_month - first).days
        if first > current:
            days = 0
        elif month == current.strftime("%Y-%m"):
            days = current.day
        else:
            days = days_in_month
        daily = [summary["by_day"].get(f"{month}-{d:02d}", 0) for d in range(1, days + 1)]
        return UsageResponse(period=month, analyzed_actions=summary["actions"], tokens_used=summary["tokens"],
                             quota=plan_for(auth.account).monthly_quota, daily_actions=daily)

    @app.post("/v1/analyze", response_model=AnalyzeResponse)
    async def analyze(body: AnalyzeRequest, request: Request, response: Response,
                      auth: AuthContext = Depends(authed)) -> AnalyzeResponse | dict[str, Any]:
        account_id = auth.account["id"]
        plan = plan_for(auth.account)
        wait = limiter.check(account_id)
        if wait is not None:
            raise ApiError(429, errors.RATE_LIMITED, "Rate limit exceeded", {"Retry-After": str(int(wait) + 1)})
        if any(contains_unredacted(t) for t in body.text_fields()):
            raise ApiError(422, errors.UNSAFE_PAYLOAD, "Payload contains unredacted sensitive content")
        if not await db(store.device_exists, account_id, body.device_id):
            raise ApiError(404, errors.DEVICE_NOT_FOUND, "Unknown device; register the device first")

        request_id = str(body.request_id)
        cached = replay.get((account_id, request_id))
        if cached is not None:
            response.headers["Idempotent-Replay"] = "true"
            return cached
        state = await db(store.reserve_usage, account_id, request_id, body.device_id, plan.monthly_quota)
        if state == "duplicate":
            raise ApiError(409, errors.DUPLICATE_REQUEST, "request_id already used")
        if state == "quota_exhausted":
            raise ApiError(402, errors.QUOTA_EXHAUSTED, "Monthly analysis quota exhausted")

        started = time.monotonic()
        deadline = min(settings.analysis_timeout_s, max(0.5, body.client_deadline_ms / 1000 - DEADLINE_MARGIN_S))
        try:
            result = await analyzer.analyze(body, deadline_s=deadline)
        except BaseException as exc:  # includes cancellation on client disconnect
            await asyncio.shield(db(store.release_usage, account_id, request_id))
            log.info("analyze outcome=%s account=%s request=%s", getattr(exc, "code", type(exc).__name__), account_id, request_id)
            raise
        latency_ms = int((time.monotonic() - started) * 1000)
        await db(store.complete_usage, account_id, request_id, tokens_in=result.tokens_in,
                 tokens_out=result.tokens_out, model_id=result.model_id, latency_ms=latency_ms)
        await db(store.touch_device, body.device_id)
        log.info("analyze outcome=ok account=%s request=%s model=%s in=%d out=%d ms=%d", account_id, request_id,
                 result.model_id, result.tokens_in, result.tokens_out, latency_ms)
        payload = AnalyzeResponse(
            request_id=body.request_id, verdict=result.verdict, model_id=result.model_id,
            policy_version=settings.policy_version, trace_id=request.state.trace_id,
            expires_at=iso(now() + timedelta(seconds=settings.verdict_ttl_s)), billed_units=1,
        ).model_dump(mode="json")
        replay.put((account_id, request_id), payload)
        return payload

    @app.post("/v1/events", response_model=TelemetryResponse)
    async def events(body: TelemetryRequest, _: AuthContext = Depends(authed)) -> TelemetryResponse:
        # Opt-in sanitized counters: validated and acknowledged, deliberately not stored.
        return TelemetryResponse(acknowledged=True)

    app.state.settings, app.state.store = settings, store
    return app


def app_factory() -> FastAPI:
    """`uvicorn tracerook_backend.app:app_factory --factory`"""
    return create_app()

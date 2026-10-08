from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

# Codes mirror the typed client errors in the MVP1 spec (§15) plus a few service-specific ones.
NOT_AUTHENTICATED = "not_authenticated"
SUBSCRIPTION_INACTIVE = "subscription_inactive"
QUOTA_EXHAUSTED = "quota_exhausted"
RATE_LIMITED = "rate_limited"
UNSAFE_PAYLOAD = "unsafe_payload"
MALFORMED_REQUEST = "malformed_request"
PAYLOAD_TOO_LARGE = "payload_too_large"
PROVIDER_UNAVAILABLE = "provider_unavailable"
MALFORMED_RESPONSE = "malformed_response"
TIMEOUT = "timeout"
NOT_FOUND = "not_found"
DEVICE_NOT_FOUND = "device_not_found"
DEVICE_LIMIT = "device_limit_reached"
DUPLICATE_REQUEST = "duplicate_request"
INTERNAL = "internal_error"


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, headers: dict[str, str] | None = None):
        super().__init__(code)
        self.status, self.code, self.message, self.headers = status, code, message, headers or {}


def error_response(status: int, code: str, message: str, headers: dict[str, str] | None = None) -> JSONResponse:
    body: dict[str, Any] = {"error": {"code": code, "message": message}}
    return JSONResponse(body, status_code=status, headers=headers)


def install_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api(_: Request, exc: ApiError) -> JSONResponse:
        return error_response(exc.status, exc.code, exc.message, exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        # FastAPI's default 422 echoes the offending input. Payloads here are user session
        # context, so report only field locations and never the submitted values.
        fields = sorted({".".join(str(p) for p in e["loc"][1:]) or str(e["loc"][0]) for e in exc.errors()})
        return error_response(400, MALFORMED_REQUEST, "Invalid request fields: " + ", ".join(fields)[:300])

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = NOT_FOUND if exc.status_code == 404 else MALFORMED_REQUEST
        return error_response(exc.status_code, code, "Not found" if exc.status_code == 404 else "Request not allowed")

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:  # noqa: ARG001
        return error_response(500, INTERNAL, "Internal error")

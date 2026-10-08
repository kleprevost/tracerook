"""Wire DTOs. Field names are the exact JSON keys decoded by the Swift client
(Packages/TraceRookCore/Models.swift: Cloud* types). Do not rename them."""
from __future__ import annotations

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

Strict = ConfigDict(extra="forbid")


def _utf8_len(value: str) -> int:
    return len(value.encode("utf-8"))


class DeviceRegistrationRequest(BaseModel):
    model_config = Strict
    installation_id: UUID | None = None  # lets a reinstall/restart re-register idempotently
    label: Annotated[str, StringConstraints(max_length=64)] | None = None


class DeviceRegistrationResponse(BaseModel):
    device_id: str
    enrollment_state: Literal["enrolled"]


class AccountResponse(BaseModel):
    account_id: str
    email: str
    plan: str
    state: str


class UsageResponse(BaseModel):
    period: str
    analyzed_actions: int
    tokens_used: int
    quota: int
    daily_actions: list[int]


class PlanOut(BaseModel):
    id: str
    name: str
    description: str
    monthlyPriceLabel: str  # camelCase: CloudPlan has no CodingKeys in the Swift client
    features: list[str]


class PlansResponse(BaseModel):
    plans: list[PlanOut]


class AnalyzeRequest(BaseModel):
    """CloudAnalysisPayload. Everything arrives already redacted by the client; the server
    re-checks (redaction.py) and rejects rather than trying to repair."""

    model_config = Strict
    request_id: UUID
    schema_version: Literal[1]
    device_id: Annotated[str, StringConstraints(min_length=1, max_length=64)]
    session_pseudonym: Annotated[str, StringConstraints(min_length=1, max_length=128)]
    task_anchor_redacted: Annotated[str, StringConstraints(max_length=8192)]
    proposed_action_redacted: Annotated[str, StringConstraints(min_length=1, max_length=8192)]
    prior_events_redacted: Annotated[list[Annotated[str, StringConstraints(max_length=1024)]], Field(max_length=20)] = []
    privacy_policy_version: Literal[1]
    client_deadline_ms: Annotated[int, Field(ge=1000, le=30000)]

    @field_validator("task_anchor_redacted", "proposed_action_redacted")
    @classmethod
    def _bytes(cls, v: str) -> str:
        if _utf8_len(v) > 16384:
            raise ValueError("too long")
        return v

    @model_validator(mode="after")
    def _total(self) -> AnalyzeRequest:
        if sum(_utf8_len(s) for s in self.prior_events_redacted) > 16384:
            raise ValueError("prior events too long")
        return self

    def text_fields(self) -> list[str]:
        return [self.session_pseudonym, self.task_anchor_redacted, self.proposed_action_redacted,
                *self.prior_events_redacted]


class AnalyzeResponse(BaseModel):
    request_id: UUID
    verdict: dict[str, Any]
    model_id: str
    policy_version: int
    trace_id: str
    expires_at: str  # RFC 3339 UTC without fractional seconds (Swift .iso8601 strategy)
    billed_units: int


class TelemetryEvent(BaseModel):
    model_config = Strict
    code: Annotated[str, StringConstraints(pattern=r"^[a-z][a-z0-9_]{0,47}$")]
    count: Annotated[int, Field(ge=0, le=100000)]


class TelemetryRequest(BaseModel):
    model_config = Strict
    origin: Literal["live", "demo"]
    events: Annotated[list[TelemetryEvent], Field(max_length=50)] = []


class TelemetryResponse(BaseModel):
    acknowledged: bool

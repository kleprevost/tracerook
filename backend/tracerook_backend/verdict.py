"""Strict AnalysisVerdict validation, mirroring Swift `AnalysisVerdict.init(from:)`/`validate()`
(Packages/TraceRookCore/Models.swift). The model's output is never trusted: anything that the
client would reject is rejected here first, so the client never sees a malformed verdict."""
from __future__ import annotations

import math
from typing import Any

CATEGORIES = ("unsafe_action", "agent_misbehavior")
SEVERITIES = ("critical", "high", "medium", "low", "unknown")
# `deny` and `unavailable` exist in DecisionOutcome but the Swift validator rejects them.
RECOMMENDED = ("allow", "request_approval", "warn_allow")
KEYS = frozenset({
    "schema_version", "category", "severity", "confidence", "suspicious", "rationale",
    "evidence", "recommended_action", "session_drift", "limitations",
})

# Anthropic structured-output schema using the exact AnalysisVerdict keys. Bounds are enforced in validate_verdict
# because not every JSON-Schema keyword is supported by output_config.format.
VERDICT_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "schema_version": {"type": "integer", "enum": [1]},
        "category": {"type": "array", "items": {"type": "string", "enum": list(CATEGORIES)}},
        "severity": {"type": "string", "enum": list(SEVERITIES)},
        "confidence": {"type": "number"},
        "suspicious": {"type": "boolean"},
        "rationale": {"type": "string"},
        "evidence": {"type": "array", "items": {"type": "string"}},
        "recommended_action": {"type": "string", "enum": list(RECOMMENDED)},
        "session_drift": {"type": "boolean"},
        "limitations": {"type": "array", "items": {"type": "string"}},
    },
    "required": sorted(KEYS),
}


class InvalidVerdict(ValueError):
    pass


def _fail(reason: str) -> InvalidVerdict:
    # Reasons are static strings: never include model output in errors or logs.
    return InvalidVerdict(reason)


def _strings(value: Any, name: str, limit: int) -> list[str]:
    if not isinstance(value, list) or len(value) > limit:
        raise _fail(f"{name} invalid")
    for item in value:
        if not isinstance(item, str) or len(item.encode("utf-8")) > 512:
            raise _fail(f"{name} invalid")
    return value


def validate_verdict(obj: Any) -> dict[str, Any]:
    if not isinstance(obj, dict) or set(obj) != KEYS:
        raise _fail("keys")
    sv = obj["schema_version"]
    if isinstance(sv, bool) or sv != 1:
        raise _fail("schema_version")
    cats = obj["category"]
    if not isinstance(cats, list) or not 1 <= len(cats) <= 2 or any(c not in CATEGORIES for c in cats):
        raise _fail("category")
    if len(set(cats)) != len(cats):
        raise _fail("category")
    if obj["severity"] not in SEVERITIES:
        raise _fail("severity")
    conf = obj["confidence"]
    if isinstance(conf, bool) or not isinstance(conf, (int, float)) or not math.isfinite(conf) or not 0 <= conf <= 1:
        raise _fail("confidence")
    if not isinstance(obj["suspicious"], bool) or not isinstance(obj["session_drift"], bool):
        raise _fail("flags")
    rationale = obj["rationale"]
    if not isinstance(rationale, str) or len(rationale.encode("utf-8")) > 2048:
        raise _fail("rationale")
    _strings(obj["evidence"], "evidence", 10)
    _strings(obj["limitations"], "limitations", 10)
    if obj["recommended_action"] not in RECOMMENDED:
        raise _fail("recommended_action")
    return obj

"""Server-side remote-payload preflight: a port of the Swift `Redactor` patterns
(Packages/TraceRookPrivacy/Redactor.swift). The client redacts before sending; this is the
second check ("redaction and remote preflight before every API call"). Anything that would still
be redacted is rejected, never silently repaired, so a client bug cannot leak secrets onward."""
from __future__ import annotations

import re

_PATTERNS = [
    re.compile(r"-----BEGIN (?:[A-Z ]*PRIVATE KEY)-----", re.S),
    re.compile(r"\b(?:sk-ant-[a-z0-9_-]+|sk-[a-z0-9_-]{16,}|gh[pousr]_[a-z0-9_]{16,}|github_pat_[a-z0-9_]+|AKIA[A-Z0-9]{16}|ASIA[A-Z0-9]{16})\b", re.I),
    re.compile(r"\bBearer\s+[a-z0-9._~+/=-]+", re.I),
    re.compile(r"\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|aws_secret_access_key)\s*[=:]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;}&]+)", re.I),
    re.compile(r"/Users/[^/\s\"']+"),
    re.compile(r"(https?://)[^/\s:@]+:[^/\s@]+@", re.I),
]
_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def contains_unredacted(text: str) -> bool:
    return any(p.search(text) for p in _PATTERNS) or bool(_CONTROL.search(text))

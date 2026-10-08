from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

DEV_ENVS = {"development", "test"}
# Models that accept the server-side `fallbacks` parameter (Haiku 5.5 does not).
FALLBACK_MODEL_PREFIXES = ("claude-opus", "claude-sonnet", "claude-fable")


class ConfigError(RuntimeError):
    pass


def _bool(value: str | None, default: bool) -> bool:
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    env: str = "test"
    database_path: str = ":memory:"
    key_pepper: bytes = b"dev-only-pepper"
    analyzer: str = "stub"  # "anthropic" | "stub"
    anthropic_api_key: str | None = None
    anthropic_model: str = "claude-opus-5-5"
    anthropic_effort: str = "low"
    anthropic_fallbacks: bool = True
    # Hard server-side ceiling for one analysis; the client deadline can only shorten it.
    analysis_timeout_s: float = 12.0
    individual_quota: int = 2000
    rate_limit_per_minute: int = 60
    auth_failures_per_minute: int = 20
    max_devices_per_account: int = 5
    max_body_bytes: int = 64 * 1024
    policy_version: int = 1
    verdict_ttl_s: int = 300

    @property
    def is_dev(self) -> bool:
        return self.env in DEV_ENVS

    @property
    def fallbacks_supported(self) -> bool:
        return self.anthropic_fallbacks and self.anthropic_model.startswith(FALLBACK_MODEL_PREFIXES)

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None, *, require_analyzer: bool = True) -> Settings:
        e = os.environ if env is None else env
        mode = e.get("TRACEROOK_ENV", "production")
        if mode not in {"production", "development", "test"}:
            raise ConfigError("TRACEROOK_ENV must be production, development or test")
        dev = mode in DEV_ENVS

        pepper = e.get("TRACEROOK_KEY_PEPPER", "")
        if not pepper:
            if not dev:
                raise ConfigError("TRACEROOK_KEY_PEPPER is required outside development")
            pepper = "dev-only-pepper"
        if not dev and len(pepper) < 32:
            raise ConfigError("TRACEROOK_KEY_PEPPER must be at least 32 characters")

        analyzer = e.get("TRACEROOK_ANALYZER", "anthropic")
        if analyzer not in {"anthropic", "stub"}:
            raise ConfigError("TRACEROOK_ANALYZER must be anthropic or stub")
        if analyzer == "stub" and not dev:
            raise ConfigError("The stub analyzer is only allowed in development/test")
        api_key = e.get("ANTHROPIC_API_KEY") or None
        if require_analyzer and analyzer == "anthropic" and not api_key:
            raise ConfigError("ANTHROPIC_API_KEY is required for the anthropic analyzer")

        effort = e.get("TRACEROOK_ANTHROPIC_EFFORT", "low")
        if effort not in {"low", "medium", "high", "xhigh", "max"}:
            raise ConfigError("TRACEROOK_ANTHROPIC_EFFORT is invalid")

        try:
            return cls(
                env=mode,
                database_path=e.get("TRACEROOK_DATABASE_PATH", "./data/tracerook.db"),
                key_pepper=pepper.encode(),
                analyzer=analyzer,
                anthropic_api_key=api_key,
                anthropic_model=e.get("TRACEROOK_ANTHROPIC_MODEL", "claude-opus-5-5"),
                anthropic_effort=effort,
                anthropic_fallbacks=_bool(e.get("TRACEROOK_ANTHROPIC_FALLBACKS"), True),
                individual_quota=int(e.get("TRACEROOK_INDIVIDUAL_QUOTA", "2000")),
                rate_limit_per_minute=int(e.get("TRACEROOK_RATE_LIMIT_PER_MINUTE", "60")),
            )
        except ValueError as exc:
            raise ConfigError("A numeric TRACEROOK_* setting is not an integer") from exc

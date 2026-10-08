from __future__ import annotations

import hashlib
import hmac
import secrets

KEY_PREFIX = "trk_live_"


def generate_api_key() -> str:
    # 256 bits of entropy; a fast keyed hash is appropriate for high-entropy secrets.
    return KEY_PREFIX + secrets.token_urlsafe(32)


def hash_api_key(pepper: bytes, key: str) -> str:
    return hmac.new(pepper, key.encode(), hashlib.sha256).hexdigest()


def display_prefix(key: str) -> str:
    return key[: len(KEY_PREFIX) + 4]


def looks_like_key(value: str) -> bool:
    return value.startswith(KEY_PREFIX) and 20 <= len(value) <= 128 and value.isascii() and value.isprintable()

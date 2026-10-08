from __future__ import annotations

import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable


class RateLimiter:
    """Sliding-window limiter, in-process. Correct for a single worker; with multiple
    workers/hosts move this to Redis (the interface is deliberately tiny)."""

    def __init__(self, limit: int, window_s: float = 60.0, clock: Callable[[], float] = time.monotonic):
        self.limit, self.window, self._clock = limit, window_s, clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, key: str, *, consume: bool = True) -> float | None:
        """Return None if allowed, else seconds until the next slot."""
        now = self._clock()
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] >= self.window:
                q.popleft()
            if len(q) >= self.limit:
                return max(0.1, self.window - (now - q[0]))
            if consume:
                q.append(now)
            if not q:
                self._hits.pop(key, None)
            return None

    def blocked(self, key: str) -> float | None:
        return self.check(key, consume=False)

    def record(self, key: str) -> None:
        with self._lock:
            self._hits[key].append(self._clock())

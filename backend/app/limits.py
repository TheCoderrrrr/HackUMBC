"""Single-process guards: sliding-window rate limits (BACKEND.md section 15).

The limiter is per client (a demo key or an IP), not global: outside traffic can't
exhaust the demo phone's allowance (REPORT C2). Buckets are tiny and few at demo
scale, so idle ones are left to age out on their client's next call.
"""
from __future__ import annotations

import threading
import time
from collections import deque


def client_key(request) -> str:
    """Rate-limit bucket: the demo key when present, otherwise the caller's IP (C2)."""
    return request.headers.get("x-demo-key") or (request.client.host if request.client else "unknown")


class RateLimiter:
    def __init__(self, limit: int, window_seconds: float = 60.0, clock=time.monotonic):
        self.limit, self.window, self.clock = limit, window_seconds, clock
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def allow(self, key: str = "") -> bool:
        now = self.clock()
        with self._lock:
            hits = self._hits.setdefault(key, deque())
            while hits and now - hits[0] >= self.window:
                hits.popleft()
            if len(hits) >= self.limit:
                return False
            hits.append(now)
            return True

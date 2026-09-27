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
    """Sliding-window limit per key, with bounded memory.

    Keys come from request headers or IPs, so a caller can invent new ones freely. Idle keys
    are dropped, and the number of tracked keys is capped (oldest activity evicted first).
    """

    def __init__(self, limit: int, window_seconds: float = 60.0, clock=time.monotonic, max_keys: int = 4096):
        self.limit, self.window, self.clock, self.max_keys = limit, window_seconds, clock, max_keys
        self._hits: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def allow(self, key: str = "") -> bool:
        now = self.clock()
        with self._lock:
            hits = self._hits.get(key)
            if hits is None:
                if len(self._hits) >= self.max_keys:
                    self._sweep(now)
                hits = self._hits[key] = deque()
            while hits and now - hits[0] >= self.window:
                hits.popleft()
            if len(hits) >= self.limit:
                return False
            hits.append(now)
            return True

    def _sweep(self, now: float) -> None:
        """Drop keys idle for a full window; if still at the cap, evict the least recently active."""
        for key in [k for k, h in self._hits.items() if not h or now - h[-1] >= self.window]:
            del self._hits[key]
        while len(self._hits) >= self.max_keys:
            del self._hits[min(self._hits, key=lambda k: self._hits[k][-1])]

    def __len__(self) -> int:
        return len(self._hits)

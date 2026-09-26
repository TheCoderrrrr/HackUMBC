"""AI circuit breaker: skip the provider while it is rate-limiting or repeatedly timing out.

Without it, every request during a provider slowdown waits the full AI deadline
before falling back. With it, requests fall back immediately (labeled AI_COOLDOWN)
until the cooldown ends, then one request probes the provider again.
"""
from __future__ import annotations

import threading
import time


class AIBreaker:
    def __init__(self, timeout_threshold: int = 2, timeout_cooldown_s: float = 30.0,
                 rate_limit_cooldown_s: float = 30.0, clock=time.monotonic):
        self.timeout_threshold = timeout_threshold
        self.timeout_cooldown_s = timeout_cooldown_s
        self.rate_limit_cooldown_s = rate_limit_cooldown_s
        self.clock = clock
        self._open_until = 0.0
        self._consecutive_timeouts = 0
        self._lock = threading.Lock()

    def is_open(self) -> bool:
        with self._lock:
            return self.clock() < self._open_until

    def remaining_s(self) -> float:
        with self._lock:
            return max(0.0, self._open_until - self.clock())

    def record_success(self) -> None:
        with self._lock:
            self._consecutive_timeouts = 0

    def record_timeout(self) -> None:
        with self._lock:
            self._consecutive_timeouts += 1
            if self._consecutive_timeouts >= self.timeout_threshold:
                self._open_until = self.clock() + self.timeout_cooldown_s
                self._consecutive_timeouts = 0

    def record_rate_limited(self, retry_after_s: float | None) -> None:
        with self._lock:
            self._open_until = self.clock() + (retry_after_s or self.rate_limit_cooldown_s)

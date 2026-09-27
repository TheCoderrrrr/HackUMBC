"""RateLimiter memory stays bounded even when callers invent new keys."""
from app.limits import RateLimiter


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def test_limits_still_apply_per_key():
    clock = Clock()
    limiter = RateLimiter(2, window_seconds=60, clock=clock)
    assert limiter.allow("a") and limiter.allow("a") and not limiter.allow("a")
    assert limiter.allow("b")
    clock.t = 61
    assert limiter.allow("a")


def test_idle_keys_are_dropped_when_the_cap_is_reached():
    clock = Clock()
    limiter = RateLimiter(5, window_seconds=60, clock=clock, max_keys=100)
    for i in range(100):
        limiter.allow(f"old-{i}")
    clock.t = 120  # every old key is now idle
    limiter.allow("new")
    assert len(limiter) == 1


def test_key_count_never_exceeds_the_cap_under_a_flood_of_new_keys():
    clock = Clock()
    limiter = RateLimiter(5, window_seconds=60, clock=clock, max_keys=50)
    for i in range(10_000):
        clock.t = i * 0.001  # all still inside the window
        limiter.allow(f"spoofed-{i}")
        assert len(limiter) <= 50
    assert limiter.allow("spoofed-9999") is True  # the most recent key survives eviction

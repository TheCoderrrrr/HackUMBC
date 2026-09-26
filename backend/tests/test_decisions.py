from __future__ import annotations

from app.decisions import DecisionSnapshot, DecisionStore, new_decision_id
from app.limits import RateLimiter


def snap(profile_id="morgan"):
    return DecisionSnapshot(profile_id, "hash", {"x": 1})


def test_store_is_bounded_oldest_out():
    store = DecisionStore(max_entries=3)
    for i in range(5):
        store.put(f"d{i}", snap())
    assert len(store) == 3
    assert store.get("d0", "morgan") is None
    assert store.get("d4", "morgan") is not None


def test_store_expires_after_ttl():
    now = {"t": 0.0}
    store = DecisionStore(ttl_seconds=7200, clock=lambda: now["t"])
    store.put("d", snap())
    now["t"] = 7199
    assert store.get("d", "morgan") is not None
    now["t"] = 7201
    assert store.get("d", "morgan") is None


def test_store_requires_matching_profile():
    store = DecisionStore()
    store.put("d", snap("morgan"))
    assert store.get("d", "jordan") is None


def test_decision_ids_are_random_and_opaque():
    ids = {new_decision_id() for _ in range(100)}
    assert len(ids) == 100
    assert all(i.startswith("dec_") and len(i) > 20 for i in ids)


def test_rate_limiter_sliding_window():
    now = {"t": 0.0}
    limiter = RateLimiter(2, 60, clock=lambda: now["t"])
    assert limiter.allow() and limiter.allow() and not limiter.allow()
    now["t"] = 60
    assert limiter.allow()

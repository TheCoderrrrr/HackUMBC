"""Live smoke test against a running backend (local or through the HTTPS tunnel).

    python scripts/smoke.py                                  # http://127.0.0.1:8000
    python scripts/smoke.py https://<name>.trycloudflare.com # what the phone will use

Checks health, demo profiles, one evaluation per profile, and two error cases.
Exits non-zero if anything the demo depends on is broken. Uses only the standard
library, so it runs from any machine with Python 3.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request

IOS_TIMEOUT_S = 8.0


def call(base: str, path: str, body=None) -> tuple[int, dict, int]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method="POST" if data else "GET",
                                 headers={"content-type": "application/json"})
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=IOS_TIMEOUT_S) as res:
            status, payload = res.status, json.load(res)
    except urllib.error.HTTPError as err:
        status, payload = err.code, json.load(err)
    return status, payload, int((time.perf_counter() - started) * 1000)


def main() -> int:
    base = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
    failures: list[str] = []

    def check(ok: bool, label: str, detail: str = "") -> None:
        print(f"  {'PASS' if ok else 'FAIL'}  {label}{'  ' + detail if detail else ''}")
        if not ok:
            failures.append(label)

    print(f"Smoke test: {base}")
    try:
        status, health, ms = call(base, "/health")
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"  FAIL  server unreachable: {exc}")
        return 1
    check(status == 200 and health.get("status") == "ok", "GET /health", f"{ms}ms {health}")

    status, body, ms = call(base, "/v1/demo-profiles")
    profiles = {p["id"]: p for p in body.get("profiles", [])}
    check(status == 200 and set(profiles) == {"jordan", "morgan", "casey"}, "GET /v1/demo-profiles", f"{ms}ms {list(profiles)}")

    ai_count = 0
    for pid, profile in profiles.items():
        status, ev, ms = call(base, "/v1/evaluate", {"profile": profile})
        if status != 200:
            check(False, f"evaluate {pid}", f"HTTP {status} {ev.get('error')}")
            continue
        d = ev["decision_summary"]
        ai_count += d["source"] == "ai"
        detail = (f"{ms}ms decision={d['source']}({d['fallback_reason']}) "
                  f"explanation={ev['explanation']['source']} primary={ev['plan']['primary_action_id']}")
        check(ms < IOS_TIMEOUT_S * 1000, f"evaluate {pid}", detail)

    if "morgan" in profiles:
        bad = json.loads(json.dumps(profiles["morgan"]))
        bad["debts"][0]["minimum_payment_cents"] = 0
        status, err, _ = call(base, "/v1/evaluate", {"profile": bad})
        check(status == 422 and err["error"]["code"] == "INVALID_PROFILE", "invalid profile -> 422")
        status, err, _ = call(base, "/v1/evaluate", {"profile": profiles["morgan"],
                                                    "scenario": {"retirement_age": 67, "employee_contribution_rate": 0.5}})
        check(status == 422 and err["error"]["code"] == "INFEASIBLE_SCENARIO", "infeasible scenario -> 422")

    print(f"\nLive AI decisions: {ai_count}/{len(profiles)} (fallbacks are labeled and still demo-safe)")
    print("RESULT:", "OK" if not failures else f"{len(failures)} failure(s): {', '.join(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

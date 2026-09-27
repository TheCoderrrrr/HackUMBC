"""Live smoke test against a running backend (local or through the HTTPS tunnel).

    python scripts/smoke.py                                     # http://127.0.0.1:8000
    python scripts/smoke.py https://<your-team>.ngrok-free.dev  # what the phone will use

Checks health, demo profiles, one base evaluation per profile, the two "Compare
scenario" request shapes per profile (feasible Adaptive and Fixed-rate, verifying
projections.custom.feasible), and two error cases. Exits non-zero if anything the
demo depends on is broken. Uses only the standard library, so it runs from any
machine with Python 3.

The app's default server URL is a build-time setting (ios/Config/Server.xcconfig),
not committed, so there is no committed domain left to disagree with this one —
pass the same domain you built the app with.
"""
from __future__ import annotations

import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.request

IOS_TIMEOUT_S = 8.0

# When the server sets DEMO_KEY, /v1/* requires the shared header (REPORT C2).
DEMO_KEY = os.environ.get("DEMO_KEY", "").strip()


class BadBodyError(Exception):
    """The response wasn't the JSON contract — usually ngrok answering for a dead backend."""

    def __init__(self, status: int, ngrok_code: str | None, preview: str):
        self.status, self.ngrok_code, self.preview = status, ngrok_code, preview
        if ngrok_code:
            hint = (f"the tunnel answered, not the API (ngrok-error-code: {ngrok_code}) — "
                    "is uvicorn running behind it?")
        else:
            hint = "response is not the JSON contract"
        super().__init__(f"HTTP {status}: {hint}. Body starts: {preview!r}")


def call(base: str, path: str, body=None) -> tuple[int, dict, int]:
    data = json.dumps(body).encode() if body is not None else None
    headers = {"content-type": "application/json",
               # the app sends this too; opts out of ngrok's browser warning
               "ngrok-skip-browser-warning": "1",
               "accept-encoding": "gzip"}
    if DEMO_KEY:
        headers["x-demo-key"] = DEMO_KEY
    req = urllib.request.Request(base + path, data=data, method="POST" if data else "GET",
                                 headers=headers)
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=IOS_TIMEOUT_S) as res:
            status, raw, headers = res.status, res.read(), res.headers
    except urllib.error.HTTPError as err:
        status, raw, headers = err.code, err.read(), err.headers
    ms = int((time.perf_counter() - started) * 1000)
    if headers.get("content-encoding") == "gzip":
        raw = gzip.decompress(raw)
    try:
        return status, json.loads(raw), ms
    except json.JSONDecodeError:
        raise BadBodyError(status, headers.get("ngrok-error-code"),
                           raw[:200].decode("utf-8", "replace")) from None


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
    except BadBodyError as exc:
        print(f"  FAIL  GET /health: {exc}")
        return 1
    check(status == 200 and health.get("status") == "ok", "GET /health", f"{ms}ms {health}")
    if health.get("ai_available") is not True:
        print("  WARN  /health says ai_available is not true: live AI is off, every decision "
              "will be rules_fallback (check AI_PROVIDER and the provider key in backend/.env)")

    try:
        status, body, ms = call(base, "/v1/demo-profiles")
    except BadBodyError as exc:
        check(False, "GET /v1/demo-profiles", str(exc))
        return 1
    profiles = {p["id"]: p for p in body.get("profiles", [])}
    check(status == 200 and set(profiles) == {"jordan", "morgan", "casey"},
          "GET /v1/demo-profiles", f"{ms}ms {list(profiles)}")

    ai_count = 0
    for pid, profile in sorted(profiles.items()):
        try:
            status, ev, ms = call(base, "/v1/evaluate", {"profile": profile})
        except BadBodyError as exc:
            check(False, f"evaluate {pid}", str(exc))
            continue
        if status != 200:
            check(False, f"evaluate {pid}", f"HTTP {status} {ev.get('error')}")
            continue
        d = ev["decision_summary"]
        ai_count += d["source"] == "ai"
        detail = (f"{ms}ms decision={d['source']}({d['fallback_reason']}) "
                  f"explanation={ev['explanation']['source']} primary={ev['plan']['primary_action_id']}")
        check(ms < IOS_TIMEOUT_S * 1000, f"evaluate {pid}", detail)

        # The Compare button's two request shapes, feasible for every demo profile
        # (the infeasible path is checked separately below).
        compares = [
            ("adaptive, retire +2y", {"retirement_age": min(profile["retirement_age"] + 2, 80),
                                      "employee_contribution_rate": None}),
            ("fixed 10%", {"retirement_age": profile["retirement_age"],
                           "employee_contribution_rate": 0.10}),
        ]
        for label, scenario in compares:
            try:
                status, ev, ms = call(base, "/v1/evaluate", {"profile": profile, "scenario": scenario})
            except BadBodyError as exc:
                check(False, f"compare {pid} ({label})", str(exc))
                continue
            custom = ev.get("projections", {}).get("custom") if status == 200 else None
            ok = status == 200 and custom is not None and custom.get("feasible") is True
            detail = (f"{ms}ms custom.feasible={custom.get('feasible')}" if custom
                      else f"HTTP {status} {ev.get('error') if isinstance(ev, dict) else ev}")
            check(ok, f"compare {pid} ({label})", detail)

    if "morgan" in profiles:
        bad = json.loads(json.dumps(profiles["morgan"]))
        bad["debts"][0]["minimum_payment_cents"] = 0
        try:
            status, err, _ = call(base, "/v1/evaluate", {"profile": bad})
            check(status == 422 and err["error"]["code"] == "INVALID_PROFILE", "invalid profile -> 422")
            status, err, _ = call(base, "/v1/evaluate", {"profile": profiles["morgan"],
                                                        "scenario": {"retirement_age": 67,
                                                                     "employee_contribution_rate": 0.5}})
            check(status == 422 and err["error"]["code"] == "INFEASIBLE_SCENARIO", "infeasible scenario -> 422")
        except BadBodyError as exc:
            check(False, "error cases", str(exc))

    print(f"\nLive AI decisions: {ai_count}/{len(profiles)} (fallbacks are labeled and still demo-safe)")
    print("RESULT:", "OK" if not failures else f"{len(failures)} failure(s): {', '.join(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

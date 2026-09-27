# Proposal: scenario fast path (`reuse_decision`)

**For:** Neil (API / AI pipeline). **From:** Eric. **Status:** tested, not applied.
**Patch:** [`scenario-fast-path.patch`](scenario-fast-path.patch) (backend + the matching iOS change).

## Why

Explore now recalculates the scenario chart as you change the retirement age or contribution
rate. Each change sends `POST /v1/evaluate` with a `scenario`, and today every one of those calls
runs **both AI steps again** (recommendation and explanation, up to the 4 s budget), even though
a what-if never changes the plan's priority order. Through the tunnel that is roughly 2–4.5 s
per change, spends AI budget on every stepper tap, and counts against the shared
120-requests-per-minute limit. The AI can also return a different order for the scenario than
for the plan on screen, so the two aren't strictly comparable.

## What the patch does

- **`schemas.EvaluateRequest`** gains an optional `reuse_decision: DecisionSummary | None`.
- **`pipeline.run`**, when it is present, re-checks it with the engine's validator
  (`engine.validate_decision`), the same way history saves do in `analytics/service.revalidate`.
  - If it still validates for this profile, the scenario uses it, **with no AI calls**, and the
    explanation is the template.
  - If it doesn't (another profile, a tampered or undocumented order), the request quietly takes
    the normal AI path. It never errors.
- **`contracts/openapi.json`** is regenerated (`scripts/export_contracts.py`), so
  `test_openapi_is_current` stays green.
- **iOS** (`APIContract.swift`, `AppStore.evaluateScenario`) sends the on-screen plan's
  `decision_summary` with each scenario request. It only encodes the field when set.
  **This half needs the server change first:** `EvaluateRequest` forbids unknown fields, so a
  current server would answer 422.

`/v1/evaluate` without `reuse_decision` behaves exactly as before.

## Evidence

- New `backend/tests/test_scenario_fast_path.py` (3 tests):
  - a reused AI decision makes **no model calls**, and its `input_hash` and projections equal a
    full evaluation's exactly;
  - a rules-fallback decision is reusable too;
  - an invalid order falls back to asking the model.
- Full suite with the patch: **488 passed**, 2 skipped.
- Simulator, against a local server whose stand-in model takes 1.5 s per call:

  | Request | Time | AI calls |
  |---|---:|---:|
  | Base plan | 3,142 ms | 2 |
  | Scenario with `reuse_decision` | 531 ms | 0 |

## Things to decide

- **Labels:** a reused decision keeps `source: "ai"` although no AI ran for this request. It is
  the plan's AI decision, re-validated, which is the same trust model history saves already use.
  If you'd rather label it, a `decision_reused: true` flag on the response would do it.
- **Rate limit:** reused requests are cheap; they could skip `evaluate_limiter` or use a looser one.

## Apply

```bash
git apply docs/proposals/scenario-fast-path.patch
cd backend && .venv/bin/python -m pytest -q
```

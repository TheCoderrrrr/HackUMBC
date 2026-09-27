# Scenario history on Tiger Data

Save a projection run, then compare two runs of the same profile over 5, 10 and 20 years. The desktop app's **Explore → Scenario history** panel uses it. `/v1/evaluate` never touches the database: without `TIGER_DATABASE_URL`, the history routes answer `503 HISTORY_DISABLED` and everything else works as before.

This targets the [hackUMBC Best Use of Tiger Data prize](https://hackumbc-2026.devpost.com/), which rewards time-series analytics with a visible user benefit: two saved scenarios diverging over time, with the yearly values coming from a Tiger Data continuous aggregate. Code lives in `backend/app/analytics/`, behind its own router, so the fund shortlist and the evaluation flow don't depend on it.

**Data rules:** synthetic demo profiles only. No real profiles, names, debts, API keys, or raw requests go to the cloud database, and neither does the raw SEC staging database. Projection points are stored as computed; SQL never recalculates financial policy. Credentials stay in git-ignored `backend/.env`.

## Setup

1. Create a Tiger Cloud service (TimescaleDB). Copy its connection string.
2. In `backend/.env` (git-ignored, never `.env.example`):
   ```
   TIGER_DATABASE_URL=postgres://tsdbadmin:…@….tsdb.cloud.timescale.com:3xxxx/tsdb?sslmode=require
   TIGER_SCHEMA=arm
   ```
3. From `backend/`: `pip install -r requirements.txt`, then optionally `python -m scripts.seed_history` to save two synthetic runs per demo profile.

Tables are created on first use (`store.migrations`). Every statement is idempotent.

## Data model

| Object | What it holds |
|---|---|
| `scenario_run` | One saved run: demo profile ID, server-built label, scenario, decision source/order/model, prompt/model/policy versions, assumptions, `input_hash` (unique). |
| `projection_point` | Hypertable on the integer `month`, one row per `(run, strategy, month)` with retirement, cash and debt in integer cents, plus `projected_on`. |
| `projection_yearly` | Continuous aggregate: `time_bucket(12, month)` with `first(value, month)`. Real-time mode is on, and each save refreshes its window. |

- **Dates:** month *m* is dated the first day of the month *m* months after the profile's `as_of_date` month, the same rule as the apps' month labels. These are projected dates under illustrative assumptions, not observed market data.
- **Yearly values:** year *y* is the point at month 12·*y*, the same sampling as the desktop chart (`balanceAtYear`).
- **Integrity:** the app sends a shown result's *inputs* (demo profile ID, scenario, decision, `input_hash`), never its numbers. The server re-validates the decision, re-runs the engine, and saves only if its recomputed `input_hash` matches (else `409 STALE_RESULT`). Only demo profiles can be saved, so no personal data reaches the cloud.

## API

| Route | Purpose |
|---|---|
| `GET /v1/history/status` | `{enabled, available}` |
| `POST /v1/history/runs` | Save a run: `201` new, `200` already saved (same `input_hash`) |
| `GET /v1/history/runs?profile_id=` | Up to 20 runs, newest first |
| `GET /v1/history/compare?base=&other=` | Yearly timeline and 5/10/20-year horizons for two runs of one profile |

## Demo query

```sql
SELECT r.label, y.projected_on, y.retirement_balance_cents / 100 AS retirement_usd,
       y.cash_cents / 100 AS cash_usd, y.debt_cents / 100 AS debt_usd
FROM arm.projection_yearly y
JOIN arm.scenario_run r USING (run_id)
WHERE r.profile_id = 'morgan' AND y.strategy = r.primary_strategy AND y.month IN (60, 120, 240)
ORDER BY y.month, r.created_at;
```

## Tests

- `backend/tests/test_history.py`: rebuild equality with live and saved-AI results, date and yearly rules against ports of the app's `monthLabel` and `balanceAtYear`, idempotency, ordering, comparison, invalid or missing runs, and outage handling (in-memory store).
- `backend/tests/test_history_tiger.py`: the same flow against the real service in a throwaway schema. It checks that the hypertable and continuous aggregate exist, and that the aggregate returns exactly the app's yearly samples. Skipped without `TIGER_DATABASE_URL`.

## Teardown

`DROP SCHEMA arm CASCADE;` removes all history. Pause or delete the service in the Tiger Cloud console to stop billing ([pricing](https://www.tigerdata.com/pricing): 30-day no-card trial, then metered).

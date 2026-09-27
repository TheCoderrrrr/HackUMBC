# Scenario history on Tiger Data

Save a projection run, then compare two runs of the same profile over 5, 10 and 20 years. The desktop app's **Explore → Saved runs** tab uses it. `/v1/evaluate` never touches the database: without `TIGER_DATABASE_URL`, the history routes answer `503 HISTORY_DISABLED` and everything else works as before.

This targets the [hackUMBC Best Use of Tiger Data prize](https://hackumbc-2026.devpost.com/), which rewards time-series analytics with a visible user benefit: two saved scenarios diverging over time, with the yearly values coming from a Tiger Data continuous aggregate. Code lives in `backend/app/analytics/`, behind its own router, so the fund shortlist and the evaluation flow don't depend on it.

**Data rules:** demo profiles are synthetic. Users can also enter **their own numbers** ("Your numbers" in the desktop app), which are stored here under an **anonymous key**: the browser generates 32 random bytes, sends them as `X-Profile-Key`, and the server stores and compares only their SHA-256. There's no email, account or required name. One key can hold up to 10 people; erasing a person removes them and every plan saved from them (`DELETE /v1/profiles/{id}`). API keys, raw requests and the SEC staging database never go to the cloud database. Projection points are stored as computed; SQL never recalculates financial policy. Credentials stay in git-ignored `backend/.env`.

## Setup

1. Create a Tiger Cloud service (TimescaleDB). Copy its connection string.
2. In `backend/.env` (git-ignored, never `.env.example`):
   ```
   TIGER_DATABASE_URL=postgres://tsdbadmin:…@….tsdb.cloud.timescale.com:3xxxx/tsdb?sslmode=require
   TIGER_SCHEMA=arm
   ```
3. From `backend/`: `pip install -r requirements.txt`, then optionally `python -m scripts.seed_history` to save two synthetic runs per demo profile. The script loads `backend/.env` itself and is idempotent.

Tables are created on first use (`store.migrations`). Every statement is idempotent.

## Data model

| Object | What it holds |
|---|---|
| `scenario_run` | One saved run: demo profile ID, server-built label, scenario, decision source/order/model, prompt/model/policy versions, assumptions, `input_hash` (unique), and `planning_preference` (the plan style used, so the app can reopen the run with the same choices). |
| `projection_point` | Hypertable on the integer `month`, one row per `(run, strategy, month)` with retirement, cash and debt in integer cents, plus `projected_on`. |
| `user_profiles` | People's own numbers: the form as entered and the built profile (JSON), keyed by `(owner_key_hash, profile_id)` with IDs `u-` + 8 hex digits. A profile from the earlier single-profile table is copied in once as `me`. |
| `scenario_run.owner_key_hash` | Owner of a run saved from a user's numbers; `NULL` for shared demo runs. Uniqueness is `(input_hash, owner)`, so identical plans by different users stay separate. |
| `projection_yearly` | Continuous aggregate: `time_bucket(12, month)` with `first(value, month)`. Real-time mode is on, and each save refreshes its window. |
| Compression | `projection_point` is compressed, segmented by `(run_id, strategy)` and ordered by `month`, with a compression policy. Saved projections never change. Measured on the live service: 1.38 MB → 262 KB (81% smaller) for 5,887 points. Reads and deletes work on compressed chunks. |

Connections come from a small lazy pool (`psycopg-pool`, 0–4 connections, health-checked, 5-minute idle). The first call takes about 336 ms (schema check and TLS), then about 20 ms each.

- **Dates:** month *m* is dated the first day of the month *m* months after the profile's `as_of_date` month, the same rule as the apps' month labels. These are projected dates under illustrative assumptions, not observed market data.
- **Yearly values:** year *y* is the point at month 12·*y*, the same sampling as the desktop chart (`balanceAtYear`).
- **Integrity:** the app sends a shown result's *inputs* (demo profile ID, scenario, decision, `input_hash`), never its numbers. The server re-validates the decision, re-runs the engine, and saves only if its recomputed `input_hash` matches (else `409 STALE_RESULT`). Demo runs are shared; runs saved from a person's numbers need their key and are visible only to it.

## API

| Route | Purpose |
|---|---|
| `GET /v1/history/status` | `{enabled, available}` |
| `POST /v1/history/runs` | Save a run: `201` new, `200` already saved (same `input_hash`) |
| `GET /v1/history/runs?profile_id=` | Up to 20 runs, newest first |
| `GET /v1/history/compare?base=&other=` | Yearly timeline and 5/10/20-year horizons for two runs of one profile, read in one query |
| `GET` / `POST /v1/profiles` | List the key's people, or add one (`201`; `409 PROFILE_LIMIT` after 10). Needs `X-Profile-Key` |
| `GET` / `PUT` / `DELETE /v1/profiles/{id}` | Load, update or erase one person (erasing also removes only their runs) |
| `POST /v1/profiles/build` | Validate the form and preview the engine's financial state, without storing |
| `DELETE /v1/history/runs/{id}` | Delete a run: `204`, or `404` if it doesn't exist. Points go by `ON DELETE CASCADE`; the continuous aggregate is refreshed |

Saves also record the plan style (`planning_preference`), so a result made with a non-default style recomputes to the same `input_hash`. It's stored on the run and returned in every run summary: opening a saved run in the app restores that style and the run's scenario, re-evaluates, and checks the new `input_hash` against the stored one.

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
- `backend/tests/test_history_tiger.py`: the same flow against the real service in a throwaway schema. It checks the hypertable, the continuous aggregate (exactly the app's yearly samples), compression and its policy, reads through compressed chunks, delete, and pool reuse.
- The test suite never reads `backend/.env` (REPORT C7), so the Tiger tests are opt-in. From `backend/`:
  ```bash
  export $(grep -E '^TIGER_(DATABASE_URL|SCHEMA)=' .env | xargs) && pytest tests/test_history_tiger.py
  ```
- `desktop/src/data/live.test.ts` saves and deletes a run through a running backend (`ARM_API=http://127.0.0.1:8000 npx vitest run src/data/live.test.ts`).

## Teardown

`DROP SCHEMA arm CASCADE;` removes all history. Pause or delete the service in the Tiger Cloud console to stop billing ([pricing](https://www.tigerdata.com/pricing): 30-day no-card trial, then metered).

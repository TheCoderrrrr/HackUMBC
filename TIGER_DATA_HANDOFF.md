# Tiger Data handoff — time-series developer

Your objective is a working, visible **scenario-history comparison** for the retirement planner, backed by Tiger Data. This is independent of the fund shortlist. Read [BACKEND.md](BACKEND.md), [BACKEND_TEAM_SPLIT.md](BACKEND_TEAM_SPLIT.md), and this file before changing the API. The existing app already computes `current`, `adaptive`, and optional `custom` monthly projections; your work stores and queries their dated points for a comparison view.

## Why this use of Tiger Data

The [hackUMBC Best Use of Tiger Data prize](https://hackumbc-2026.devpost.com/) emphasizes time-series analytics and a demonstrable user benefit. A useful demo shows how two saved retirement scenarios diverge over 5, 10, and 20 years, with balance, cash, and debt charts coming from Tiger Data queries. Do not migrate the roughly 985 MB raw SEC staging DB merely to claim database usage. The fund developer can later export small, verified, dated fund facts if the first feature is complete.

Tiger Data is PostgreSQL with time-series features such as hypertables and continuous aggregates; use its [official docs](https://www.tigerdata.com/docs) for current connection and SQL syntax. [Tiger Cloud pricing](https://www.tigerdata.com/pricing) currently lists a 30-day no-card trial, then metered service. Keep credentials in ignored `backend/.env`, never in the client, fixtures, logs, or Git.

## Existing integration contract

- API entry: `POST /v1/evaluate` in `backend/app/api.py`; keep its current request/response behavior intact.
- Pydantic outputs: `Evaluation.projections` in `backend/app/schemas.py` contains `current`, `adaptive`, and optional `custom` `Projection` objects. Each `ProjectionPoint` has `month`, `retirement_balance_cents`, `cash_cents`, and `debt_cents`. `Evaluation` also carries `profile_id`, `input_hash`, `model_version`, `policy_version`, and `assumptions`.
- Engine: `backend/app/engine/simulation.py` produces the points. Treat them as immutable results; do not recalculate or change financial policy in SQL.
- This is a synthetic-data hackathon demo with no account system. Use demo-profile IDs and synthetic results only; do not upload real user profiles, names, debts, API keys, or raw requests to the cloud database.

## Small implementation path

1. Set up a Tiger Cloud service (or confirm with organizers if a self-hosted TimescaleDB instance qualifies for the sponsor prize). Add a connection setting with a clear disabled/unavailable mode. Never make existing `/v1/evaluate` dependent on database uptime.
2. Add migrations and a narrow persistence adapter under a new `backend/app/analytics/` area. Suggested records: one `scenario_run` with a run ID, synthetic profile ID, timestamp, strategy, model/policy/assumption provenance; and dated `projection_point` rows keyed by run, strategy, and month. Store monetary fields as integer cents. Choose and document how `month` maps to a projected date; do not pretend projections are observed market data. Use a Tiger Data time-series feature on the dated points and explain what it does in the demo.
3. Seed two or three **synthetic** runs from existing fixtures/evaluations. Query two runs for one profile and return a compact comparison timeline through a separate endpoint or demo view. Keep database-specific SQL inside the analytics adapter. If unavailable, the existing planning flow must still work.
4. Add focused tests for insertion/idempotency, month ordering, scenario comparison, invalid/missing runs, and database failure. Verify the actual Tiger-backed query once with the cloud instance. A mock-only integration will not demonstrate sponsor use.
5. Show one clear screen or chart comparing scenarios over time, with source label and model assumptions. In the pitch, show the database-backed query and what changes for the user; merely connecting to PostgreSQL adds little value.

Do not modify `backend/app/funds.py`, `backend/scripts/import_sec_mfrr.py`, `backend/scripts/audit_sec_candidates.py`, or the fund catalog. Coordinate any shared edits to `backend/app/api.py`, `backend/app/main.py`, `backend/app/config.py`, and `backend/app/schemas.py` with the fund developer first. Prefer a separate router or adapter so merges stay small.

## Delivery checks and Git

- The existing evaluation works when Tiger Data is disabled or unreachable.
- Two synthetic runs can be written, queried, and compared with a real Tiger Data connection; dates, cents, and provenance are correct.
- Tests pass and no credential or personal finance input appears in logs/commits.
- Record setup steps, SQL/migrations, demo query, and teardown in your own short README.
- Work on a separate branch. The fund-related files are currently **untracked locally**, so a fresh clone will not include them until the fund developer commits and pushes. Your initial work does not depend on them.

The [hackUMBC rules](https://hackumbc-2026.devpost.com/rules) say submitted work and repository commits must fall within the September 26, 2026 noon–September 27, 2026 11:45 a.m. EDT hacking period. The [submission page](https://hackumbc-2026.devpost.com/) also requires a public GitHub link and a short demo video. Confirm track details with organizers if anything on the site conflicts with event instructions.

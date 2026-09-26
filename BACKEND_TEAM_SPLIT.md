# Backend Team Split

This document assigns the three backend workstreams for the Adaptive Retirement prototype. The team is building one Python service; the same deterministic engine must power the live API and the saved offline demo.

## Shared rules

- Use the contract in [BACKEND.md](BACKEND.md) and keep it synchronized with [FRONTEND.md](FRONTEND.md).
- Python, not AI, calculates money, matching, debt payments, allocations, and projections.
- Money is integer USD cents; use `Decimal` with `ROUND_HALF_UP` for cash and debt accounting.
- Do not add databases, authentication, microservices, Docker, or production banking support.
- Keep `main` buildable. Use small branches and reviewed squash merges.

## Developer A — API, contracts, and integrations

**Owns:** the server boundary and external services.

- Create FastAPI setup and the `/health`, `/v1/demo-profiles`, and `/v1/evaluate` routes.
- Own Pydantic schemas, OpenAPI generation, request validation, version fields, and the shared error envelope.
- Connect API requests to the evaluator supplied by the financial-engine and simulation workstreams.
- Implement bounded AI orchestration: structured output, four-second total deadline, model configuration, in-memory prior-decision storage, and rules/template fallback wiring.
- Own the optional Plaid Sandbox adapter, in-memory token sessions, request limits, environment validation, HTTPS tunnel, and presenter runbook.

**Primary files:**

```text
backend/app/main.py
backend/app/api.py
backend/app/schemas.py
backend/app/integrations/plaid.py
backend/.env.example
contracts/openapi.json
contracts/examples/
```

**Deliverable:** a phone-reachable API that returns a validated evaluation for Morgan and continues to work when AI or Plaid is unavailable.

## Developer B — Financial state, policy, and explanations

**Owns:** financial meaning and the first-month recommended plan.

- Build canonical fixtures and the constants in `assumptions.py`.
- Implement derived state: contribution cash cost, allocatable budget, emergency months, employer matching, high-interest debt, and glide-path equity weight.
- Implement the deterministic waterfall, contribution cap rules, matching calculations, affordability checks, debt avalanche ordering, actions, reason facts, and constraint checks.
- Validate AI priority proposals and create the deterministic rules fallback.
- Define the template explanations and financial facts used by live and saved AI explanations.
- Write unit tests for arithmetic, matching, liquidity, debt, tax-treatment, and Morgan's opening-month acceptance case.

**Primary files:**

```text
backend/app/engine/assumptions.py
backend/app/engine/state.py
backend/app/engine/policy.py
backend/fixtures/profiles.json
backend/tests/test_state.py
backend/tests/test_policy.py
```

**Deliverable:** a tested `derive_state`, `validate_decision`, and `build_plan` implementation that produces a funded first-month adaptive plan.

## Developer C — Simulation, offline artifacts, and reliability

**Owns:** monthly projections and the backend-offline handoff.

- Implement current, adaptive, and custom strategy simulation.
- Model monthly debt interest and payoff, annual growth, employee limits, contributions, matching, retirement returns, inflation-adjusted balances, points, and milestones.
- Enforce conservation-of-cash and other simulation invariants.
- Implement `evaluate` composition with the engine interfaces provided by Developer B.
- Build `export_demo.py`, saved decision replay, stable profile/input hashes, artifact manifest, and the nine required preset evaluations.
- Write simulation, export, determinism, and outage-mode tests.

**Primary files:**

```text
backend/app/engine/simulation.py
backend/app/engine/evaluate.py
backend/scripts/export_demo.py
backend/fixtures/decisions.json
backend/fixtures/generated/
backend/tests/test_simulation.py
backend/tests/test_export.py
```

**Deliverable:** deterministic projections plus generated offline artifacts for every profile and preset, with no live model call during export.

## Integration order

1. **First hour:** agree on Pydantic model names, versions, `FinancialState`, `Plan`, `Evaluation`, and the three fixtures. Developer A exposes `/health`; Developer B pins Morgan's first-month arithmetic; Developer C scaffolds projection interfaces.
2. **Hours 1–4:** integrate one vertical slice: `POST /v1/evaluate` for Morgan returns state, a first-month adaptive plan, reasons, and a current/adaptive projection shell.
3. **Hours 4–10:** finish waterfall, AI validation/fallback, full simulations, and scenario support in parallel.
4. **By hour 12:** generate and commit all nine offline presets. Confirm the iOS client decodes API examples and bundled artifacts.
5. **After hour 12:** Plaid is optional. Cut it at hour 15 if the connect-import-confirm-evaluate flow is not complete.

## Handoffs and file boundaries

- Developer B publishes stable pure-function interfaces first. Developers A and C call those functions; they do not duplicate financial rules.
- Developer A owns schema files. Contract changes require updated OpenAPI/examples and a Swift decode check.
- Developer C owns generated artifact structure. Artifacts must come from the real evaluator, never handwritten totals.
- Coordinate before changing shared fixtures, assumptions, `Evaluation`, or engine interfaces. Keep each change backward-compatible when possible.
- AI cannot alter protected policy: essentials, debt minimums, critical reserve, matching formula, contribution cap, reserve dependency, debt ordering, assumptions, or equity allocation.

## Done criteria

The backend is ready when the API and offline bundle use the same tested evaluator; every recommended dollar is affordable; Morgan's $963.80 extra debt payment passes; all nine presets regenerate deterministically; and the phone demo remains usable if the live server, AI provider, or Plaid is unavailable.

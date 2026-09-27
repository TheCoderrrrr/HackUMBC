# Financial engine: ownership and interfaces

How the three backend workstreams divide the Adaptive Retirement Management (ARM) engine, and the exact function contracts between them. [BACKEND.md](BACKEND.md) is the full specification; this file is the working reference for the seams between Developer A (API), B (financial state and policy), and C (simulation and offline bundle).

## Shared rules

- Use the contract in [BACKEND.md](BACKEND.md) and keep it synchronized with [FRONTEND.md](FRONTEND.md).
- Python, not AI, calculates money, matching, debt payments, allocations, and projections.
- Two fixed agent calls: Recommendation receives Python-computed `FinancialState` indicators and returns an ordering, rationale, and tradeoffs; Explanation describes the validated decision and computed changes. There is no Financial State Agent.
- The `planning_preference` ordering table is the default order and the rules fallback. The Recommendation Agent may choose any of the three documented orders for any profile; the saved Morgan cash-security variant demonstrates a non-default order. Python validates every proposal before use.
- Money is integer USD cents; use `Decimal` with `ROUND_HALF_UP` for cash and debt accounting.
- AI cannot alter protected policy: essentials, debt minimums, critical reserve, matching formula, contribution cap, reserve dependency, debt ordering, assumptions, or equity allocation.
- Coordinate before changing shared fixtures, assumptions, `Evaluation`, or engine interfaces. `tests/test_engine_interface.py` and `tests/test_public_interface.py` fail if the names and signatures other developers import change.

## Ownership

| Developer | Owns | Primary files |
|---|---|---|
| **A** (Neil): API, contracts, integrations | FastAPI routes, Pydantic schemas, OpenAPI, error envelope, both AI calls with one four-second deadline, rules/template fallback wiring, `previous_decision_id` replay (128 entries, two hours, in memory), optional Plaid Sandbox, runbook | `app/main.py`, `app/api.py`, `app/schemas.py`, `app/ai/`, `app/engine_port.py`, `contracts/` |
| **B** (Kevin): financial state, policy, explanations | Fixtures, assumptions, derived state, the waterfall, matching, affordability, debt avalanche, decision validation, rules fallback, template explanations | `app/engine/{assumptions,money,validation,state,policy,explanations}.py`, `fixtures/profiles.json`, `fixtures/morgan-cash-security-profile.json` |
| **C** (Eric): simulation, offline artifacts | Current/Adaptive/Custom simulation, `evaluate` composition, canonical hashes, saved-decision replay, the ten-artifact offline bundle | `app/engine/{monthly,simulation,evaluate,canonical}.py`, `scripts/export_demo.py`, `scripts/prepare_decisions.py`, `fixtures/decisions.json`, `fixtures/generated/` |

Developer B publishes stable pure functions; A and C call them and never duplicate financial rules. A owns schema files, so contract changes need regenerated OpenAPI/examples (`scripts/export_contracts.py`) and a Swift decode check. C owns the artifact structure; artifacts come from the real evaluator, never handwritten totals.

## Data boundary

Engine functions accept mappings with the canonical JSON field names and return JSON-compatible dictionaries. A passes `profile.model_dump(mode="json")` and validates results with the shared Pydantic models; there is no second set of schemas in the engine.

Gross monthly salary is kept unrounded internally until a monetary result is produced. The take-home reconstruction applies the tax adjustment to the exact salary-rate product before rounding; the allocator computes the cash cost of the actual cent-denominated contribution.

`ProfileValidationError` is a `ValueError` with a `path` identifying the invalid input; the API maps it to `422 INVALID_PROFILE`. Unknown or unvested matching is a valid blocked assessment, not a zero employer match.

## Financial state and model input

`derive_state(profile)` returns the documented `FinancialState` fields. `recommendation_context(profile, state)` supplies an allowlisted context for the Recommendation call: `planning_preference`, `emergency_cash_cents`, `debt_burden`, `savings_capacity`, and a fixed subset of `financial_state`. It excludes names, profile/debt IDs, provenance text, bank identifiers, and raw import payloads (checked in `test_state.py`), so nothing in it needs to be withheld from the model.

Evidence paths refer to that context, for example `financial_state.high_interest_debt_cents`. Plan reason `input_paths` instead reference canonical profile inputs.

## Preference policy

- `balanced`: starter reserve, high-APR debt, full reserve.
- `cash_security`: starter reserve, full reserve, high-APR debt.
- `debt_reduction`: high-APR debt, starter reserve, full reserve.

Any of the three is a valid Recommendation choice for any profile. Python rejects incomplete, duplicate, unknown, or full-before-starter orders. `engine_port.permitted_orders` lists all three with the preference default first.

Model proposals contain only `ordered_priorities` and `rationale` (each item: `priority`, `summary`, `evidence_paths`, `tradeoff`). Model and prompt identifiers are trusted caller metadata. Python supplies the decision ID, source, fallback reason, and constraint checks. During saved-decision replay, extract the proposal fields from a saved `DecisionSummary` and pass provenance separately.

Rationale must be qualitative. Numeric amounts belong in Python-generated facts and templates; unsupported numeric or outcome claims cause rules fallback even when an evidence path exists.

## Developer A: first-month plan

```python
from app.engine.state import derive_state, recommendation_context
from app.engine.policy import validate_decision, build_plan
from app.engine.explanations import template_explanation

state = derive_state(profile)
context = recommendation_context(profile, state)
# The provider wrapper obtains a proposal, or uses None on an unavailable call.
decision = validate_decision(profile, state, proposal, model_id=model_id)
plan = build_plan(profile, state, decision)
explanation = template_explanation(profile, state, decision, plan)
```

Skip provider calls when state warnings contain `MISSING_REQUIRED_INPUT` or `CASH_FLOW_SHORTFALL`; the engine still produces a blocked plan. An explanation-only provider failure keeps the accepted decision and uses `template_explanation`.

`build_plan` returns `primary_action_id`, `actions`, and `reasons`. For feasible plans, action cash costs sum to resources minus living expenses. Debt action cash cost includes minimum and extra payments; employee contribution cash cost occurs once; employer matching is a reason fact, not a cash expense. `render_reason(reason)` renders one reason. `ADJUST_CONTRIBUTION` and `MAINTAIN_DEBT_MINIMUM` explain a reduction or a required-only payment.

Decision IDs are random; numeric reproducibility excludes IDs and prose. A computes trusted change records from the prior-decision cache and passes them as `changes=` to `template_explanation`.

## Developer C: monthly policy

```python
from app.engine.policy import allocate_month

allocation = allocate_month(profile, state, decision)
# Subsequent months use the SAME original profile, state, and validated decision:
allocation = allocate_month(
    profile, state, decision,
    month=month_snapshot,
    strategy="adaptive",  # "current" or "custom" are also supported
)
```

`month_snapshot` has exactly these keys, all money in integer cents:

```text
annual_gross_salary_cents
monthly_resources_before_retirement_cents
monthly_living_expenses_cents
annual_employee_limit_cents
emergency_cash_cents
debts
```

Retain every original debt ID, type, APR, and entered minimum, including debts with a zero balance after payoff; only balances evolve. Do not pass a capped final-month payment back as the entered minimum.

The allocator accrues debt interest exactly once, caps minimum payments, and returns interest, minimum/extra/total payments, closing balances, employee contribution and rate, cash cost, employer match, reserve-stage allocations, residual cash, total cash added, feasibility, shortfall, and warnings. The simulation must not accrue interest or reserve debt payments again.

- `current` holds the original election subject to the modeled cap, pays minimums, and keeps the residual as cash.
- `adaptive` applies the waterfall with the one validated decision order for the whole horizon.
- `custom` with no rate applies adaptive policy at the selected retirement age. With `employee_contribution_rate=` it funds that election before reserve priorities; an unaffordable election raises `InfeasibleScenario` with the first failing month (`422 INFEASIBLE_SCENARIO`) and never silently lowers the rate. An election above the original annual cap raises `ValueError`.

The monthly employee cap is `annual_limit_cents // 12`. Match uses the actual cent contribution. Every feasible month must satisfy:

```text
resources_cents = living_expenses_cents
                + sum(debt.total_payment_cents)
                + employee_cash_cost_cents
                + total_cash_added_cents
```

## Simulation rules

- Current and Adaptive keep the profile retirement age; adding Custom does not alter either. Each strategy has independent balances and includes month 0 before any returns or payments.
- Before months 13, 25, and later anniversaries, salary, reconstructed resources, living expenses, and the annual cap grow and round once. Pass grown resources directly; the original election stays the restoration target. Month snapshots never trigger AI calls or change the accepted order.
- Weighted illustrative returns apply to opening retirement assets; contributions and match arrive at month end. Cash interest applies to opening cash only. Equity weight uses the beginning-of-month horizon.
- An invariant failure (cash identity, contribution ceiling, debt identities, negative balances, missing debt IDs) raises an engine error, not a scenario shortfall.
- Debt-free and reserve milestones start at month 0 when already satisfied, then record the first later month end that meets the target. A blocked Current or Adaptive projection has empty points, null terminal values and milestones, and a warning; other strategies survive. Allocator warnings (negative amortization, custom liquidity delays) propagate to the evaluation.
- `evaluate` checks that B's displayed first-month plan equals Adaptive's opening allocation and fails if they differ.

Provider-free evaluation medians (macOS arm64, Python 3.12): Jordan 98 ms, Morgan 97 ms, Casey 19 ms, within the 250 ms fixture target.

## Hashes and the offline bundle

The canonical hash starts from validated models with defaults populated, sorts keys recursively, preserves list order, normalizes equivalent numbers and negative zero, rejects non-finite numbers, and encodes compact UTF-8 JSON. The evaluation `input_hash` covers profile, scenario, assumptions, three versions, decision source, ordered priorities, model ID, and prompt version. It excludes decision IDs, generated text, timestamps, and previous-decision IDs. API and exporter share this serializer, so changing the provider, model, or prompt version means regenerating saved decisions and re-exporting.

The bundle has three standard profiles plus the Morgan cash-security variant (same inputs, new ID and preference). Nine standard artifacts cover Original, retirement +2 years, and contribution +1 point; the tenth is the variant's Original. `manifest.json` lists the three standard IDs in `default_profile_ids` and links the variant to Morgan. Saved standard decisions keep the preference default (so Morgan's $963.80 holds); only the variant saves starter → debt → full.

Saved AI text needs no human sign-off (team decision); it is demo placeholder content. The exporter still rejects numbers in prose, invalid decisions, and stale hashes. It builds in a sibling staging directory, reloads and validates all twelve files, publishes with a recoverable backup, and refuses concurrent runs.

```sh
cd backend
python -m scripts.prepare_decisions --force   # only to regenerate saved AI text
python -m scripts.export_demo                 # run twice and compare bytes
cp fixtures/generated/*.json ../ios/AdaptiveRetirement/Resources/Demo/
```

## Local verification

From `backend/` with the virtual environment active:

```powershell
pip install -r requirements-test.txt
python -m pytest -p no:cacheprovider
```

`backend/pytest.ini` supplies the import path. `.tools`, `.venv`, caches, and local credentials are ignored by Git.

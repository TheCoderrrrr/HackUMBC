# Developer B financial engine handoff

This package implements the financial state, bounded decision validation, cash allocation policy, and deterministic plan explanations in `BACKEND.md`. API schemas, provider calls, decision-session storage, complete projections, and artifact export remain with Developers A and C as assigned in `BACKEND_TEAM_SPLIT.md`.

## Status at handoff

Developer B's independent implementation is complete and reviewed. The backend test suite passes: **170 tests**, including Morgan's $963.80 extra card payment, contribution and matching arithmetic, cash conservation, blocked inputs, AI proposal fallback, changing monthly budgets, and Current/Adaptive/Custom allocation. The final review found no remaining critical or important issue in this scope. This is an engine handoff, not a claim that the live API, full projections, or offline bundle are finished.

Implemented files:

```text
app/engine/{assumptions,money,validation,state,policy,explanations}.py
fixtures/profiles.json
fixtures/morgan-cash-security-profile.json
tests/{test_state,test_policy,test_plan,test_monthly_allocation,test_review_regressions}.py
```

The three canonical profiles are Jordan, Morgan, and Casey in `profiles.json`. The separate Morgan cash-security profile is the input for the tenth saved demonstration; it does not contain a fabricated AI decision or precomputed evaluation. All generated artifacts and their model/prompt provenance remain Developer C's work, with Developer A and B review.

## What Developer B still needs to do with the team

1. **Contract integration with A:** validate that the Pydantic `FinancialProfile`, `FinancialState`, `Plan`, `DecisionSummary`, `AIExplanation`, and error envelope accept the engine's exact JSON fields and cent/rate types. Update contract examples when needed and have the iOS developer check Swift decoding. Confirm the API maps `ProfileValidationError.path`, blocked assessments, and unaffordable custom scenarios to the documented HTTP behavior.
2. **Saved-decision review with A and C:** inspect `fixtures/decisions.json` once generated. Check each ordering, evidence path, rationale, and tradeoff against the corresponding profile. Verify the Morgan cash-security exception is enabled only for its reviewed fixture. A confirms actual model/prompt provenance; C confirms that export replays validated decisions without live calls.
3. **Financial audit of C's evaluator and bundle:** compare the first simulated adaptive month with `allocate_month` and `build_plan`; check that debt interest is accrued once, caps and matching use actual contributions, final debt payments release cash once, and each feasible month conserves money. Verify all nine presets plus the tenth Morgan variant regenerate from the same evaluator with visible assumptions, correct hashes, and no handwritten totals.
4. **Outage and presentation sign-off:** confirm rules/template fallback labels and numeric results remain honest when AI fails, and that stopping the backend leaves the core saved demo usable. Repeat Morgan's documented opening arithmetic and the critical-reserve versus employer-match tradeoff in the presenter walkthrough.

These steps depend on A's schemas/provider wrapper and C's simulator/exporter. They should not be marked complete from Developer B's unit tests alone. The engine changes are currently local workspace files; they have not been committed or pushed in this handoff.

## Data boundary

Engine functions accept mappings with the canonical JSON field names and return JSON-compatible dictionaries. Developer A can pass `profile.model_dump(mode="json")` and validate results with the shared Pydantic output models. This keeps financial policy independent of API ownership; there is no second set of Pydantic schemas here.

Money is integer cents. Arithmetic uses `Decimal` and `ROUND_HALF_UP`. Gross monthly salary is kept unrounded internally until a monetary result is produced. The current take-home reconstruction applies the tax adjustment to the exact salary-rate product before rounding; the allocator computes the cash cost of the actual cent-denominated contribution.

`ProfileValidationError` is a `ValueError` with a `path` identifying the invalid input. Developer A should map it to the documented `INVALID_PROFILE` error envelope. Unknown or unvested matching is a valid blocked financial assessment, not a zero employer match.

## Financial state and model input

`derive_state(profile)` returns the documented `FinancialState` fields. `recommendation_context(profile, state)` supplies an allowlisted context for the Recommendation call. It includes Python-computed debt burden and savings capacity; it excludes names, profile/debt IDs, provenance text, bank identifiers, and raw import payloads.

Evidence paths refer to the returned recommendation context: for example, `planning_preference`, `emergency_cash_cents`, `debt_burden`, `savings_capacity`, and `financial_state.high_interest_debt_cents`. Do not send the full profile to the model. Plan reason `input_paths` instead reference canonical profile inputs, as required by the API contract.

## Preference policy

- `balanced`: starter reserve, high-APR debt, full reserve.
- `cash_security`: starter reserve, full reserve, high-APR debt.
- `debt_reduction`: high-APR debt, starter reserve, full reserve.

The `planning_preference` table is the rules fallback, not the only legal AI output. Any of the three documented orders is a valid Recommendation choice as long as starter reserve precedes full reserve. Python still rejects incomplete, duplicate, unknown, or full-before-starter permutations. The Morgan cash-security demo can therefore save starter → high-APR debt → full reserve without a fixture-hardcoded exception.

Model proposals contain only `ordered_priorities` and `rationale`. Each rationale contains `priority`, `summary`, `evidence_paths`, and `tradeoff`. Model/prompt identifiers are trusted caller metadata, not model-authored fields. Python supplies the decision ID, source, fallback reason, and constraint checks. Do not send a full `DecisionSummary` back as a raw model proposal during saved-decision replay; extract its proposal fields and pass its provenance separately.

Ask the provider for qualitative rationale and tradeoffs. Numeric amounts and percentages belong in the Python-generated labeled facts and templates. Unsupported numeric or outcome claims cause rules fallback even when an evidence path exists. These checks constrain model output; they are not a general proof that arbitrary natural-language reasoning is correct. Developer A still owns validation and fallback for the separate Explanation call.

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

Skip provider calls when state warnings contain `MISSING_REQUIRED_INPUT` or `CASH_FLOW_SHORTFALL`. The engine still produces a blocked plan. The provider wrapper owns the four-second deadline, provider error handling, and any more specific fallback-cause label. An explanation-only provider failure should keep the accepted decision and use `template_explanation`.

`build_plan` returns only `primary_action_id`, `actions`, and `reasons`. For feasible plans, action cash costs sum to resources minus living expenses. Debt action cash cost includes both minimum and extra payments; employee contribution cash cost occurs once; employer matching is supplied as a reason fact and is not a cash expense.

Call `render_reason(reason)` to render individual reason facts. Additional reason codes `ADJUST_CONTRIBUTION` and `MAINTAIN_DEBT_MINIMUM` explain a reduction or required-only debt payment without incorrectly calling either a contribution increase. Codes and template keys are strings, as in the shared contract.

Decision IDs are intentionally random. Numeric reproducibility excludes IDs and prose, as required by the specification. Developer A owns the prior-decision cache and computes trusted change records; pass those records as `changes=` to `template_explanation`. Developer C owns saved model provenance and decision fixtures, which still need joint A/B review before release.

## Developer C: monthly policy handoff

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

`month_snapshot` has exactly these keys:

```text
annual_gross_salary_cents
monthly_resources_before_retirement_cents
monthly_living_expenses_cents
annual_employee_limit_cents
emergency_cash_cents
debts
```

All money values are integer cents. Salary and living expenses are positive. Supply opening cash and opening debt balances. Retain every original debt ID, type, APR, and entered minimum, including debts with a zero balance after payoff. Only debt balances evolve. Do not pass the capped final-month payment back as the entered minimum.

The allocator accrues debt interest exactly once, caps minimum payments, and returns debt interest, actual minimum/extra/total payments, and closing balances. Do not accrue interest or reserve debt payments again in the simulation. It also returns employee contribution, actual contribution rate, cash cost, employer matching, reserve-stage allocations, residual cash, total cash added, feasibility, shortfall, and warnings.

The simulation owns anniversary growth, opening-to-closing cash updates, retirement investment returns, the changing glide path, month-zero points, milestones, inflation adjustments, and terminal projection fields. Pass already-grown monthly resources directly; do not reconstruct them from the original take-home again. The original election remains the restoration target. Month snapshots do not trigger AI calls or change the accepted priority order.

- `current` holds the original employee election subject to the modeled cap, pays minimums, and retains the residual as cash.
- `adaptive` applies the waterfall.
- `custom` with no override applies adaptive policy; the simulation owns the selected horizon.
- `custom` with `employee_contribution_rate=` funds the fixed election before reserve priorities and skips automatic additional retirement saving. An unaffordable election returns an infeasible result with the budget gap; map the submitted scenario to `422 INFEASIBLE_SCENARIO`. Validate the initial custom election with `month=None` before entering the loop. An election above the original annual cap raises `ValueError`; later snapshots apply their modeled monthly cap.

The monthly employee cap is floored to whole cents so the annualized ceiling is never exceeded. Match uses the actual cent contribution after cap/affordability limits. Every feasible month must satisfy:

```text
resources_cents = living_expenses_cents
                + sum(debt.total_payment_cents)
                + employee_cash_cost_cents
                + total_cash_added_cents
```

Stop an infeasible strategy and emit the blocked projection shape from `BACKEND.md`. Preserve other feasible strategies. Propagate allocator warnings, including negative amortization and custom liquidity delays, into the evaluation; `Plan` itself has no warnings field. A reviewed Morgan cash-security decision that uses a non-default documented order validates and allocates like any other accepted proposal.

## Local verification

The financial engine has no runtime dependencies outside Python 3.12's standard library. Install `backend/requirements-test.txt` into a virtual environment, then run from the repository root:

```powershell
.\.venv\Scripts\python.exe -m pytest backend
```

On macOS/Linux use `.venv/bin/python -m pytest backend`. `backend/pytest.ini` supplies the import path and test directory. `.tools`, `.venv`, caches, and local credentials are ignored by Git.

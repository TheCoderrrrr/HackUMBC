# What Developer B needs from Developers A and C

Developer B's engine (`app/engine/`) is finished and tested: 231 backend tests pass, including Developer A's API and AI-pipeline tests. The live API still runs on A's placeholder `engine_stub.py`, and none of Developer C's files exist yet. This page lists what each developer needs to provide or decide so the real engine can power the API and the offline demo.

See `DEVELOPER_B_HANDOFF.md` for how to call the engine.

## Team decision needed first: can the AI choose a non-default priority order?

After code review, the engine now accepts any of the three documented orders as an AI choice, and falls back to the `planning_preference` default only when a proposal is invalid. The review asked for this because rejecting every non-default order meant the AI could only agree with the rules.

The current spec says the opposite. `BACKEND.md` §9 (line 555) and `BACKEND_TEAM_SPLIT.md` (lines 10 and 49) say only the Morgan cash-security demo may use a non-default order. Please agree on one rule:

- **Keep the new behavior:** reword those three spec lines. No code change.
- **Restore the restriction:** Developer B will add it back as an explicit trusted flag passed in for the saved Morgan decision. The old version, which checked about 20 exact Morgan fixture values, will not come back.

## From Developer A (API and AI pipeline)

### 1. Connect the real engine through `engine_port.py`

`engine_port.py` imports `engine_stub`. The stub's numbers match our `derive_state` for all four fixtures, but its plan is a single placeholder action. The signatures differ, so switching the import alone will not work. The table lists each mismatch and what we suggest.

| `engine_port` function | Stub today | Real engine | Suggested adapter |
|---|---|---|---|
| `derive_state` | Returns Pydantic `FinancialState` | `state.derive_state(dict) -> dict` | `FinancialState.model_validate(derive_state(profile.model_dump(mode="json")))` |
| `blocking_issue` | Own rule | Blocked when `state["warnings"]` contains `MISSING_REQUIRED_INPUT` or `CASH_FLOW_SHORTFALL` | Read the engine's warnings; do not re-implement the rule |
| `agent_indicators` | Flat keys such as `liquidity.emergency_months` | `state.recommendation_context(profile, state)` with nested `financial_state.*` keys | See item 2 |
| `permitted_orders` / `default_order` | Now matches the engine | `policy.PREFERENCE_ORDER`, `policy.default_priorities` | Import from `policy` |
| `validate_decision` | Takes `decision_id`, `fallback_reason`; `model_id` inside the proposal | `validate_decision(profile, state, proposal, *, model_id, prompt_version)`; creates its own `decision_id` | See item 3 |
| `template_explanation` | `(profile, core, decision, changes)` | `explanations.template_explanation(profile, state, decision, plan, changes=None)` | Pass `core.financial_state` and `core.plan` as dicts |
| `evaluate` | Placeholder | Developer C's `evaluate.py` (not written yet) | Until C lands, use `policy.build_plan` for the plan and keep blocked projections |

### 2. Use one set of evidence-path names

This is the most important item. Your prompt tells the model to cite keys like `liquidity.emergency_months` and `debt.highest_debt_apr`. Our `validate_decision` only accepts keys that exist in `recommendation_context`, for example:

```text
planning_preference
emergency_cash_cents
debt_burden
savings_capacity
financial_state.emergency_months
financial_state.high_interest_debt_cents
financial_state.highest_debt_apr
financial_state.match_capture_fraction
```

If we connect the engine without fixing this, every AI proposal fails evidence validation and every response falls back to the rules order. Please send `recommendation_context` to the model instead of the stub's `agent_indicators`. If you want the flatter names for prompt readability, tell us and we will rename them in the engine so there is still only one list.

`situation_flags` in `ai/pipeline.py` also reads the flat keys, so it needs the same update.

### 3. Map proposals and fallback reasons at the boundary

- Our `validate_decision` rejects a proposal whose top-level fields are not exactly `ordered_priorities` and `rationale`. Pass `model_id` as the keyword argument, not inside the proposal.
- Our fallback reasons are uppercase codes: `NO_AI_PROPOSAL`, `BLOCKED_FINANCIAL_INPUT`, `INVALID_PRIORITY_ORDER`, `INVALID_EVIDENCE`, `UNSUPPORTED_RATIONALE_CLAIM`, and so on. Yours are `ai_unavailable`, `timeout`, `provider_error`, and `invalid_proposal: ...`. When the provider call fails, pass `proposal=None` and then set your more specific reason on the returned decision. Please agree with the iOS developer on one final set of strings.
- We create decision IDs with `secrets.token_urlsafe`. If you want your `dec_` prefix, override `decision_id` after validation. Do not generate the ID before validation.

### 4. Contracts and errors

- Check that `FinancialState`, `Plan`, `DecisionSummary`, and `AIExplanation` in `schemas.py` accept the engine's exact output. Our `build_plan` also produces the reason codes `ADJUST_CONTRIBUTION` and `MAINTAIN_DEBT_MINIMUM`.
- Map `ProfileValidationError` (from `app/engine/validation.py`, which has a `.path` attribute) to the `INVALID_PROFILE` error envelope.
- Map an infeasible custom election (`allocate_month(..., strategy="custom")` returns `feasible: False`) to `422 INFEASIBLE_SCENARIO`.
- `contracts/openapi.json` and `contracts/examples/` do not exist yet. Please generate them once the real engine is connected, so iOS can check decoding against real output.

### 5. Test environment

`requirements.txt` pins `pytest==9.1.1` and `requirements-test.txt` pins `pytest==8.4.2`. Installing one replaces the other. Please pick one version and remove the other pin.

## From Developer C (simulation, export, and offline artifacts)

Nothing from Developer C is on `main` or any branch yet. Three of Developer B's four remaining handoff steps are blocked on this work.

### 1. Files we are waiting for

```text
backend/app/engine/simulation.py
backend/app/engine/evaluate.py
backend/scripts/export_demo.py
backend/fixtures/decisions.json
backend/fixtures/generated/        (9 presets + morgan-cash-security.json + manifest)
backend/tests/test_simulation.py
backend/tests/test_export.py
```

### 2. How to use the engine in the simulation

The full contract is in `DEVELOPER_B_HANDOFF.md` under "Developer C: monthly policy handoff". The main rules:

- Call `allocate_month(profile, state, decision, month=snapshot, strategy=...)` once per month, always with the original profile, original state, and one validated decision. Do not call the AI inside the monthly loop.
- `month` snapshots must contain exactly `MONTH_KEYS`. Keep every original debt, including paid-off ones with a zero balance. Only balances change; type, APR, and entered minimum stay fixed.
- The allocator already accrues debt interest once and returns closing balances. Do not add interest or debt payments again in the simulation.
- Check the cash identity every feasible month: `resources = living + debt payments + employee cash cost + cash added`.
- For custom elections, first call with `month=None` to validate the original election. Stop an infeasible strategy and emit the blocked projection shape. Keep the other strategies.
- Pass allocator warnings (including `NEGATIVE_AMORTIZATION`) into the evaluation's `warnings`.

### 3. Saved decisions and the Morgan artifact

- `decisions.json` should store, for each profile, the model's proposal (`ordered_priorities` and `rationale`) separately from its provenance (`model_id`, `prompt_version`). During export, replay each decision with `validate_decision(profile, state, proposal, model_id=..., prompt_version=...)`. Do not pass a full `DecisionSummary` back in as the proposal; it will be rejected.
- The Morgan cash-security artifact uses `fixtures/morgan-cash-security-profile.json` and the order `starter_reserve`, `high_apr_debt`, `full_reserve`. No special flag is needed. Validation accepts this order, and the first month produces the $963.80 extra card payment.
- Include rules-fallback decisions for the outage path, and label saved AI decisions as saved, not live.
- Exclude decision IDs, timestamps, and prose from deterministic equality checks.

### 4. When C is ready, Developer B will

- Compare the first simulated adaptive month with `allocate_month` and `build_plan`.
- Review every saved decision's order, evidence paths, rationale, and tradeoffs together with Developer A.
- Check that all ten artifacts regenerate from the same evaluator with correct hashes and no handwritten totals.
- Sign off on the outage behavior: rules and template labels stay honest, and the saved demo works with the backend stopped.

Please send a message when a first version of `evaluate.py` is pushed, even before the exporter, so the first-month audit can start early.

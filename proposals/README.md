# Integration proposals from Developer C (Eric)

For Neil (A) and Kevin (B). These are proposals only. Nothing in your files was
changed on any branch; C's code on `Eric` works with `main` as is.

Status of `Eric` (merged with `main` at `0ff66cb`): 259 of 260 tests pass. The
one failure, `test_demo_profiles_are_the_three_fixtures`, also fails on `main`.
With Neil's patch below applied, all 265 pass.

## For Neil (A)

### 1. Use the real engine in the API: `neil-real-engine.patch`

`engine_port.py` still imports `engine_stub`, so every live evaluation returns
the stub plan, empty projections, and a `STUB_ENGINE` warning. The patch adds
`app/engine_real.py`, which implements every `engine_port` name with B's
functions and C's evaluator. It holds no financial rules; it only converts
between your Pydantic models and B/C's dictionaries.

Apply and test from the repository root:

```sh
git apply proposals/neil-real-engine.patch
cd backend && python -m pytest -q
```

What it changes and why:

- **Demo profiles.** B's `fixtures/profiles.json` is a JSON list; the stub
  expects `{"profiles": [...]}`. This is the test that fails on `main` today.
- **Errors.** B's `ProfileValidationError` becomes 422 `INVALID_PROFILE` with
  its field path; an unaffordable custom scenario becomes 422
  `INFEASIBLE_SCENARIO` with the budget gap (BACKEND.md section 11).
- **Evidence paths.** B's `validate_decision` only accepts evidence paths from
  B's `recommendation_context` (`emergency_cash_cents`, `debt_burden`,
  `savings_capacity`, `financial_state.*`). The stub's `liquidity.*`,
  `debt.*`, and `match.*` keys would all be rejected, so every live AI
  decision would fall back. `agent_indicators` now returns B's keys, and
  `situation_flags` in `pipeline.py` reads them. The test rationale in
  `conftest.py` uses the new keys.
- **Fallback reasons.** Your labels are kept (`ai_unavailable`, `timeout`,
  `provider_error`, `blocked_input: ...`). A proposal B rejects becomes
  `invalid_proposal: <B's code, lowercase>`, for example
  `invalid_proposal: invalid_evidence`.
- **Decision IDs.** Your `new_decision_id()` replaces B's random ID.
- **Privacy.** B's plan action IDs contain debt IDs (`debt-<id>`). The
  Explanation prompt received `primary_action_id`, which
  `test_prompts_exclude_identifying_data` caught once the real engine was
  connected. The prompt now receives the primary action's category and status.
- **One profile hash.** `pipeline.profile_hash` is replaced by C's
  `app.engine.canonical.profile_hash`, so API and offline bundle hashes
  match.
- **Tests.** `tests/test_engine_integration.py` checks Morgan's $963.80 card
  payment through the API, identical API and exporter results (including
  `input_hash`), the 422 for an unaffordable custom rate, and priority-order
  enforcement.

If you accept it, `engine_stub.py` and `stub_profiles.json` are no longer used
and can be deleted.

### 2. Checking saved explanations

C's exporter must check each saved AI explanation before it goes into the
offline bundle. Rather than asking you for a new function, C proposes to reuse
your existing rules: parse with `AIExplanation`, require `source == "ai"` and
empty `changes` (saved explanations describe an initial plan), and apply your
`valid_prose` from `app/ai/pipeline.py` (no numbers, length limits). Please
confirm this is the right check, or point C to a different one.

## For Kevin (B)

### 3. Which priority orders are allowed

`BACKEND_TEAM_SPLIT.md` says the `planning_preference` table governs standard
profiles and only the Morgan cash-security variant may show a non-default
order. Neil's tests enforce that. Your "update 2" lets `validate_decision`
accept any of the three documented orders for any profile.

Neil's patch follows the written spec: it lists only the default order (plus
the Morgan variant's exception) in the prompt, and rejects other orders with
`invalid_proposal: order_not_permitted`. The check sits in the adapter only
because your validator no longer does it. Please decide which rule is right.
If it is the spec, it belongs in `policy.validate_decision`, and the adapter
check can be removed.

### 4. Evidence the model sees

With Neil's patch, the Recommendation prompt contains exactly your flattened
`recommendation_context`, the same values your validator accepts as evidence.
Please confirm nothing there should be withheld from the model.

### 5. Test dependency pins

`backend/requirements.txt` pins `pytest==9.1.1`, and
`backend/requirements-test.txt` pins `pytest==8.4.2`. Installing both gives
whichever comes last. Please agree on one version with Neil.

## What C needs back

- Neil: accept or change items 1 and 2, and send the Gemini API key.
- Kevin: decide item 3 and confirm item 4.
- Both: review `backend/fixtures/decisions.json` once C generates it. Neil
  checks model/prompt provenance and structure; Kevin checks orders,
  rationale, and constraint checks. Mark each record by setting `reviewers` to
  `["A", "B"]`. The exporter refuses anything without both marks.

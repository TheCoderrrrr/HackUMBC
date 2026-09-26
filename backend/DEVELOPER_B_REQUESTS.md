# What Developer B needs from Developers A and C

Last updated after PR #6. The live API now runs on Developer B's engine and Developer C's evaluator, and all 269 backend tests pass on Windows. Most earlier requests are done. This page lists Developer B's answers to C's open questions and what B still needs.

## Done since the last version

- **A:** `engine_port.py` calls B's engine and C's evaluator; `engine_stub.py` is deleted.
- **A:** The Recommendation prompt sends B's `recommendation_context` and cites the same evidence keys the validator accepts.
- **A:** `ProfileValidationError` maps to `422 INVALID_PROFILE`, and an unaffordable custom scenario maps to `422 INFEASIBLE_SCENARIO`.
- **C:** `simulation.py`, `evaluate.py`, `export_demo.py`, `prepare_decisions.py`, and their tests are on `main`. `evaluate.py` checks that B's first-month plan equals the Adaptive opening allocation.
- **C:** `allow_morgan_exception` was removed from C's code after B deleted it.
- **B (in PR #6):** `export_demo.py` now also runs on Windows (`msvcrt` lock instead of `fcntl`, which exists only on macOS and Linux).

## Developer B's answers to C's questions

These answer items 3 and 4 in `proposals/README.md` and Kevin's items 1 and 2 in `ERIC_NEEDS.md`.

### Which priority orders are allowed: any of the three documented orders

The AI may choose any documented order for any profile. The `planning_preference` table is the rules fallback and the default listed first in the prompt. Python still rejects incomplete, duplicate, unknown, and full-before-starter orders. This follows the code review: if only the default is accepted, the AI can only agree with the rules.

This is already in place on `main`:

- `policy.validate_decision` accepts all three documented orders.
- `engine_port.permitted_orders` lists all three, with the preference default first.
- The `test_ai_pipeline.py` tests were updated to match.

C can generate saved decisions under this rule. The Morgan cash-security artifact uses `starter_reserve`, `high_apr_debt`, `full_reserve` with no special flag.

### Can the model see everything in `recommendation_context`: yes

It contains only allowlisted, normalized values: `planning_preference`, `emergency_cash_cents`, `debt_burden`, `savings_capacity`, and a fixed subset of `financial_state` fields. It has no names, profile or debt IDs, provenance text, or bank identifiers. A test in `test_state.py` checks this. Nothing needs to be withheld.

### Engine freeze during generation: agreed

B will not change the engine, assumptions, or versions between C generating `decisions.json` and the final export without telling C first.

## Still needed from Developer A (Neil)

1. **Update the spec text.** `BACKEND.md` §9 (line 555) and `BACKEND_TEAM_SPLIT.md` (lines 10 and 49) still say only the Morgan variant may use a non-default order. They should say the AI may choose any documented order, with the preference default as the fallback. B can make this edit if A agrees.
2. **Send C the Gemini API key** privately, so C can generate `decisions.json`.
3. **Answer C's saved-explanation question** (`proposals/README.md`, item 2).
4. **Generate `contracts/openapi.json` and `contracts/examples/`.** They still do not exist, and iOS needs real API output to check Swift decoding.
5. **Pick one pytest version with B.** `requirements.txt` pins `9.1.1` and `requirements-test.txt` pins `8.4.2`. B suggests keeping `9.1.1` and deleting the other pin, since the API tests already use it.

## Still needed from Developer C (Eric)

1. **Send `backend/fixtures/decisions.json` as soon as it is generated.** B will review every record's order, evidence paths, rationale, tradeoffs, and constraint checks, then add `"B"` to `reviewers`.
2. **Send the generated bundle (ten evaluations, `profiles.json`, `manifest.json`) before the final export.** B will audit it:
   - The first Adaptive month matches `allocate_month` and `build_plan`.
   - Debt interest is accrued once, and final debt payments release cash once.
   - Caps and matching use actual contributions.
   - Every feasible month conserves cash.
   - Morgan's opening month shows the $963.80 extra card payment.
   - All ten artifacts regenerate byte-identically with correct hashes.
3. **Tell B before changing how the simulation calls `allocate_month`**, so B can check the effect on the monthly cash identity.

## Order of events

1. A sends C the key and answers the saved-explanation question. B's answers above are final.
2. C generates `decisions.json` and sends it to A and B.
3. A and B review and add their marks. B audits the placeholder bundle.
4. C exports the final bundle twice, compares bytes, and commits it.
5. B signs off on the outage path: rules and template labels stay honest, and the saved demo works with the backend stopped.

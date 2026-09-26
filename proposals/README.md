# Integration proposals from Developer C (Eric)

For Neil (A) and Kevin (B). These are proposals only. Nothing in your files was
changed on any branch; C's code on `Eric` works with `main` as is.

Status of `Eric` (merged with `main` at `5cec6b6`): 265 of 267 tests pass. The
two failures in `test_ai_pipeline.py` also fail on `main`; they are item 3 below.

## For Neil (A)

### 1. Real engine in the API (done)

Main already took the evidence-key, profile-file and prompt-privacy parts of
the earlier patch. The remaining piece is now on `Eric`: `engine_port.evaluate`
calls C's `app.engine.evaluate`, so live evaluations return real projections
and C's canonical `input_hash`, and an unaffordable custom scenario returns 422
`INFEASIBLE_SCENARIO`. `engine_stub.py` is deleted. Please review that change.

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

Neil's `engine_port.permitted_orders` follows the written spec and lists only
the default order in the live prompt, and his tests expect other orders to be
rejected. Your validator accepts them, so two tests in `test_ai_pipeline.py`
fail on `main`. Please decide which rule is right; if it is the spec, the check
belongs in `policy.validate_decision`.

### 4. Evidence the model sees

The Recommendation prompt contains exactly your flattened
`recommendation_context`, the same values your validator accepts as evidence.
Please confirm nothing there should be withheld from the model.

### 5. Test dependency pins

`backend/requirements.txt` pins `pytest==9.1.1`, and
`backend/requirements-test.txt` pins `pytest==8.4.2`. Installing both gives
whichever comes last. Please agree on one version with Neil.

## What C needs back

- Neil: review item 1, accept or change item 2, and send the Gemini API key.
- Kevin: decide item 3 and confirm item 4.
- Both: review `backend/fixtures/decisions.json` once C generates it. Neil
  checks model/prompt provenance and structure; Kevin checks orders,
  rationale, and constraint checks. Mark each record by setting `reviewers` to
  `["A", "B"]`. The exporter refuses anything without both marks.

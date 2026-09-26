# What Neil (Developer A) needs from Kevin (B) and Eric (C)

Tested on `Neil` after merging `main` at `5034673` (2026-09-26): all **309 backend tests
pass**, the live API runs on B's engine and C's evaluator, and `scripts/smoke.py` passes
through a Cloudflare tunnel. Each item below lists the check that found it.

## Needs

| # | Who | What | Why | Found by |
|---|---|---|---|---|
| 1 | **Eric** | **Generate with prompt version 2 (now on `Neil`), not version 1.** The version is now set in code (`app/ai/prompts.PROMPT_VERSION`), so delete `AI_PROMPT_VERSION` from your `.env`. | Version 1 listed the preference default as "the policy default", so Gemini always picked it and the Morgan cash-security record failed 3/3. Version 2 asks the model to weigh high-interest debt against the preference. Records made with version 1 carry the wrong provenance and hashes. | Before: `prepare_decisions` failed 3/3 on that record. After: every run that reached the decision step gave starter → debt → full for the variant and the default for the other three; 0 of 18 explanations rejected. |
| 1b | **Eric** | **In `prepare_decisions`, wait `exc.retry_after_s` seconds after an `AIRateLimited` error before the next attempt.** | The free Gemini tier ran out after about 60 calls in a few minutes. Your script retries immediately, so every attempt hits the same limit and the run fails. `GeminiModel.generate` now raises `AIRateLimited` with Gemini's suggested wait. | Two back-to-back runs failed with *"model call failed: AIRateLimited"* on every attempt. |
| 2 | **Eric** | **Don't wait for my API key.** Either get your own free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), or I run `prepare_decisions` on my laptop and send you the file for review. | A shared key ends up in chat logs and other machines. Your script already runs unchanged on my side. | Same run: the script works with my `.env` (about 47s). |
| 3 | **Eric** | **Keep importing only these A names**: `valid_prose`, `situation_flags` (`app/ai/pipeline.py`), `SYSTEM`, `ExplanationOut`, `explanation_prompt`, `recommendation_prompt`, `recommendation_schema`, `PROMPT_VERSION` (`app/ai/prompts.py`), `evidence_paths`, `GeminiModel`, `AIRateLimited`, `load_settings`. Tell me before relying on anything else. | Answer to your proposal item 2: yes, reuse `AIExplanation` + `valid_prose` for saved explanations. `tests/test_public_interface.py` now guards these names and signatures, so a rename fails loudly instead of breaking your exporter. | Searched `export_demo.py` and `prepare_decisions.py` for imports from `app.ai`, `app.schemas` and `app.engine_port`. |
| 4 | **Kevin** | **Update the three spec lines to the new order rule**: `BACKEND.md` line 555 and `BACKEND_TEAM_SPLIT.md` lines 10 and 49. | The code (your "update 2", merged in #6) allows any documented order for any profile, but the spec still says only the Morgan variant may. Eric's saved-decision checks and my prompt both read the spec. | Searched both files: the old wording is still there. |
| 5 | **Kevin** | **Agree on one pytest version**: I propose `requirements.txt` runtime-only, and `requirements-test.txt` with `pytest==9.1.1` + `httpx`. | `requirements.txt` pins `pytest==9.1.1` and `requirements-test.txt` pins `8.4.2`; installing one replaces the other. The full suite passes on 9.1.1. | Searched both files for `pytest`; ran the suite. |
| 6 | **Kevin** | **Confirm the model may see everything in `recommendation_context`**, and tell me before changing its keys or `validate_decision`'s fallback codes. | My prompt sends that context, flattened, as the only allowed evidence keys (enforced in the response schema). The API passes `NO_AI_PROPOSAL` → `TIMEOUT` / `RATE_LIMITED` / `AI_COOLDOWN` / `PROVIDER_ERROR` to the app. | `test_prompt_lists_engine_evidence_keys`, `test_numeric_rationale_is_rejected_by_engine` |

## Already done for your requests

| Request | Status |
|---|---|
| B: connect the real engine, use `recommendation_context` evidence keys, `model_id` as keyword, upper-case fallback codes | Done; live proposals are accepted by your validator |
| B: `ProfileValidationError` → `422 INVALID_PROFILE`; infeasible custom → `422 INFEASIBLE_SCENARIO` | Done (C's evaluator raises it; the API maps it) |
| B/C: `contracts/openapi.json` + `examples/` from real output | Done: `scripts/export_contracts.py`; `test_contracts.py` fails if stale |
| C: review `engine_port.evaluate` wiring (proposal item 1) | Reviewed and merged. Latency is 27–191 ms per evaluation, inside the 250 ms target |
| C: saved-explanation check (proposal item 2) | Accepted; see item 3 above |

## Order of events

1. **Neil:** prompt version 2, done on `Neil`. **Kevin:** items 4–6. **Eric:** item 1b.
2. **Eric:** runs `prepare_decisions` with prompt version 2 (items 1 and 2), then sends `decisions.json` to Neil and Kevin.
3. **Neil and Kevin:** review it (Neil: provenance and structure; Kevin: orders and rationale), then set `"reviewers": ["A", "B"]`.
4. **Eric:** exports the final bundle, and the frontend developer copies it into `Resources/Demo/`.

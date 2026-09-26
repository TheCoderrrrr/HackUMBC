# What Eric (Developer C) needs from the team

Eric builds the offline demo bundle: ten saved evaluations plus `profiles.json`
and `manifest.json`, which the iPhone app uses when the server or AI is down.
Updated after `main` `4b041ce` (Neil's prompt v2, Kevin's PR #8). All 316
backend tests pass on branch `Eric`.

## Done for your requests

| Request | Status |
|---|---|
| Neil 1: generate with prompt version 2 | `prepare_decisions` records `PROMPT_VERSION` from `app/ai/prompts.py` and sends the same prompt as the live API (all three documented orders, default first). |
| Neil 1b: wait after `AIRateLimited` | It waits `retry_after_s` (30 s if Gemini gives none, at most 120 s) before the next attempt. |
| Neil 2: don't wait for your key | Eric will use his own key from aistudio.google.com/apikey. |
| Neil 3: only your guarded imports | `prepare_decisions` imports only your listed names. Three names C relies on are not guarded yet; see Neil item 1 below. |
| Kevin 1 & 2: send `decisions.json` and the bundle before final export | New `python -m scripts.export_demo --draft` writes an unreviewed bundle to the git-ignored `fixtures/draft/` so Kevin can audit before anyone signs off. The final export still requires both review marks. |
| Kevin 3: tell B before changing how the simulation calls `allocate_month` | Agreed. Nothing in this update changes it. |
| Kevin's order rule | The prompt offers all three orders. The saved standard decisions still keep the preference default so Morgan's $963.80 demo arithmetic holds (BACKEND.md section 12). Only the Morgan variant saves starter -> debt -> full. |

## Neil (Developer A)

| # | What | Why |
|---|---|---|
| 1 | **Add three names to your guarded list:** `app.schemas.Evaluation`, `app.engine_port.permitted_orders`, and `app.ai.pipeline.explanation_facts`. | C's evaluator and exporter already validate with `Evaluation`. C's test compares its order list with `permitted_orders`. `prepare_decisions` keeps a copy of `explanation_facts` for now; once it's guarded, C imports it directly so saved prompts stay identical to live ones. |
| 2 | **Review `backend/fixtures/decisions.json`** when Eric sends it: model and prompt provenance and output structure. Add `"A"` to each record's `reviewers`. | The final export refuses records without both marks. |
| 3 | **Consider switching providers** (see the model recommendation below). Decide before Eric generates, because `model_id` is part of every saved hash. | The Gemini free tier rate-limits generation and the live demo. |

## Kevin (Developer B)

| # | What | Why |
|---|---|---|
| 1 | **Audit `fixtures/draft/`** when Eric sends it: your checklist from `DEVELOPER_B_REQUESTS.md` (first Adaptive month, interest once, caps, cash conservation, $963.80, byte-identical regeneration). | Problems found now avoid a second review round. |
| 2 | **Review `backend/fixtures/decisions.json`**: orders, evidence paths, rationale, tradeoffs, constraint checks. Add `"B"` to each record's `reviewers`. | The final export refuses records without both marks. |

## Frontend developer

| # | What | When |
|---|---|---|
| 1 | **Build Swift decoding against `fixtures/draft/`**. The file structure is final; only the AI text changes after review. Don't ship it. | As soon as Eric sends it |
| 2 | **Add the final twelve files to `Resources/Demo/`** and check decoding, offline launch, saved-AI labels, and corrupt-file handling (`FRONTEND.md` section 7). | After the reviewed export |

## Order of events

1. Neil decides on the provider (item 3). Eric gets a key.
2. Eric runs `prepare_decisions` and `export_demo --draft`, then sends
   `decisions.json` to Neil and Kevin and the draft to Kevin and the frontend.
3. Kevin audits the draft. Neil and Kevin review `decisions.json` and add their marks.
4. Eric exports the final bundle twice, compares bytes, commits it, and hands
   it to the frontend developer.

## Model recommendation (for Neil, who owns the model client)

BACKEND.md section 3 names the Anthropic or OpenAI SDK for the two agent calls;
Gemini was chosen later. Both alternatives return JSON-schema structured output,
which your evidence-key enum needs, and paid keys avoid free-tier rate limits.

| Use | Model | Why |
|---|---|---|
| Live API (4-second budget) | **Claude Haiku 4.5** (`claude-haiku-4-5-20251001`) | Fast and low-cost; structured output via JSON schema. |
| Saved decisions (no deadline, reviewed) | **Claude Sonnet 5** (`claude-sonnet-5`) | Stronger reasoning for the Morgan variant's debt-versus-cash tradeoff. Saved content is labeled saved, so it may use a different model from live. |
| OpenAI alternative | A current "mini" model with Structured Outputs (strict JSON schema) | Pin the exact model ID at setup, as BACKEND.md section 15 requires. |

Switching means a new client that implements `StructuredModel.generate` and
raises `AITimeout`/`AIRateLimited` like `GeminiModel`. Both need a paid API key.
Switch before Eric generates: the model ID is recorded in every saved decision
and input hash, so switching afterwards means regenerating and re-reviewing.

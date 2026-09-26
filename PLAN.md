# Adaptive Retirement — AI-Assisted Cash Priorities

HackUMBC 2026 · 24-hour build · SwiftUI iPhone app + Python backend

This is the current product and team plan. It replaces the earlier Next.js/LangGraph/SSE proposal. [FRONTEND.md](FRONTEND.md) specifies the iOS implementation; [BACKEND.md](BACKEND.md) specifies the API, financial engine, AI boundaries, fixtures, and acceptance checks. Keep all three documents synchronized; implemented Pydantic/OpenAPI schemas become the API source of truth.

## Product and pitch

**Same retirement date. Different financial lives.**

Explain how retirement contributions, debt repayment, and emergency savings compete for the same available cash. Retain an illustrative target-date stock/bond allocation. AI helps choose the order of permitted cash priorities and explain the tradeoffs; Python calculates every indicator, contribution, payment, and projection.

The product answers:

1. What retirement contribution fits this customer's cash flow?
2. Where should their next available dollar go?
3. Why was this priority chosen, and why did it change?
4. What happens to retirement assets, cash, and debt over time?

No readiness score, success probability, personalized portfolio allocation, trading, or claimed retirement adequacy. This is an educational prototype, not an official T. Rowe Price product.

## Fictional customer demo

Morgan is a hypothetical T. Rowe Price customer invented for this demo. Every account, preference, and personal detail is synthetic. Jordan and Casey are fictional comparison profiles; no real customer data is needed.

Display: **Fictional customer • Synthetic data • Not affiliated with or endorsed by T. Rowe Price.**

| Profile | Situation | Demo purpose |
|---|---|---|
| Jordan, 35, retiring at 67 | Strong reserves, full match, low-rate student debt | Maintain contributions |
| Morgan, 35, retiring at 67 | One month of reserves and $18,000 of credit-card debt at 25% APR | Preserve matching and choose savings/debt priorities |
| Casey, 58, retiring at 65 | Strong reserves, no debt, shorter horizon | Show a different retirement horizon without claiming adequacy |

Use the exact amounts in BACKEND.md. Jordan and Morgan retain the same initial 90% illustrative equity allocation. Morgan's pinned balanced decision produces $963.80 in extra opening-month debt repayment. Label this as the result of that decision, not the guaranteed output of every AI choice.

For demonstrating priority-ordering authority, prepare a reviewed alternative Morgan decision with an explicit cash-security preference. Show its choice to build a full reserve before extra card payments, along with the cost of delaying debt repayment. This optional comparison uses a separate fixture variant and exported evaluation; keep the required nine presets unchanged. Do not depend on a live model selecting a particular answer on stage. Clearly distinguish saved AI decisions from live AI calls and rules fallback.

## AI responsibilities

A small sequential backend pipeline is sufficient; no agent framework or streaming protocol is required.

### Financial State Agent

Receives the canonical normalized profile and Python-computed indicators: liquidity, debt burden, savings capacity, and horizon. It identifies competing needs and summarizes the state. It does not calculate or overwrite indicators. Readiness remains out of scope until a defensible target is defined.

Plaid is optional input ingestion. Synthetic fixtures go through the same normalization and financial engine. Never send names, account identifiers, credentials, or raw Plaid responses to the model.

### Recommendation Agent

Proposes a priority ordering over exactly:

- Starter reserve.
- Extra high-interest debt repayment.
- Full emergency reserve.

The order must contain each priority once, with starter reserve before full reserve. The agent may weigh an explicit `balanced`, `cash_security`, or `debt_reduction` preference against the computed state. This authority changes the allocation of available cash; it is not merely a narrative wrapper.

Python retains authority over essential expenses, debt minimums, critical liquidity, affordable employer matching, contribution caps, debt avalanche ordering, targets, and all exact amounts. Additional retirement saving and residual cash follow the chosen discretionary priorities. The model cannot change investment allocation or simulation assumptions.

Validate every proposal. Invalid or unavailable AI uses the documented deterministic waterfall. An explicit custom contribution remains a user-selected scenario, not an AI-controlled election.

### Explanation Agent

Receives the validated decision, calculated results, and Python-computed differences from the prior decision. Generates a brief “why this plan / why it changed” narrative using supplied evidence. Use deterministic templates when generation fails or references unsupported facts.

### Structured reasoning trace

Store a concise `DecisionSummary` with:

- Decision ID and AI/rules origin.
- Model ID and prompt version.
- Applied priority ordering.
- Evidence-linked rationale and tradeoffs.
- Python-generated constraint-check results.
- Fallback reason, when applicable.

This is a decision record, not private chain-of-thought or a raw model transcript. Store it in the evaluation and saved artifacts. Keep live prior-decision snapshots in a bounded, two-hour in-memory cache for same-profile comparisons; no database is required. Expired IDs fall back to an initial-plan explanation.

## Financial engine and projections

One Python engine powers live responses and offline artifacts. Use integer cents, Decimal cash accounting, explicit employer-match tiers, contribution tax-cost estimates, and a shared cash budget. Show cash, debt, and retirement assets separately.

Current preserves the original contribution election and minimum debt payments. Adaptive applies the validated priority order. Custom changes retirement age and optionally fixes the contribution rate. Adaptive and Custom share one decision ordering within an evaluation. Recalculate amounts monthly without additional agent calls.

For MVP, use deterministic monthly compound-growth projections and debt amortization with disclosed assumptions. Monte Carlo is optional stretch only after MVP and AI acceptance pass, before feature freeze. Any simulation remains Python math; no numeric projection comes from an LLM. Do not present percentiles as success probabilities.

The same inputs, assumptions, and validated decision must reproduce the same numerical outputs. Live model choices can vary, so pin reviewed decisions for the demo and artifact generation.

## Architecture and user experience

- **iOS:** SwiftUI, Swift Charts, URLSession, iOS 17+. Welcome → Overview / Plan / Explore tabs. Physical-device installation is an hour-one gate.
- **Backend:** Python 3.12, FastAPI, Pydantic, pytest, small structured-output AI pipeline, configurable pinned model. Keys stay server-side.
- **Networking:** backend Mac through a temporary HTTPS tunnel; configurable server URL on the phone.
- **API:** `/health`, `/v1/demo-profiles`, `/v1/evaluate`; optional `/v1/plaid/*`. No run-ID/SSE architecture.
- **Offline:** three profiles × three required presets, generated from the same evaluator using committed validated decisions. No live model calls during export.
- **UI provenance:** distinguish live/saved calculations and AI-assisted/rules-fallback decisions. Why sheets show rationale, facts, tradeoffs, and checks.
- **Plaid:** Sandbox stretch after the hour-12 MVP; not the opening demo dependency.

Keep the full AI pipeline within four seconds and the iOS timeout at eight seconds. On missing credentials, outage, deadline exhaustion, or invalid proposals, return rules-backed results with honest labels. An explanation-only failure retains the valid recommendation and uses templates. Offline custom calculations remain disabled; saved presets continue to work.

## Team ownership

| Developer | Responsibility |
|---|---|
| 1 | SwiftUI screens, charts, accessibility, Why-sheet presentation |
| 2 | Xcode/signing, models, state, networking, offline bundles, optional LinkKit |
| 3 | API/OpenAPI, model orchestration, structured outputs, decision cache, tunnel, optional Plaid |
| 4 | Indicators, permitted priorities, validation, cash allocation, projections, fixtures, templates, exporter |

Developer 3 owns schemas; Developer 4 owns financial semantics. Contract changes require matching examples and successful Swift decoding. Use small reviewed branches, frequent integration, and buildable main.

## 24-hour execution plan

| Hours | Deliverable |
|---|---|
| 0–1 | Physical iPhone install, backend/tunnel, fictional fixtures |
| 1–2 | Freeze schemas, decision contract, constraints, and examples |
| 2–4 | Real evaluation on phone and matching offline artifact; cut Plaid if this gate fails |
| 4–7 | Cash allocator, indicators, AI stages, structured decision summaries, core screens |
| 7–10 | Projections, scenarios, validated alternative ordering, explanations, outage handling |
| 10–12 | Nine presets and live/offline integration; MVP gate includes AI validation and fallback |
| 12–15 | Optional Plaid or seeded Monte Carlo only if core gates pass; cut incomplete Plaid at 15 |
| 15–18 | Reliability, accessibility, financial audit; feature freeze at 18 |
| 18–20 | Final tests, pinned decisions, artifacts, dependencies |
| 20–22 | Live/offline rehearsals and recording |
| 22–24 | Final build, backups, submission, blocking fixes only |

## Acceptance and demo

Required checks include cash conservation, matching and caps, no allocation changes from debt, valid alternative ordering that materially changes payments, rejection of malformed priorities, provider-outage fallback, evidence-grounded explanations, deterministic saved-decision replay, same-profile prior-decision comparisons, and all nine artifacts decoding on the phone. Verify the four-second AI budget and eight-second client deadline with the chosen provider.

Three-minute story: introduce the fictional customers; show Jordan maintaining contributions; show Morgan's competing needs and AI-selected priorities; open the structured explanation; compare debt/cash/retirement outcomes; try a saved retirement-age scenario. Explain that AI chooses among constrained priorities while Python validates and calculates the plan. Show the optional cash-security variant or working Plaid connection afterward if time permits.

The demo must cold-launch offline, switch profiles, show saved AI decisions, and run every preset with the backend stopped. Rehearse a live AI-provider failure separately to prove the rules fallback. Keep a recorded walkthrough and powered phone/backend backups.

These documents specify intended behavior; they do not claim the application or financial model has already been implemented or validated.

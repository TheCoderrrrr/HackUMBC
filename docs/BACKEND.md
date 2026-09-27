# Adaptive Retirement Management (ARM) — Backend and Financial Engine Handoff

**Audience:** Developers 3 and 4.  
**Build window:** 24 hours.  
**Companion:** [FRONTEND.md](FRONTEND.md).  
**Status:** Implementation specification; creating this document does not implement or validate the application.

## 1. Purpose and architecture

Build one Python service with bounded AI priority selection and a deterministic financial engine that converts a normalized profile into an affordable contribution/cash-priority plan, explanations, and monthly projections.

~~~text
Synthetic fixtures or Plaid Sandbox + confirmed inputs
  -> canonical financial profile
  -> calculated financial state
  -> Recommendation Agent (1: use computed indicators; propose bounded order, rationale, tradeoffs)
  -> Python validation and cash allocator
  -> deterministic monthly simulation
  -> Explanation Agent (2: explain validated decisions and changes)
  -> structured evaluation
  -> live SwiftUI response or bundled offline artifact
~~~

Use Python 3.12, FastAPI, Pydantic, Uvicorn, and pytest. Add the Plaid SDK only for the stretch integration. NumPy, pandas, SciPy, databases, Docker, Redis, and microservices are unnecessary.

Run on a designated teammate's Mac through a temporary HTTPS tunnel. No paid instance is required.

AI selects a bounded priority order; Python validates it and computes every monetary amount. No trading or portfolio optimization. Preserve an illustrative target-date allocation while personalizing contributions and cash priorities.

T. Rowe Price already researches target-date personalization. The prototype contributes the explainable implementation and participant experience. [T. Rowe Price research](https://www.troweprice.com/institutional/us/en/insights/articles/2024/q3/make-it-personal-the-next-chapter-for-target-date-solutions-na.html)

## 2. Scope and critical corrections

Supported:

- One employed adult, one employer plan, USD, pre-retirement accumulation.
- Traditional or Roth employee contributions.
- Confirmed, fully vested, per-pay-period matching formula.
- Fixed-APR debts with user-confirmed minimum payments.
- Steady-state cash budget and explicitly modeled annual growth.

Excluded: vesting schedules, true-ups, multiple plans, variable-rate debt, forgiveness programs, early withdrawals, retirement drawdown, withdrawal taxes, and tax optimization.

Requirements:

- Employer contribution percentage and employee full-match threshold are different fields.
- Gross salary is not spendable income.
- Essentials and required debt payments precede discretionary allocations.
- Critical liquidity can override matching; disclose the tradeoff.
- Contributions, extra debt, and savings share one budget.
- Debt does not directly alter allocation.
- Missing values are not zero.
- Cash, debt, and retirement assets remain separately visible.
- Insufficient assets do not trigger more investment risk.
- No readiness/probability number without a defined target and credible model; neither is in scope.

## 3. Repository and internal architecture

~~~text
backend/
  app/
    main.py
    schemas.py
    api.py
    engine/
      state.py
      policy.py
      simulation.py
      assumptions.py
    integrations/
      plaid.py
  fixtures/profiles.json
  scripts/export_demo.py
  tests/
  requirements.txt
  .env.example

contracts/
  openapi.json
  examples/
~~~

Pure functions:

~~~text
derive_state(profile) -> FinancialState
validate_decision(profile, state, proposal) -> DecisionSummary
build_plan(profile, state, decision) -> Plan
simulate(profile, strategy, scenario, assumptions, decision) -> Projection
evaluate(profile, scenario, validated_decision) -> Evaluation
~~~

AI orchestration runs before the pure evaluator. API and exporter call the same evaluator with a validated decision. The exporter reads committed decision fixtures; it never makes live model calls. Routers and the Plaid adapter contain no financial policy. Swift does not duplicate the engine.

Use the raw Anthropic or OpenAI Python SDK for the two fixed, single-shot agent calls, with Pydantic models for `DecisionSummary` and `AIExplanation`. Instructor may wrap the SDK for schema validation and retry-on-failure during fixture preparation; the interactive path has no automatic retries. Do not add LangChain, CrewAI, AutoGen, LangGraph, or another autonomous-agent orchestration framework. The two calls do not loop and share one hard total timeout.

`POST /v1/evaluate` remains one synchronous request returning one `Evaluation` with both `decision_summary` and `explanation`. Do not split explanation into a second endpoint, polling, or streaming; `PlanViewModel` loads the evaluation in one call.

Use Decimal and ROUND_HALF_UP for cash/debt accounting. Return integer cents. Floating-point compound return factors are acceptable, rounded to cents monthly. Allocate any final cent residual to cash so money is conserved.

Use synchronous FastAPI handlers for synchronous SDK/engine work. One Uvicorn worker supports the in-memory token design.

## 4. Shared API contract

Keep synchronized with FRONTEND.md. Developer 3 owns Pydantic/OpenAPI; Developer 4 owns financial semantics.

### Conventions

- Prefix /v1 except /health.
- Schema "1"; initial model and policy "1.0.0".
- Money: integer USD cents.
- Rates: JSON numbers; 0.05 means 5%.
- Dates YYYY-MM-DD; timestamps UTC ISO 8601.
- Month 0 starting snapshot, month 1 first month-end.
- Null milestone means not reached within the horizon.
- No NaN or Infinity.

### Endpoints

~~~text
GET /health
  -> { status: "ok", schema_version, model_version,
       policy_version, plaid_enabled }

GET /v1/demo-profiles
  -> { schema_version, profiles: FinancialProfile[] }

POST /v1/evaluate
  <- { profile: FinancialProfile,
       scenario: null | {
         retirement_age: integer,
         employee_contribution_rate: number | null
       } }
  -> Evaluation

POST /v1/plaid/link-token                     [stretch]
  <- {}
  -> { link_token, expiration }

POST /v1/plaid/exchange                       [stretch]
  <- { public_token }
  -> { session_token, expires_at }

POST /v1/plaid/import                         [stretch]
  Authorization: Bearer <session_token>
  <- {}
  -> { status: "complete" | "partial", draft_profile,
       missing_fields: string[], warnings: string[] }
~~~

Disabled Plaid routes return 503 PLAID_DISABLED. No individual-profile endpoint or separate simulation endpoint is necessary.

### FinancialProfile

~~~text
schema_version: "1"
id: string
name: string
as_of_date: date
currency: "USD"
source: "demo" | "plaid_sandbox"
age: integer
retirement_age: integer
annual_gross_salary_cents: integer
monthly_take_home_cents: integer
monthly_living_expenses_cents: integer
employee_contribution_rate: number
contribution_tax_treatment: "traditional" | "roth"
estimated_marginal_income_tax_rate: number
annual_employee_limit_cents: integer
retirement_balance_cents: integer
emergency_cash_cents: integer
employer_match:
  status: "confirmed" | "none" | "unknown"
  fully_vested: boolean
  tiers:
    - employee_rate_from: number
      employee_rate_to: number
      match_per_employee_dollar: number
debts:
  - id: string
    type: "credit_card" | "student_loan" | "other"
    balance_cents: integer
    apr: number
    minimum_payment_cents: integer
provenance:
  <field_path>:
    source: "fixture" | "plaid_sandbox" | "user_confirmed"
    as_of_date: date
~~~

Definitions:

- Take-home is after the current retirement deduction and other payroll deductions.
- Living expenses exclude debt payments, retirement contributions, and savings transfers.
- Emergency cash excludes earmarked imminent bills. It is the only initial cash asset modeled.
- Retirement balance contains confirmed retirement assets.
- Debt minimum is an entered obligation, not a guessed percentage.
- Draft imports permit nulls; canonical required monetary inputs do not.

### FinancialState

~~~text
months_until_retirement: integer
gross_monthly_salary_cents: integer
current_employee_contribution_cents: integer
current_employee_cash_cost_cents: integer
monthly_resources_before_retirement_cents: integer
monthly_required_debt_payments_cents: integer
monthly_allocatable_budget_cents: integer
current_monthly_surplus_cents: integer
emergency_months: number
critical_reserve_target_cents: integer
starter_reserve_target_cents: integer
full_reserve_target_cents: integer
employee_rate_for_full_match: number | null
current_monthly_employer_match_cents: integer | null
maximum_monthly_employer_match_cents: integer | null
match_capture_fraction: number | null
high_interest_debt_cents: integer
highest_debt_apr: number | null
baseline_equity_weight: number
warnings: string[]
~~~

### Evaluation, actions, and reasons

~~~text
Evaluation
  schema_version: string
  model_version: string
  policy_version: string
  profile_id: string
  input_hash: string
  financial_state: FinancialState
  plan:
    primary_action_id: string
    actions: RecommendationAction[]
    reasons: Reason[]
  assumptions: ModelAssumptions
  projections:
    current: Projection
    adaptive: Projection
    custom: Projection | null
  warnings: string[]

RecommendationAction
  id: string
  rank: integer
  category: "cash_flow" | "contribution" | "emergency" | "debt" | "allocation"
  status: "action" | "maintain" | "blocked" | "information"
  monthly_cash_cost_cents: integer
  employee_contribution_cents: integer | null
  employee_contribution_rate: number | null
  debt_id: string | null
  target_balance_cents: integer | null
  reason_codes: string[]

Reason
  code: string
  template_key: string
  facts: dictionary<string, string | number | boolean | null>
  input_paths: string[]
~~~

### AI decision and explanation contract

~~~text
DecisionSummary
  decision_id: string
  source: "ai" | "rules_fallback"
  model_id: string | null
  prompt_version: string
  ordered_priorities: ("starter_reserve" | "high_apr_debt" | "full_reserve")[]
  rationale:
    - priority: string
      summary: string
      evidence_paths: string[]
      tradeoff: string
  constraint_checks:
    - code: string
      passed: boolean
  fallback_reason: string | null

AIExplanation
  state_summary: string
  narrative: string
  source: "ai" | "template"
  changes:
    - field_path: string
      before: string | number | boolean | null
      after: string | number | boolean | null
~~~

Evaluation additionally contains decision_summary: DecisionSummary and explanation: AIExplanation. The structured decision summary is the stored reasoning trace: a concise decision record, not private chain-of-thought. Constraint checks and changes are computed by Python, never asserted by the LLM.

FinancialProfile additionally accepts planning_preference: "balanced" | "cash_security" | "debt_reduction", default "balanced". This is an explicit customer input, not an inferred personality trait. Fixture provenance covers this field.

The evaluate request additionally accepts previous_decision_id: string | null (default null). The backend keeps a bounded (128 entries), two-hour in-memory map of prior validated decisions and their state/action snapshots. Use cryptographically random opaque decision IDs; only possession of the ID and a matching profile ID permits comparison. Store each snapshot's profile hash, but allow financial inputs and preferences to change for that same profile so the explanation can describe those changes. Never look up prior snapshots by profile ID alone; an expired or unknown ID yields an initial-plan explanation with a warning. Bundled IDs need not exist on the live server. No database or raw model transcript is required. Previous decisions supply explanation context only, not authority over the next plan.

### Projection and assumptions

~~~text
Projection
  strategy: "current" | "adaptive" | "custom"
  retirement_age: integer
  feasible: boolean
  shortfall_cents: integer | null
  retirement_balance_nominal_cents: integer | null
  retirement_balance_today_cents: integer | null
  cash_nominal_cents: integer | null
  debt_nominal_cents: integer | null
  cumulative_debt_interest_cents: integer | null
  debt_free_month: integer | null
  starter_reserve_month: integer | null
  full_reserve_month: integer | null
  points:
    - month: integer
      retirement_balance_cents: integer
      cash_cents: integer
      debt_cents: integer

ModelAssumptions
  annual_equity_return: number
  annual_bond_return: number
  annual_cash_return: number
  annual_inflation: number
  annual_salary_growth: number
  annual_living_cost_growth: number
  annual_employee_limit_growth: number
  high_interest_apr_threshold: number
  retirement_total_saving_target: number
  critical_reserve_cap_cents: integer
  starter_reserve_months: number
  full_reserve_months: number
  returns_net_of_fees: boolean
  glide_path:
    - years_to_retirement: number
      equity_weight: number
  limitations: string[]
~~~

Current and Adaptive use the profile's original age. Custom uses the scenario retirement age. A null contribution override applies adaptive policy at that age; an explicit rate fixes the election. Strategy remains custom in both cases.

### Error envelope

~~~json
{
  "error": {
    "code": "INVALID_PROFILE",
    "message": "Confirm the minimum payment for this debt.",
    "field_paths": ["debts.0.minimum_payment_cents"],
    "retryable": false
  }
}
~~~

Use 422 for invalid/infeasible scenarios, 401 for invalid/expired sessions, 429 for rate limits, 503 for unavailable integration, and sanitized 500 for unexpected failures. A valid base profile with cash shortfall returns HTTP 200 and a blocked plan.

Normalize Pydantic errors into the envelope. [FastAPI error handling](https://fastapi.tiangolo.com/tutorial/handling-errors/)

## 5. Validation and unsupported cases

- Age 18–75; retirement age greater than age and no more than 80.
- Salary/living expenses positive; other amounts nonnegative.
- Contribution rates [0,1]; estimated marginal tax rate [0,0.5].
- APR [0,1]; higher rates require explicitly extending the supported scope.
- At most 20 debts, unique IDs, confirmed positive minimums for positive balances.
- Match tiers start at zero, are contiguous, ordered, nonoverlapping, and have positive multipliers no greater than 2.0.
- At most eight tiers; none/unknown use empty tiers.
- No-match values are zero, but capture fraction is null.
- Unknown or non-fully-vested matching returns a blocked assessment, not invented matching.
- Cap request body at 128 KiB.
- Validate the original annualized employee election against the supported cap. Do not silently change the contribution used to reconstruct current take-home.
- Reject non-USD imports.
- Required null fields cannot enter the numerical engine.

Blocked projections have feasible=false, null terminal amounts, and empty points; custom remains null if no scenario was submitted. Missing matching uses MISSING_REQUIRED_INPUT. Cash shortfalls use CASH_FLOW_SHORTFALL and a positive shortfall amount.

For 2026 fixtures, use a conservative $24,500 annual employee cap and exclude catch-up contributions. This is the regular 2026 limit, not the maximum for every older participant. [IRS 2026 limits](https://www.irs.gov/newsroom/401k-limit-increases-to-24500-for-2026-ira-limit-increases-to-7500)

This is an annualized planning cap. Do not claim to calculate remaining legal current-year room without year-to-date and other-plan information.

## 6. Derived state and cash arithmetic

Dollar notation below is for readability. Implementation uses cents and Decimal.

~~~text
S = annual gross salary / 12
c = current employee contribution rate

k = 1                                      for Roth
k = 1 - estimated marginal income-tax rate for traditional

current employee contribution = S * c
current employee cash cost = S * c * k

resources before retirement =
  current take-home + current employee cash cost

allocatable budget =
  resources before retirement
  - living expenses
  - required debt minimums

current monthly surplus =
  allocatable budget - current employee cash cost

emergency months = emergency cash / living expenses
~~~

Cap required debt payments at balance plus that month's interest. Do not reserve a full payment for an almost-paid-off debt.

The tax adjustment approximates a change in take-home while other deductions remain fixed. It does not model payroll taxes, brackets, filing, or withdrawal taxes. Include SIMPLIFIED_TAX_ESTIMATE for traditional contributions.

Months to retirement = 12 × (retirement age − age). Use integer starting ages and model anniversaries, not birthdays.

High-interest exposure sums positive balances with APR at least 10%. Highest debt APR is null when no positive debt exists. Weighted-average APR is unnecessary.

## 7. Employer matching

~~~text
match_rate(c) = sum over tiers:
  multiplier * max(0, min(c, tier_end) - tier_start)

monthly employer match = gross monthly salary * match_rate(c)
~~~

The full-match employee rate is the last positive tier's upper bound. Capture fraction is current matching divided by maximum matching.

Required example:

~~~text
100% on employee contributions from 0% through 3%
50% on employee contributions from 3% through 5%

Full match requires 5% employee contribution.
Maximum employer contribution is 4% of salary.
~~~

Match is calculated from the actual employee contribution after affordability and cap constraints.

Employer matching and high-interest debt are supported priorities, but this exact ordering is a disclosed prototype policy rather than a universal rule. [Investor.gov checklist](https://www.investor.gov/introduction-investing/general-resources/investor-preparedness-checklist)

## 8. Adaptive monthly waterfall

Recompute amounts monthly using one validated priority order for the whole evaluation. Plan-screen actions are the first month's output from the same allocator. The ordering below is the rules fallback; AI may reorder only Steps 3–5 under Section 9 constraints. Do not invoke agents inside the monthly loop.

### Step 0: Essential obligations

Reserve living expenses and required debt payments. If resources cannot cover them, return a shortfall. No invented borrowing, withdrawals, or assumed expense cuts. Suppress projections dependent on resolving the gap.

### Step 1: Critical reserve

Target min($1,000, one month of living expenses). Fund only the gap from existing cash before employee contributions.

This exception can temporarily sacrifice employer matching. Explain the consequence.

### Step 2: Employer match

Allocate contributions up to the full-match employee rate, limited by remaining cash and the employee cap. Participant cash cost equals contribution × k.

If only partial matching is affordable, return MATCH_PARTIALLY_AFFORDABLE.

### Step 3: Starter liquidity

Fund the gap to one month of current living expenses.

### Step 4: High-interest debt

Prototype threshold: APR >= 10%.

Allocate extras by descending APR, then ascending balance, then debt ID. Cap at amount due and continue to the next eligible debt. Preserve all minimum payments.

This threshold is a policy assumption, not an investment-return forecast.

### Step 5: Full liquidity

Fund the gap to three months of current living expenses. Three months is a disclosed default, not a claim of household-specific sufficiency.

### Step 6: Additional retirement contributions

Find the smallest employee rate c satisfying c + match_rate(c) >= 0.15. At this stage, desired rate is the greater of that solution and the original employee election.

Solve directly over match tiers or with deterministic bisection to a contribution-cent tolerance. Apply affordability and the monthly cap. Add only the increment beyond Step 2.

The 15% combined contribution target is a heuristic, not evidence of retirement adequacy. Earlier liquidity/debt stages may reduce a higher original election; this later stage restores or preserves it when affordable.

### Step 7: Residual cash

Retain leftover dollars as UNASSIGNED_SURPLUS. No brokerage or IRA optimization.

All modeled cash, including surplus, counts toward future reserve targets. Do not liquidate existing cash to accelerate debt; this policy allocates future cash flow only.

### Primary action

Keep all actions. Blocked issues, critical reserves, and an affordable increase to capture missing matching retain precedence. Thereafter select the first actionable priority in the validated order, followed by contribution increase or maintenance. The fallback order is:

1. Blocked essential-cash-flow or missing-input issue.
2. Critical reserve shortfall.
3. Affordable contribution increase when currently below full-match eligibility.
4. Starter reserve.
5. Extra high-interest debt.
6. Full reserve.
7. Retirement contribution increase.
8. Maintain contribution.

Morgan already captures matching under the original election, so extra debt repayment is the headline.

### Accounting invariant

~~~text
resources before retirement =
  living expenses
  + actual debt payments
  + employee contribution cash cost
  + cash added
~~~

Employer matching is an external retirement inflow, not a participant cash expense.

## 9. Explainability

Required reason codes:

~~~text
CASH_FLOW_SHORTFALL
CRITICAL_LIQUIDITY
CAPTURE_EMPLOYER_MATCH
MATCH_PARTIALLY_AFFORDABLE
BUILD_STARTER_RESERVE
HIGH_APR_DEBT
BUILD_FULL_RESERVE
INCREASE_RETIREMENT_SAVING
MAINTAIN_CONTRIBUTION
UNASSIGNED_SURPLUS
BASELINE_ALLOCATION_RETAINED
MISSING_REQUIRED_INPUT
SIMPLIFIED_TAX_ESTIMATE
~~~

Template keys are lowercase reason codes. Facts contain all interpolation values, using _cents and _rate suffixes. Input paths reference canonical fields.

For HIGH_APR_DEBT include debt ID, balance, APR, minimum, extra, and total payment. Match reasons separately include employee contribution, employer contribution, and required employee rate.

No explanation introduces claims absent from the structured output. Allocation text says the curve is illustrative and no personal portfolio optimization was performed.

### AI authority, orchestration, and stored reasoning traces

Two backend stages share the same canonical financial state; a small sequential pipeline is sufficient. Developer 3 owns model calls, timeouts, structured outputs, and in-memory decision records. Developer 4 owns allowed actions, validation, templates, and financial meaning.

1. **Recommendation Agent:** receive Python-computed `FinancialState` indicators directly as structured input: liquidity, debt burden, savings capacity, and horizon. Python calculates debt burden as annual required minimums / annual gross salary, and savings capacity as current monthly surplus / take-home (null when take-home is zero). Include these metrics in the internal agent context; do not add readiness without a defined target. In one call, return a permutation of `starter_reserve`, `high_apr_debt`, and `full_reserve`, plus concise evidence-linked rationale and tradeoffs. Starter reserve must precede full reserve. Ground the text in actual state and explicit preference; do not infer preferences from names or demographics. The agent cannot compute or overwrite indicators.
2. **Explanation Agent:** receive the validated decision, calculated amounts, projections, and Python-computed changes from the previous decision. Generate the state summary and a short “why this plan / why it changed” narrative. Do not expose a raw internal reasoning transcript.

Policy decision: the `planning_preference` → ordering table is the default order and the rules fallback: balanced → starter/debt/full; cash-security → starter/full/debt; debt-reduction → debt/starter/full. The Recommendation Agent may choose any of these three documented orders for any profile; the prompt lists the preference default first. It supplies grounded rationale and tradeoffs for the order it chooses. Python rejects incomplete, duplicate, unknown, or full-before-starter orders and validates every proposed order before use. The saved Morgan cash-security variant in Section 12 demonstrates a non-default choice. The same timeout and invalid-output fallback rules apply.

Hard constraints always remain in Python: essentials and debt minimums, critical reserve before discretionary contributions, affordable employer-match capture, contribution caps, minimum-to-full reserve dependency, avalanche debt ordering, and conservation of cash. Additional retirement contributions and residual cash follow the selected discretionary priorities. No AI changes to equity allocation, APRs, matching formulas, return assumptions, reserve targets, or scenario inputs. Explicit custom contribution elections retain their documented scenario semantics; AI cannot override them. Current uses its original fixed strategy. Adaptive and Custom share one validated ordering per evaluation so comparisons do not introduce unrelated AI choices.

Validate exact action membership, uniqueness, completeness, dependency order, evidence paths, and populated rationale before using a proposal. Unknown fields/actions or failed checks reject the proposal. Python calculates and records constraint checks after validation. For blocked financial inputs, skip AI and return the existing blocked evaluation.

Use structured model output and a pinned configurable model ID; no particular vendor/model release is required by this plan. Treat all profile text and imported data as data, never agent instructions. Send normalized financial facts and explicit preferences only; exclude names, bank identifiers, account numbers, credentials, and raw Plaid payloads.

Bound the complete AI pipeline to four seconds total across the two calls; individual requests must fit the remaining deadline. Removing the third call roughly doubles the available per-call latency margin. No automatic retries in the interactive request. On timeout, unavailable credentials, provider failure, invalid proposal, or invalid state summary, use the deterministic fallback order and template explanations. An explanation-only failure retains the valid decision and uses templates. The existing eight-second iOS timeout remains; provider latency is separately measured. Never label fallback or saved content as live AI.

Narratives cannot introduce unsupplied amounts or claims. Prefer supplied labeled facts for numeric display; use qualitative prose for the generated narrative. Validate referenced facts and fall back to templates on unsupported references. Preserve the validated structured summary and final explanation in Evaluation; do not retain raw model transcripts. Fallback summaries contain the actual applied ordering and Python-generated rationale.

The engine is deterministic for the same profile, assumptions, scenario, and validated decision. Live model selections may vary: store the accepted decision for reproducibility. Input hashes include validated ordering, planning preference, and model/prompt provenance in addition to numeric inputs and versions. Decision IDs, timestamps, and generated prose are excluded from numeric equality checks.

Decision replay through `previous_decision_id` and the bounded 128-entry, oldest-out in-memory map is required at the Hour 12 MVP gate for `ExploreViewModel` and acceptance tests. Do not defer or cut it under time pressure: no persistence, no eviction policy beyond FIFO/oldest-out, and no database.

## 10. Illustrative target-date glide path

Piecewise-linear equity anchors:

~~~text
Years to retirement   Equity
30 or more            90%
20                    80%
10                    65%
0                     50%
~~~

Bonds = 1 − equity. Interpolate linearly and clamp beyond 30 years. Use remaining horizon at the beginning of each month.

Do not adjust for debt, wealth, or readiness. This does not reproduce a specific T. Rowe Price fund.

Jordan/Morgan start at 90%; Casey at 60.5%.

## 11. Deterministic simulation

### Assumptions

~~~text
annual_equity_return:           0.06
annual_bond_return:             0.03
annual_cash_return:             0.00
annual_inflation:               0.025
annual_salary_growth:           0.025
annual_living_cost_growth:      0.025
annual_employee_limit_growth:   0.025
high_interest_apr_threshold:    0.10
retirement_total_saving_target: 0.15
critical_reserve_cap_cents:     100000
starter_reserve_months:        1
full_reserve_months:           3
returns_net_of_fees:           true
~~~

These are illustrative nominal assumptions, not sponsor forecasts. No volatility, changing brackets, withdrawal taxation, or retirement spending.

Grow salary, reconstructed resources before contributions, living expenses, and the planning cap at model anniversaries, starting before month 13. Hold the marginal tax adjustment constant. Future cap indexing is an assumption, not future law.

Use annual cap /12 as a monthly ceiling. No year-to-date accounting or true-ups.

Keep APR and minimum payments fixed nominal until payoff. Real credit-card interest conventions/minimums differ. No new borrowing.

### Strategies

**Current:** preserve original employee rate subject to modeled cap, pay minimums, retain residual cash. Do not invent extra payments absent from inputs.

**Adaptive:** apply the full waterfall with the validated decision order.

**Custom with explicit rate:** reserve essentials, fix the requested contribution/matching, then direct residual cash through critical reserve, the validated ordering of starter reserve/high-interest debt/full reserve, and cash. Skip automatic additional retirement contributions. This is a selected scenario, not a recommendation; warn when it delays liquidity.

**Custom with null rate:** adaptive policy with the selected retirement age.

If Current cannot fund its election, mark that projection infeasible but preserve any feasible Adaptive result. Reject unaffordable custom submissions with 422 INFEASIBLE_SCENARIO and a budget-gap message. Do not silently reduce custom rates.

### Monthly sequence

1. Apply anniversary growth.
2. Accrue debt interest.
3. Calculate capped minimums.
4. Reserve essentials and minimums.
5. Allocate remaining cash.
6. Apply payments and reuse final-payment excess once.
7. Apply retirement returns to opening balance.
8. Add employee/employer contributions at month-end.
9. Update cash, points, and milestones.

### Debt

~~~text
interest = opening_balance * APR / 12
amount_due = opening_balance + interest
payment = min(amount_due, minimum_payment + extra_payment)
closing_balance = max(0, amount_due - payment)
~~~

Flag negative amortization when payment is below interest. Release a paid-off debt's minimum next month. Unused money within its final month remains available immediately; do not count it twice.

### Retirement assets

~~~text
annual_return = equity_weight * 0.06 + bond_weight * 0.03
monthly_return = (1 + annual_return)^(1/12) - 1

closing_retirement_balance =
  opening_retirement_balance * (1 + monthly_return)
  + employee_contribution
  + employer_match
~~~

### Inflation and milestones

~~~text
today_dollars = nominal_future_dollars / 1.025^(months / 12)
~~~

Include month-0 point. Existing no-debt or funded-reserve milestones are 0. Otherwise record first month-end meeting the condition. Null means not reached. A first-hit reserve milestone does not guarantee the target remains funded forever.

Emergency savings is part of cash, not an additional asset. Do not combine pretax retirement assets with cash into an unlabeled spendable total.

### Monte Carlo

Optional stretch only after the hour-12 MVP and AI acceptance checks pass, and before the hour-18 freeze. Use seeded Python simulations with disclosed assumptions; never route projections through an LLM. Keep deterministic projections as the demo default. Percentiles are not retirement success probabilities; do not add readiness scores or success claims.

## 12. Exact fixtures

Demo framing: Morgan is a fictional T. Rowe Price customer created for this prototype. Jordan and Casey are fictional comparison profiles. Display “Fictional customer • Synthetic data • Not affiliated with or endorsed by T. Rowe Price.” No real customer information, actual fund-performance claims, or sponsor endorsement is implied. All preferences and account values are invented.

All fixtures:

- Date 2026-09-26, USD.
- Traditional employee contributions and 22% estimated marginal income-tax adjustment.
- $24,500 employee planning cap.
- Fully vested 100% match on the first 5% of salary.
- Provenance fixture on every input; planning_preference is balanced by default.
- No unlisted debts or expenses.

Convert the specification's dollars below to integer cents in profiles.json.

### Jordan — financially established

~~~text
id: jordan
age: 35
retirement age: 67
annual gross salary: $120,000
monthly take-home: $6,900
current employee contribution: 10%
retirement balance: $150,000
emergency cash: $26,400
monthly living expenses: $4,400
debt:
  id: jordan-student
  type: student_loan
  balance: $15,000
  APR: 4%
  minimum: $200/month
~~~

Expected with the committed balanced decision: six months of reserves, full match, maintain 10% contribution, retain low-rate loan minimum, surplus to cash, 90% illustrative equity.

### Morgan — competing priorities

~~~text
id: morgan
age: 35
retirement age: 67
annual gross salary: $84,000
monthly take-home: $4,800
current employee contribution: 8%
retirement balance: $35,000
emergency cash: $3,600
monthly living expenses: $3,600
debt:
  id: morgan-card
  type: credit_card
  balance: $18,000
  APR: 25%
  minimum: $400/month
~~~

Opening-month acceptance arithmetic for the committed balanced decision:

~~~text
Current employee contribution:     $560.00
Estimated current take-home cost:  $436.80
Resources before contribution:   $5,236.80
Living expenses:                 $3,600.00
Debt minimum:                      $400.00
Adaptive employee contribution:    $350.00 (5%)
Adaptive take-home cost:            $273.00
Employer contribution:             $350.00
Extra debt payment:                $963.80
Total debt payment:              $1,363.80
~~~

One month of reserves is already funded. Preserve full matching and accelerate high-interest debt. After payoff, build three months of reserves, then increase contributions. Initial equity remains 90%, the same as Jordan.

Team decision for sign-off before the Hour 18 feature freeze: keep the AI-reordering demonstration as a tenth artifact. Prepare a separate Morgan cash-security fixture variant and a reviewed decision that orders starter reserve → high-APR debt → full reserve instead of the cash-security default of starter reserve → full reserve → high-APR debt. Ground this one documented exception in Morgan's 25% APR debt and show the debt-interest versus liquidity tradeoff. Export its evaluation through the same engine as `morgan-cash-security.json`. This is additional to the nine required presets; label it as a saved AI decision. Balanced acceptance arithmetic above remains pinned to its original decision.

### Casey — approaching retirement

~~~text
id: casey
age: 58
retirement age: 65
annual gross salary: $110,000
monthly take-home: $5,900
current employee contribution: 12%
retirement balance: $850,000
emergency cash: $36,000
monthly living expenses: $4,500
debt: none
~~~

Expected: eight months of reserves, full match, maintain 12%, no urgent debt action, 60.5% illustrative equity, seven-year projection. Do not claim retirement adequacy from the balance.

## 13. Offline artifact exporter

Implement export_demo.py using the same evaluator as the API. No manually authored numerical results. Store reviewed, validated AI decisions in backend/fixtures/decisions.json with model/prompt provenance and explanations; replay these during export. Include explicit rules-fallback fixtures for outages. Each preset reuses the profile's pinned ordering. Artifacts retain decision_summary and explanation; saved AI must be labeled as saved, not a live call.

For each profile export:

1. Original Current/Adaptive evaluation, scenario=null.
2. Retirement age +2, contribution override null.
3. Original retirement age, fixed contribution = adaptive opening rate +0.01.

All selected fixtures fit the 20% UI ceiling and preset affordability. If a prescribed preset becomes invalid, export fails; do not silently change it.

Files:

~~~text
manifest.json
profiles.json
<profile>-original.json
<profile>-retire-plus-two.json
<profile>-contribution-plus-one.json
morgan-cash-security.json
~~~

Each artifact:

~~~text
profile_id
profile_hash
schema_version
model_version
policy_version
scenario
evaluation
~~~

Profile hash: SHA-256 of server canonical profile JSON. Input hash additionally covers scenario, assumptions, versions, validated priority ordering, and model/prompt provenance. Use sorted keys and stable compact JSON. Swift treats hashes as opaque.

Manifest maps profile/preset IDs to filenames and includes the separate Morgan cash-security variant mapped to `morgan-cash-security.json`. Check generated artifacts into the repo and copy them into iOS only after tests pass. Exclude timestamps from deterministic equality assertions. The demo script's 2:35–3:00 segment shows this specific saved artifact, its priority ordering, and its structured decision summary.

## 14. Optional Plaid Sandbox

Start only after hour-12 MVP. Developer 3 owns server adapter; Developer 2 owns LinkKit.

Scope:

- Sandbox only, one rehearsed institution.
- Request Liabilities for the debt import demonstration.
- Import balances for accounts returned by that connection.
- Manually confirm retirement balance and other missing inputs.
- No Investments, Transactions, income inference, webhooks, or background sync.

Server flow:

1. Create Link token with backend credentials and random ephemeral client-user ID.
2. Exchange public token server-side.
3. Store access token in memory under an opaque random session identifier.
4. Return session identifier and expiry.
5. Import accounts/liabilities using authenticated session.
6. Return draft, missing paths, and warnings.
7. iOS confirms inputs and submits canonical profile for evaluation.

Separate exchange/import so a data-fetch retry does not reuse a one-use public token. After an ambiguous exchange timeout, require fresh Link rather than blindly retrying the same token.

Normalization:

- Join liabilities to accounts by account ID; deduplicate.
- Do not add an account balance and corresponding liability balance twice.
- Preserve timestamps/provenance.
- Convert APR percentages to fractions.
- Missing APR/minimum/balance remains unknown.
- Multiple APR categories require confirmation.
- Negative credit balance is not debt; warn rather than turning it into emergency cash.
- Credit availability is not cash.
- Confirm earmarked funds before mapping bank cash to emergency cash.
- Confirm age, retirement date, salary, take-home, expenses, contribution election, tax estimate, retirement balance, and matching.
- Unsupported obligations keep the profile incomplete. Never silently drop them.
- Reject unsupported currencies.

Plaid exposes APR categories and payment information, not a complete financial plan. [Plaid Liabilities API](https://plaid.com/docs/api/products/liabilities/)

Use four-second per-upstream-request timeouts. Return partial data or retryable unavailability when data is not ready. Limit user-initiated import attempts to three per session before directing the presenter to demo profiles.

Restart clears sessions; expired sessions return 401 SESSION_EXPIRED. Native OAuth/Universal Links can exceed the schedule. Rehearse a non-OAuth Sandbox flow, and cut Plaid if unsupported instead of adding domain/entitlement work. [Plaid iOS setup](https://plaid.com/docs/link/ios/)

**Hour 15 cutoff:** retain only a complete phone connect → import → confirm → evaluate flow.

## 15. Environment, tokens, and hosting on a Mac

~~~text
APP_ENV=hackathon
AI_ENABLED=true
AI_PROVIDER=...
AI_MODEL=...              # pin an available model ID at setup
AI_API_KEY=...            # backend only
AI_PROMPT_VERSION=1
AI_TOTAL_TIMEOUT_SECONDS=4
PLAID_ENABLED=false
PLAID_ENV=sandbox
PLAID_CLIENT_ID=...
PLAID_SECRET=...
PLAID_REDIRECT_URI=...     # only for a tested OAuth setup
SESSION_TTL_SECONDS=7200
LOG_LEVEL=info
~~~

Missing AI credentials disable live AI and expose rules fallback; do not break the demo. Fail startup if enabled Plaid lacks credentials or uses non-Sandbox configuration. Commit only placeholder .env.example; ignore .env.

Boundaries:

- No secrets/access tokens in iOS or bundles.
- In-memory token sessions, two-hour expiry, one worker.
- No financial request-body/token logs.
- Logs contain route, status, latency, sanitized error code.
- No connected-profile database or file persistence.
- Bound request size, debt/tier counts, and simulation horizon.
- Simple global ceilings: 120 evaluations/minute, 10 requests/minute for each Plaid mutation endpoint. Return 429; no distributed rate-limit service.
- No full account authentication for the synthetic/Sandbox prototype; do not portray this as production-ready for real accounts.

Run from backend directory:

~~~bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8000
~~~

Separate terminal sessions:

~~~bash
cloudflared tunnel --url http://localhost:8000
~~~

~~~bash
caffeinate -i
~~~

Install cloudflared from its official instructions before rehearsal. Enter the printed HTTPS URL in iOS settings. A tunnel restart can change it; no app rebuild should be needed.

Quick Tunnels expose the Mac's local service without moving FastAPI to a cloud instance. There is no uptime guarantee. [Cloudflare Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)

Judging: Mac powered, lid open, server/tunnel running without reload, phone health check completed, cellular tested, hotspot available. A second Mac may keep the same checkout/dependencies as a manual backup; do not build failover infrastructure.

## 16. Team and Git ownership

**Developer 3:**

- First: health, demo profiles, phone-reachable tunnel.
- Owns schemas, routes, error envelopes, OpenAPI, Plaid, tokens, runbook.
- Does not alter financial assumptions without Developer 4.
- Does not add storage or account infrastructure.

**Developer 4:**

- First: fixtures, budget arithmetic, match tests.
- Owns state, waterfall, simulation, facts, assumptions, tests, exporter.
- Does not build UI or Plaid.
- Owns any gated Monte Carlo stretch; never delegates numeric projections to an LLM.

Developer 1 uses contract examples for UI; Developer 2 decodes them into Swift. Contract changes require updated examples and a successful Swift decode.

Use small task branches, reviewed squash merges every one to two hours, buildable main, and committed dependency locks. Developer 3 owns schema files; Developer 4 coordinates edits. Tag vertical-slice, mvp, demo-final.

## 17. Timeline

- **Hours 0–1:** server/tunnel, units/budget definitions, fixtures; iOS proves installation.
- **Hours 1–2:** freeze schemas, examples, errors, versions, assumptions.
- **Hours 2–4:** state/policy and a real phone-visible response plus matching bundle.
- **Hour 4:** vertical-slice gate; cut Plaid if incomplete.
- **Hours 4–7:** waterfall, reasons, profiles, accounting tests; bounded AI pipeline and structured decisions.
- **Hours 7–10:** monthly current/adaptive/custom simulation and edge cases; AI validation, prior-decision diff, and fallback tests.
- **Hours 10–12:** all presets, live/offline integration.
- **Hour 12:** MVP gate: required product offline, live evaluator connected, bounded AI ordering and rules fallback verified.
- **Hours 12–15:** conditional Plaid by Developer 3; financial audit by Developer 4.
- **Hour 15:** cut incomplete Plaid.
- **Hours 15–18:** reliability, data gaps, latency, integration.
- **Hour 18:** freeze features.
- **Hours 18–20:** final tests, artifacts, dependency freeze.
- **Hours 20–22:** normal/outage rehearsals and recording.
- **Hours 22–23:** final build/tag and backups.
- **Hours 23–24:** blocking fixes only.

## 18. Tests and acceptance

AI acceptance:

- Valid alternative ordering changes funded allocations when the fixture budget makes the tradeoff relevant.
- Missing/duplicate/unknown priorities, full-before-starter, and invalid evidence paths fall back.
- AI cannot change protected priorities, amounts, allocations, or assumptions.
- Provider outage, invalid output, and deadline exhaustion preserve an honest rules-backed evaluation.
- Explanation failure preserves a valid decision; no unsupported numbers reach the UI.
- Prior IDs expire safely and cannot compare different profiles.
- Saved decision replay reproduces numeric results and all ten artifacts without a model call.
- Profile text cannot override system constraints; model requests exclude identifying data.

Financial tests:

- Full, partial, absent, unknown, and tiered matching.
- Five percent employee for four percent employer in the tiered example.
- Essential shortfalls never produce unfunded recommendations.
- Critical liquidity can precede matching.
- Reserve allocation funds only the missing amount.
- Exactly 10% APR enters high-interest priority.
- Stable avalanche tie-breaking.
- Four-percent student loan gets no high-interest extra.
- Debt does not change equity allocation.
- Zero-APR debt and negative amortization.
- Final payment capped at amount due.
- Released payoff money used once.
- Employee cap excludes employer matching.
- Traditional/Roth cash costs differ correctly.
- Unaffordable custom rate fails explicitly.
- Higher original rate preserved in the later retirement stage when affordable.
- Morgan's extra payment equals $963.80.

Simulation identities:

- Sources equal expenses, debt, contribution cash cost, and cash added within one cent each month.
- Zero-return assets equal opening balance plus contributions.
- No negative debt balances.
- Initial milestones equal 0 where already achieved.
- Null means not reached.
- Identical inputs/assumptions/validated ordering produce identical numerical outputs.
- Horizon changes consistently update allocations and growth.
- Different strategies can reasonably trade retirement balance against liquidity/debt.
- Inflation adjustment uses the correct horizon.

Contract/integration:

- Examples validate in Pydantic and decode in Swift.
- Error envelope consistent.
- Unknown matching never becomes zero.
- No NaN/Infinity.
- All ten artifacts regenerate from the live function.
- Hashes, scenarios, versions match manifest.
- No handwritten projection totals or probability scores.
- Phone reaches health/evaluate over cellular through tunnel.
- Backend shutdown preserves offline demo.
- Stretch: partial imports, timeouts, invalid/expired sessions, restart, cancellation.

Aim for the pure local engine under 250 ms on fixtures; measure AI-inclusive latency against the four-second pipeline deadline and eight-second client timeout. Measure after integration; do not add caching infrastructure without evidence. Frontend timeout is eight seconds.

## 19. Demo reasoning and done criteria

Jordan and Morgan share age 35 and retirement age 67. Both retain 90% illustrative equity. Jordan maintains contributions; Morgan preserves matching and directs affordable cash toward 25% APR debt. Show the arithmetic.

Describe the Current baseline honestly: unchanged contribution rate and minimum debt payments, not observed transaction history. Compare interest, liquidity, and retirement assets together.

Developer 3 answers connectivity/security questions. Developer 4 answers affordability, matching, modeling, and limitations. Keep live Link outside the main three-minute story.

**Backend done:** one tested engine powers live responses and saved artifacts; every recommended dollar is funded; assumptions are visible; and stopping the service does not break the core phone demonstration.

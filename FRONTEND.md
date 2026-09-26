# Adaptive Retirement — Frontend Implementation Handoff

**Audience:** Developers 1 and 2.  
**Build window:** 24 hours.  
**Companion:** [BACKEND.md](BACKEND.md).  
**Status:** Implementation specification; creating this document does not implement the application.

## 1. Product and scope

Build a native SwiftUI application that explains how retirement contributions, emergency savings, and debt repayment compete for the same available cash. The target-date strategy remains the investment foundation.

**Pitch:** Same retirement date. Different financial lives.

The experience answers:

1. What retirement contribution fits this person's current cash flow?
2. Where should their next available dollar go?
3. What happens to debt, cash, and retirement assets over time?

The backend owns financial calculations. Swift formats and displays results; it never independently calculates recommendations, employer matching, payoff dates, or projections.

### Required features

- Three synthetic profiles, including two with the same age and retirement date.
- Instant profile switching.
- Financial snapshot with sources and dates.
- One primary recommendation on Overview.
- A plan separating employee contributions, employer matching, debt, liquidity, and allocation.
- AI explanations grounded in validated decisions, with deterministic template fallback and supporting inputs.
- Current-versus-adaptive projections.
- Custom retirement-age and contribution scenarios while connected.
- Bundled engine-generated profiles and selected scenarios while offline.
- A physical-iPhone demonstration.

### Scope cuts

- No readiness score, probability of success, or guaranteed retirement-income number.
- No automatic allocation adjustment based on debt or assets.
- No on-device LLM, chatbot, trading, authentication accounts, or production bank credentials. AI calls run on the backend.
- No independent debt-payment slider. Contribution changes must affect other priorities.
- Plaid Sandbox is conditional stretch work, not the main demo entry point.
- No second financial engine in Swift.

T. Rowe Price already researches target-date personalization. Present this prototype as an explainable participant experience around that concept. [T. Rowe Price research](https://www.troweprice.com/institutional/us/en/insights/articles/2024/q3/make-it-personal-the-next-chapter-for-target-date-solutions-na.html)

## 2. Technology and first-hour device gate

Use Swift, SwiftUI, Foundation/URLSession, and Swift Charts. Target iOS 17+. Avoid third-party navigation, networking, state-management, or charting frameworks.

The team has not yet deployed SwiftUI to a physical iPhone. Astra-assisted development does not remove signing risk.

Developer 2 must:

1. Designate the integration Mac and demo iPhone.
2. Sign into Xcode, select a development team, and use automatic signing.
3. Choose a unique bundle identifier.
4. Pair and trust the phone; enable Developer Mode when required.
5. Install and launch a minimal app.
6. Disconnect Xcode and confirm the app still opens.

If this fails in hour one, Developer 1 helps before continuing styling. Keep SwiftUI; do not spend the event migrating stacks.

Apple documents personal-account setup, automatic signing, and device provisioning. Simulator success does not replace this checkpoint. [Apple device deployment](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)

## 3. Navigation and exact screens

Use Welcome followed by three tabs. Each tab has its own NavigationStack.

### Welcome

Copy:

> Adaptive Retirement  
> Your retirement plan should understand more than your retirement date.

Actions:

- Primary: **Explore demo profiles**.
- Secondary: **Connect Sandbox accounts**, visible only after the complete flow passes its gate.
- Connection Settings toolbar action.

Show: **Educational prototype using synthetic or Sandbox data.** Morgan is a fictional T. Rowe Price customer; Jordan and Casey are fictional comparison profiles. Display **Fictional customer • Synthetic data • Not affiliated with or endorsed by T. Rowe Price.**

### Overview tab

Order:

1. Profile name and switcher.
2. Age and planned retirement age.
3. Data-mode badge.
4. Primary action with monthly amount when applicable.
5. Employer match captured, emergency months, retirement balance.
6. Financial Snapshot entry.
7. View Plan action.

Data badges: **Saved demo calculation**, **Live calculation**, or **Last live calculation**.

Do not use a health-score ring. Profiles with no urgent action receive a maintenance recommendation.

### Plan tab

Sections:

- **Retirement contributions:** employee percentage, employee dollars, estimated take-home cost, employer matching.
- **Monthly cash priorities:** contribution cash cost, savings allocation, extra debt payment, remaining cash.
- **Debt:** required minimum and additional payment separately.
- **Emergency savings:** current months, starter target, full target.
- **Target-date foundation:** stocks/bonds bar and explanation.

Every section has **Why?**. Show the backend-generated narrative, selected priority order, supporting facts, tradeoffs, and constraint checks from the structured decision summary. Label decision origin **AI-assisted priorities**, **Rules fallback**, or **Saved AI-assisted priorities** independently of the existing data-mode badge. Never show raw internal model reasoning. Blocked actions show the missing input or cash-flow gap.

Allocation copy:

> This prototype retains an illustrative target-date allocation. Your financial context changes contributions and cash priorities; it does not establish a suitable alternative portfolio.

Label the bar: **Illustrative allocation — not a specific T. Rowe Price fund**.

### Explore tab

Default: compare Current and Adaptive at the profile's original retirement age.

Controls:

- Retirement age: integer steps, current age +1 through 80, matching backend validation.
- Optional employee contribution override: 0–20%, steps of 0.5 percentage points.
- **Compare scenario** button.
- Offline preset buttons: original plan, retire two years later, contribution +1 percentage point.

A null contribution override means the adaptive policy remains active at the selected retirement age. An explicit override means a fixed employee rate, subject to modeled caps.

The +1-point preset is relative to the adaptive opening-month employee rate. Do not calculate it in Swift; read the exact value from the artifact.

Show at most two chart lines:

- Default: Current and Adaptive.
- Custom result: Adaptive and Custom.

For different retirement ages, use a shared calendar-year axis but stop each trajectory at its own retirement date. Label both ages. Do not extrapolate the shorter trajectory.

Outcome cards:

- Retirement-account balance, nominal or today's dollars.
- Debt-free timing, or **Not paid off before retirement**.
- Cumulative debt interest.
- Emergency-reserve milestones.
- Cash and remaining debt at the respective retirement date.

A lower retirement-account balance does not automatically mean a worse overall result. Show debt and liquidity consequences alongside it.

### Supporting sheets

- Profile picker.
- Financial snapshot.
- Recommendation explanation.
- Modeling assumptions.
- Connection settings.
- Stretch: imported-profile confirmation.

Snapshot shows canonical inputs, sources, and as-of dates. No transaction feed or holdings drilldown.

## 4. Components and visual direction

~~~text
AdaptiveRetirementApp
  RootView
    WelcomeView
    MainTabView
      OverviewView
        ProfileHeader
        NextActionCard
        MetricRow
        DataModeBadge
      PlanView
        ContributionCard
        CashAllocationStack
        DebtActionCard
        EmergencyProgress
        AllocationBar
      ExploreView
        ScenarioControls
        PresetPicker
        ProjectionChart
        OutcomeCards
~~~

Use system typography, one accent color, neutral cards, consistent spacing, and standard controls. Distinguish chart series with labels and line style as well as color. Support larger text and VoiceOver.

Use Swift Charts for the line chart and SwiftUI shapes for allocation and cash bars. No 3D graphics, animated gauges, or custom chart packages. [Apple Swift Charts](https://developer.apple.com/documentation/charts)

## 5. MVVM and state ownership

### AppStore

One MainActor ObservableObject, created with StateObject at the app root and injected into the view tree.

Owns:

- Selected canonical profile and tab.
- Current evaluation and data-mode metadata.
- Public HTTPS base URL.
- Profile-selection generation counter.
- Connection state and demo/live preference.

It contains no financial policy or private credentials.

### PlanViewModel

Shared by Overview and Plan. Owns evaluation loading, retry, explanation selection, and presentation state. The two tabs must not request duplicate evaluations.

### ExploreViewModel

Owns draft controls, submitted settings, request task, and comparison result. Pass the last live decision ID for the same profile as previous_decision_id; reset it on profile or server changes. Missing/expired prior IDs simply show an initial-plan explanation. Draft edits do not change the active recommendation. Displayed results retain their submitted settings.

### ConnectionViewModel

Stretch only. Owns Link presentation, handler/session lifetime, exchange/import state, in-memory opaque backend session token, and draft confirmation. Never contains a Plaid access token.

### APIClient

Injectable protocol with URLSession implementation and a small fake for tests. Use async/await and Codable.

Responsibilities:

- Build URLs from the configured HTTPS base URL.
- Encode/decode the shared contract.
- Map error envelopes.
- Eight-second evaluation timeout.
- Cancellation.
- No request-body or token logging.

### DemoRepository

Loads bundled profiles and exact preset artifacts. No interpolation, recommendation rules, or scenario calculations.

### Loading state

~~~text
idle
loading(previous_result?)
loaded(result)
failed(previous_result?, error)
~~~

On profile selection:

1. Increment selection generation.
2. Cancel old evaluation and scenario tasks.
3. Load the selected profile's bundled original result immediately.
4. Reset draft scenario controls.
5. Request live results only if live mode is enabled.
6. Apply a response only when generation and profile ID still match.

Never block the first dashboard on a health check.

## 6. Shared API contract

Keep this section synchronized with BACKEND.md. Once implementation starts, Pydantic schemas and the exported OpenAPI document are authoritative.

### Conventions

- Prefix: /v1, except /health.
- Schema version: "1".
- Initial model and policy versions: "1.0.0".
- Money: integer USD cents, decoded as Int64.
- Rates: JSON numbers; 0.05 means 5%, decoded as Double.
- Dates: YYYY-MM-DD.
- Timestamps: UTC ISO 8601.
- Month 0: starting snapshot; month 1: first month-end.
- Null milestone: not achieved within the horizon.
- Explicit Swift CodingKeys for snake_case.
- Hashes are opaque backend-generated strings.

Formatting dollars or percentage labels is allowed. Deriving a new financial score or recommendation is not.

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

Disabled Plaid routes return 503 with PLAID_DISABLED. Demo profiles never depend on Plaid.

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

Take-home pay is after the current employee retirement deduction. Living expenses exclude debt payments and savings transfers. Emergency cash excludes earmarked imminent bills. The confirmation UI must preserve these definitions.

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

Required reason codes:

~~~text
CASH_FLOW_SHORTFALL, CRITICAL_LIQUIDITY, CAPTURE_EMPLOYER_MATCH,
MATCH_PARTIALLY_AFFORDABLE, BUILD_STARTER_RESERVE, HIGH_APR_DEBT,
BUILD_FULL_RESERVE, INCREASE_RETIREMENT_SAVING, MAINTAIN_CONTRIBUTION,
UNASSIGNED_SURPLUS, BASELINE_ALLOCATION_RETAINED,
MISSING_REQUIRED_INPUT, SIMPLIFIED_TAX_ESTIMATE
~~~

Use the validated backend AI narrative when available, otherwise deterministic English templates. Developer 4 owns financial meaning and facts; Developer 1 owns layout. Unknown template keys show a neutral explanation and supplied labeled facts, never an invented recommendation.

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

Current and Adaptive use the original retirement age. Custom uses the submitted retirement age. Null contribution override applies the adaptive policy at that age; an explicit override fixes the contribution election.

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

Handle 422 invalid/infeasible inputs, 401 expired sessions, 429 rate limits, 503 unavailable integrations, and sanitized 500 errors. Valid base profiles with financial shortfalls return a blocked evaluation with HTTP 200.

## 7. Offline bundle and failure behavior

Developer 4 generates artifacts by calling the same evaluator used by FastAPI. Developer 2 adds them to the resource bundle.

~~~text
Resources/Demo/
  manifest.json
  profiles.json
  jordan-original.json
  jordan-retire-plus-two.json
  jordan-contribution-plus-one.json
  morgan-original.json
  morgan-retire-plus-two.json
  morgan-contribution-plus-one.json
  casey-original.json
  casey-retire-plus-two.json
  casey-contribution-plus-one.json
  morgan-cash-security.json
~~~

Each artifact wraps profile_id, profile_hash, schema/model/policy versions, exact scenario, and evaluation. `profiles.json` includes the separate `morgan-cash-security` variant. The manifest maps profile/preset IDs to filenames, lists `jordan`, `morgan`, and `casey` in `default_profile_ids`, and marks the tenth artifact as a demonstration with `base_profile_id: "morgan"`. Show only the three default IDs in the normal customer picker. The Morgan demonstration uses its saved variant profile and evaluation together; label its AI text as saved content.

Behavior:

- Load bundled profiles without a network prerequisite.
- Offline profile switching, all nine standard presets, and the separate Morgan demonstration remain available.
- Disable arbitrary submission with **Reconnect for a custom scenario**.
- Never interpolate between presets.
- Preserve the last successful live result in memory and label it.
- Never substitute synthetic results for a connected profile.
- Connected-profile failure offers retry or explicit demo selection.
- Corrupt/version-incompatible artifacts produce a recoverable error.

Keep prior content during refresh with an inline indicator. A changed control does not relabel an old result. Infeasible scenarios show the budget gap while retaining clearly labeled previous results. No infinite retries.

## 8. Networking and local backend

The backend runs on a teammate's Mac through a temporary Cloudflare HTTPS tunnel. The iPhone must use the tunnel URL: its own localhost points to the phone.

Connection Settings allows editing the HTTPS base URL without rebuilding. Changing it resets live connection state but preserves bundled profiles. Do not add global App Transport Security exceptions.

Tunnel URLs may change on restart. Quick Tunnels have no uptime guarantee, so saved scenarios are mandatory. [Cloudflare Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)

## 9. Optional Plaid LinkKit

Start only after the hour-12 MVP gate.

1. Request a link token.
2. Present native Link with the pinned SDK's documented interface.
3. Retain its handler/session for the presentation lifetime.
4. Exchange the successful public token through FastAPI.
5. Keep the returned opaque backend session token in memory.
6. Import the draft.
7. Confirm imported and missing inputs.
8. Evaluate only a complete canonical profile.

Cancellation returns quietly to the previous screen. Expired sessions require reconnecting. Plaid secrets and access tokens remain server-side.

Use Swift Package Manager with https://github.com/plaid/plaid-link-ios-spm and pin the resolved version. Current LinkKit 7.x documentation lists Xcode 16.1 minimum. OAuth may require redirect registration and Universal Links. Rehearse one non-OAuth Sandbox flow; do not add domain/entitlement work if it threatens the cutoff. [Plaid iOS setup](https://plaid.com/docs/link/ios/)

**Hour 15 cutoff:** if connect → import → confirm → evaluate does not work on the phone, hide Connect and stop Plaid work.

## 10. Project structure and ownership

~~~text
ios/
  AdaptiveRetirement.xcodeproj
  AdaptiveRetirement/
    App/
    Models/
    Services/
    Features/
      Overview/
      Plan/
      Explore/
      Connection/
    Components/
    Resources/Demo/
  AdaptiveRetirementTests/
~~~

**Developer 1:** views, presentation/navigation, components, charts, accessibility, explanation layouts. Starts with static contract examples.

**Developer 2:** project/signing, dependencies, Codable models, AppStore/ViewModels, APIClient, bundles, and optional LinkKit. Starts with physical-device installation.

Developer 2 alone edits Xcode project settings and packages. Developer 1 does not implement networking or financial logic. Developer 3 owns backend schemas; Developer 4 owns financial meanings and output generation.

## 11. Timeline and integration gates

- **Hours 0–1:** physical install and UI skeleton.
- **Hours 1–2:** decode contract examples; phone reaches backend health over HTTPS.
- **Hours 2–4:** real recommendation on phone; same response loads from bundle.
- **Hour 4 gate:** working vertical slice; otherwise remove Plaid.
- **Hours 4–7:** Overview, Snapshot, Plan, explanations, profile switching.
- **Hours 7–10:** Explore controls, chart, milestones, scenario submission; AI summaries, decision provenance, and change explanations.
- **Hours 10–12:** offline presets, timeout handling, full device walkthrough.
- **Hour 12 MVP gate:** required UI works offline and live evaluation works.
- **Hours 12–15:** conditional LinkKit by Developer 2; polish by Developer 1.
- **Hour 15:** cut incomplete Plaid.
- **Hours 15–18:** reliability, accessibility, second-device checks.
- **Hour 18:** feature freeze.
- **Hours 18–20:** final builds and artifact verification.
- **Hours 20–22:** normal/offline rehearsal and recording.
- **Hours 22–23:** final install, backups, cables and power.
- **Hours 23–24:** blocking fixes only.

## 12. Git and acceptance tests

Use one monorepo, short-lived task branches, reviewed squash merges every one to two hours, and buildable main. Do not leave UI and integration branches separate until the final hours.

Commit shared scheme and dependency lockfile. Exclude DerivedData, user-specific Xcode state, and secrets. Tag vertical-slice, mvp, and demo-final.

Required checks:

- Install and launch on the demo iPhone, including without debugger.
- Decode all examples and all ten artifacts, including the Morgan demonstration.
- Switch profiles during a request without stale results.
- Preserve submitted scenario labels when draft controls change.
- Test timeouts and backend shutdown.
- Airplane-mode cold launch, profile switching, and every preset.
- Disable custom offline submission without disabling presets.
- Handle missing inputs and infeasible scenarios.
- Verify AI/rules/saved labels, structured traces, expired prior IDs, and model-outage fallback.
- Repair a changed tunnel URL without rebuilding.
- Correct nominal/today-dollar labels and differing chart horizons.
- Larger text and accessible labels.
- Stretch: Link cancellation, partial imports, expired sessions.

Use focused decoding tests and a written device checklist; do not build a large UI-test framework.

## 13. Demo and definition of done

Three-minute sequence:

1. **0:00–0:20:** introduce same retirement date, different financial lives.
2. **0:20–0:50:** Jordan: strong reserves, full match, maintain contributions.
3. **0:50–1:25:** Morgan: same baseline allocation, preserve match, accelerate expensive debt.
4. **1:25–2:10:** Why sheet and debt/cash/retirement comparison.
5. **2:10–2:35:** retire-two-years-later preset or live scenario.
6. **2:35–3:00:** show the AI-selected priority order and structured decision summary; explain that Python computes and validates every amount.

Show Plaid afterward only if asked and working.

Prepare the physical phone, powered backend Mac, cable, hotspot, saved scenarios, and a local walkthrough video on two devices. Rehearse the entire offline path.

Developer 1 answers product/UI questions; Developer 2 answers iOS/offline questions.

**Frontend done:** the physical iPhone can explain the three profiles, instantly switch the same-retirement-date pair, compare outcomes, and repeat the core demonstration without network access.

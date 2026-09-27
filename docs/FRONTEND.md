# Adaptive Retirement Management (ARM) — Frontend Implementation Handoff

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
- No on-device LLM, trading, authentication accounts, or production bank credentials. AI calls run on the backend. The later educational chat addition is documented in [EDUCATION_CHAT.md](EDUCATION_CHAT.md).
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

Use a guided first-run setup followed by three tabs. Each tab has its own NavigationStack. Onboarding finishes in Explore, where the user first tries the dated playhead.

### Splash and onboarding material

[Figma splash](https://www.figma.com/design/G4MMU5TTVZzGmRvWTSC9cU/Fintech-investing-app?node-id=61-263)

Use the centered white Adaptive wordmark over an indigo/lavender glow that dissolves into charcoal at the screen edges. The splash includes subtle organic contour lines and fine grain behind the wordmark; see DESIGN.md for the editable vector and noise settings. Keep the current design static. Future implementation should support a gentle pulse and ripple in the contours and glow while the wordmark remains still, with a static Reduce Motion fallback. This motion must never extend startup time.

Carry the same anchored background into onboarding, fading out the wordmark and splash contours as a dark frosted system material and the setup content appear. Keep the background outside layout flow and behind all text, icons, and controls. Reuse it across every setup step and focus branch without restarting the background. Return to the existing charcoal surface on entering Explore.

The Figma material reference uses 48 px background blur, a 68% charcoal layer, and fine duotone grain; see DESIGN.md for shared colors and effects. Use the native material as the implementation baseline and verify contrast on device. Reduce Transparency substitutes an opaque charcoal surface; Reduce Motion uses a brief crossfade or immediate update. Decorative layers must not intercept touches or appear in VoiceOver. The prototype's 0.9-second hold and 550 ms transition demonstrate the handoff only: app startup must not impose an artificial minimum delay or replay the splash on Back navigation.

### Welcome and guided onboarding

[Figma entry](https://www.figma.com/design/G4MMU5TTVZzGmRvWTSC9cU/Fintech-investing-app?node-id=3-2) · [Four-step sequence](https://www.figma.com/design/G4MMU5TTVZzGmRvWTSC9cU/Fintech-investing-app?node-id=46-129)

Use four concise setup screens, following the user's simple profile / connection / suggestions reference. Each has one heading, one short instruction, one main action, and a visual that serves that step. The money river first appears in Explore.

1. **Profile:** show Morgan's avatar and name, “Try a sample financial life,” and **Continue with Morgan**. **Use my accounts** opens the separate connection preview. Keep the fictional-profile disclosure discreet and legible.
2. **Accounts:** move the same avatar into a simple dotted connection graphic beside an account icon. Show only three sample balances: retirement $35,000, cash $3,600, and credit card $18,000. Primary: **Use sample accounts**. Do not imply that a bank has been linked.
3. **Focus:** “Choose what you'd like to explore.” Three selectable rows introduce debt, a cash buffer, and retirement. This is a presentation choice, not a change to the financial planning preference or calculation. Default to debt for Morgan. Each choice has a working prototype state and a corresponding result.
4. **Next step:** expand the selected icon into the central visual and explain that part of the saved plan with one amount and brief context. Debt: $963.80 extra each month, $1,363.80 including the minimum. Cash: $3,600 saved, one month covered, next target three months. Retirement: $700 each month, comprising $350 employee and $350 employer contributions. Primary: **See it over time**.

Then open Explore with the river and a short **Drag to a date** hint. **Start exploring** dismisses it; seeking or playing also enters an existing dated state. Keep the river fixed when dismissing the hint. Figma's future dates are illustrative; the native lesson must use actual available projection data.

Keep primary actions in one stable location, offer Back, preserve the selected focus, and allow replay. No timed auto-advance or artificial loading. The earlier confirm-details and priorities lecture screens were removed from the sample walkthrough; canonical facts remain available through Financial Snapshot and Plan. All three focus paths show the same saved Balanced plan, not freshly calculated recommendations.

The **Use my accounts** branch explicitly says account linking is unavailable in this demo and offers sample data. In the native app, expose **Connect Sandbox accounts** only after its integration gate passes. A real import still requires source/date review and confirmation of missing or unconfirmed balances, elections, income, costs, matching rules, tax assumptions, retirement age, and planning preference. Do not infer these from bank balances or omit required confirmation merely to shorten the demo. Evaluate only a complete validated profile. Never substitute Morgan's result for connected data. Jordan and Casey remain in the profile picker; Connection Settings remains available for backend configuration.

#### Motion and continuity contract

Continuity belongs to persistent identities, not a river repeated on every setup screen. Preserve the same avatar in a common presentation layer: at the 393 × 852 reference size it moves from (140.5, 290, 112 × 112) on Profile to (44, 302, 80 × 80) on Accounts, then settles at (325, 69, 44 × 44) in the header. It remains there through the result and Explore. Derive these positions from layout at other sizes; support larger text without clipping controls.

- Profile → accounts and accounts → focus use 500 ms Smart Animate with cubic-bezier (0.77, 0, 0.175, 1). Keep the avatar identity stable while other content fades.
- Selecting a focus changes selection feedback in 180 ms. Continuing carries that exact icon from the row into an 80 pt central icon over 500 ms. Unselected rows fade out in 180 ms; the result fades in over 240 ms with at most 8 pt translation. Never animate monetary amounts through intermediate values.
- The avatar is stationary after reaching the header. Moving into Explore takes about 350 ms. Its river is introduced once and stays mounted while the hint is dismissed and the dated playhead is used.
- Back and rapid navigation retarget from the current presentation state; never lock controls during animation. The Explore scrubber follows the finger directly and pauses playback. Discrete navigation easing must not slow functional scrubbing.
- Reduce Motion removes translation and scale, using immediate updates or brief opacity changes. Keep every action available. Provide VoiceOver labels and month adjustment; avoid announcing every animation frame.

The Figma flow has linked selection states and a separate timeline study of the selected-icon transition. It is a design prototype, not a running SwiftUI implementation or proof of continuous scrubbing.

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

Lead with the approved **money river and dated playhead**. Place the existing comparison chart and scenario controls below it. The river shows the selected plan's monthly contribution take-home cost, emergency-savings allocation, additional debt payment, and any remaining cash. Keep employer matching separate from take-home cash; do not silently omit a nonzero remaining-cash allocation.

The playhead selects a calendar month from already calculated monthly results. Display month/year prominently, with plan milestones at their actual projected dates. Update the river and the selected retirement, cash, and debt balances together. Scrubbing is local presentation state: it must not submit a scenario, modify the recommendation, or trigger financial recalculation. Play advances through available months and stops at the end; dragging pauses playback. Respect Reduce Motion and provide accessible month-by-month adjustment. Reset or clamp the selected month when the profile or submitted scenario changes. Never extrapolate past a trajectory's retirement date.

The Figma prototype has three illustrative date states (Sep 2026, Sep 2028, Jan 2030) to demonstrate the interaction. Those dates and future ribbon widths are not forecasts and must not become hardcoded financial outputs. The current projection contract contains monthly balances but not monthly allocation amounts: the backend must expose its allocator's monthly cash flows and an explicit projection calendar anchor before a data-backed river can be implemented. Never infer allocation from differences in account balances, which also contain returns and interest. Preserve a clear unavailable state until these fields exist.

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
    OnboardingView
      SharedProfileIdentity
      ProfileStep
      AccountsStep
      FocusStep
      NextStep
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
        MoneyRiverView
        PlayheadLesson
        ScenarioControls
        PresetPicker
        ProjectionChart
        OutcomeCards
~~~

Use the current Geist typography and dark palette in DESIGN.md, with native control structure, open sections, and fine separators. Keep SF Symbols and system status text native. Distinguish chart series with labels and line style as well as color. Support larger text and VoiceOver.

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
- Onboarding step, selected presentation focus, draft source, completion state, and replay state. Changing a step or focus must not recalculate a plan or alter planning_preference.

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
  warnings: string[]   # this projection's own months; the top-level
                       # warnings cover state + the opening-month plan only

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

The backend runs on a teammate's Mac through an ngrok HTTPS tunnel on a fixed free domain. The iPhone must use the tunnel URL: its own localhost points to the phone.

Connection Settings allows editing the HTTPS base URL without rebuilding. Changing it resets live connection state but preserves bundled profiles. Do not add global App Transport Security exceptions.

The build-time default URL comes from `SERVER_BASE_URL` in `ios/Config/Server.xcconfig` (empty in the repo) via the git-ignored `Signing.local.xcconfig` on the demo host. The free tier has no uptime guarantee, so saved scenarios are mandatory. [ngrok docs](https://ngrok.com/docs)

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
- Onboarding Continue/Back, all three focus paths, replay, interruption during a morph, and Reduce Motion. Check avatar and selected-icon continuity, that the river first appears in Explore, and that hidden controls cannot receive taps.
- Stretch: Link cancellation, partial imports, expired sessions.

Use focused decoding tests and a written device checklist; do not build a large UI-test framework.

## 13. Demo and definition of done

Three-minute sequence:

1. **0:00–1:00:** take Morgan through the guided setup, reveal the first plan, and try one dated playhead interaction in Explore.
2. **1:00–1:30:** explain preserving the match while accelerating expensive debt; open Why and show the validated priority order and its supporting facts.
3. **1:30–2:00:** switch to Jordan to contrast the same retirement date with stronger reserves and different cash priorities.
4. **2:00–2:35:** compare the retire-two-years-later preset or a live scenario, including debt and cash alongside retirement.
5. **2:35–3:00:** show the structured decision summary; explain that Python computes and validates every amount. Distinguish the currently illustrative Figma river from actual generated results.

Show Plaid afterward only if asked and working.

Prepare the physical phone, powered backend Mac, cable, hotspot, saved scenarios, and a local walkthrough video on two devices. Rehearse the entire offline path.

Developer 1 answers product/UI questions; Developer 2 answers iOS/offline questions.

**Frontend done:** the physical iPhone can explain the three profiles, instantly switch the same-retirement-date pair, compare outcomes, and repeat the core demonstration without network access.

# Target Date Fund 2.0 — Personalized Glide Paths from Real Financial Data
### HackUMBC 2026 · UMBC · 24-hour build

**Target sponsor:** T. Rowe Price · also eligible for Best Fintech / Best Use of AI / Best Use of Plaid (confirm the real prize list at kickoff)

---

## The Idea

When you join a 401(k) and don't pick investments, you get defaulted into a **target-date fund**. It shifts you from stocks to bonds as retirement approaches, and the *only* input is your age.

Two 30-year-olds can be in completely different places. One has no debt and six months of savings. The other has $150K in student loans, a credit card at 25% APR and $500 in checking. Today both get the exact same portfolio because they share a birth year. The second person is maximizing market risk in their retirement account while a guaranteed 25% loss compounds on their card, and one car repair away from a 401(k) hardship withdrawal.

**Target Date Fund 2.0** connects to real accounts through **Plaid**, reads debts, rates, cash and cash flow, and bends the glide path to fit the person. It tells you what to prioritize (match, debt, emergency fund, contributions) and explains in plain English **why your strategy changed** whenever your finances do.

**Why this wins with T. Rowe Price:** target-date funds are their largest product line (~$553B). Their own published research says age-only is too crude and personalization is the next step. We show up with a working version built on their flagship product.

---

## The Pitch (say this to judges)

> "Every target-date fund asks one question: what year were you born? We ask what your bank accounts actually say. Target Date Fund 2.0 reads your real debts and savings through Plaid, adjusts your glide path within safe bounds, tells you whether your next dollar should go to your 401(k), your credit card or your emergency fund, and explains every change in plain English. The math is deterministic. The AI only reasons and explains."

**The differentiation is not robo-advice. It's personalizing the *default* product that tens of millions of people already hold.**
Robo-advisors score risk from a questionnaire. Budgeting apps show your debt but don't touch your retirement allocation. Nobody connects live balance-sheet data to a target-date glide path. That's the gap.

**Hard rule:** numbers never come from an LLM. Indicators, glide paths and projections are Python math with unit tests. Agents interpret those numbers, choose from bounded levers and explain.

---

## Grounded In

| Idea | How we use it |
|---|---|
| **Life-cycle investing and human capital** (Merton; Bodie, Merton & Samuelson) | Standard TDFs assume your future paycheck is a safe, bond-like asset. Heavy debt and no cash buffer make it riskier, so less equity risk is warranted near term. |
| **Debt vs. invest** | Paying a 24.9% APR card is a guaranteed 24.9% return. Beyond the employer match, no expected equity return beats it. |
| **401(k) leakage** | People without emergency savings raid retirement accounts through hardship withdrawals and loans. A cash buffer protects the glide path itself. |
| **T. Rowe Price's own personalization research** | Cite the exact paper or article in the pitch. **Find the link during hour 0.** |
| **Multi-agent reasoning over a shared state model** (the Skeptic / Strategist / Operator pattern) | Three agents read one deterministic state model instead of each computing its own numbers. |

---

## The Demo — Full Story (what judges see)

90 seconds end to end. Prep the two Plaid sandbox personas beforehand (see **Prep: Demo Personas**).

### Scene 1 — Same Age, Same Fund (10 sec)

Landing page, two cards side by side: **Maya, 30** and **Jordan, 30**. Both show "Retirement 2060 Fund" and an identical glide path chart.

> "Maya and Jordan are both 30. Their employer defaulted both into the 2060 target-date fund. Same age, same portfolio. That's how it works today."

### Scene 2 — Connect Real Accounts (15 sec)

Click **Connect accounts** on Jordan → Plaid Link opens (sandbox) → pick bank → accounts load:

```
Checking            $500
Credit card       $8,000   @ 24.9% APR
Student loans   $150,000   @ 6.8%
401(k)           $12,000   contributing 6% (4% match)
```

> "Jordan connects their accounts through Plaid. Now we can see what the fund has never seen."

### Scene 3 — The Financial State (20 sec) · **hero moment**

The **Indicator Dashboard** counts up, tile by tile:

```
Liquidity          0.2 months     🔴  one missed paycheck from a hardship withdrawal
Debt burden        30% DTI        🟡  $1,966/mo in minimum payments
Savings capacity   16% of take-home 🟡
Readiness          41% of target  🟡
Horizon            35 years       🟢
```

Maya's side fills in all green. The Financial State agent's one-line note sits under each red tile.

> "Five indicators, computed straight from Plaid data. No AI touched these numbers."

### Scene 4 — The Glide Paths Diverge (15 sec)

The chart animates. The standard path stays dashed. Jordan's line dips (less equity for the next few years while the cash buffer is thin). Maya's nudges slightly more aggressive. Hovering the gap shows the lever: `de_risk_for_thin_buffer: −10 pts until liquidity ≥ 3 months`.

**Priority Stack** slides in for Jordan:

```
1. Keep contributing 4% to capture the full employer match
2. Redirect the other 2% + $150/mo to the 24.9% card, on top of the minimum (paid off in ~19 months)
3. Build a 3-month emergency fund ($7,200)
4. Step contributions back up to 10%
```

> "Jordan isn't told to stop saving for retirement. They're told to keep the free match, kill the 25% debt first and build a buffer, and their fund takes less risk until that buffer exists."

### Scene 5 — Monte Carlo (10 sec)

Fan chart, 2,000 simulated paths: P10 / P50 / P90 balance at 65, standard vs personalized. The personalized P10 (bad-luck case) is higher because Jordan is far less likely to be forced to sell in a downturn.

> "Pure numpy. Same seed every run. The personalized plan mostly raises the bad-luck outcome."

### Scene 6 — "Why Did My Strategy Change?" (20 sec)

Flip the **"18 months later"** toggle: card paid off, $7,500 in savings. The graph re-runs, the tiles turn green, Jordan's glide path moves back toward the standard curve.

The **Why Panel** slides in:

> *"Your stock allocation rose from 77% to 87%. Your credit card is paid off, so the 24.9% guaranteed cost is gone, and your emergency fund now covers 3.1 months, so a surprise expense no longer threatens your 401(k). Your contributions return to 10%."*
>
> `Equity now: 77% → 87%` · `Liquidity: 0.2 → 3.1 months` · `Contribution: 4% → 10%`

> "The fund keeps adapting as your life changes, and it always tells you why."

**Spend the most time on scenes 3, 4 and 6.** The indicators, the diverging line and the plain-English "why" are what nobody else has.

| Scene | What judges see | ~Time |
|---|---|---|
| 1 | Two identical 2060 funds | 10s |
| 2 | Plaid Link, Jordan's accounts | 15s |
| 3 | Indicator dashboard (hero) | 20s |
| 4 | Glide paths diverge + priority stack | 15s |
| 5 | Monte Carlo fan | 10s |
| 6 | 18-months-later toggle + Why Panel | 20s |

---

## Tech Stack

| Component | Technology |
|---|---|
| Financial data | **Plaid** sandbox: `auth` (balances), `liabilities`, `transactions` |
| Agents | **LangGraph** + `langchain-anthropic` |
| Agent models | **Claude Sonnet 5** (recommendation), **Claude Haiku 4.5** (state + explanation) |
| Math + simulation | Python, **numpy**, Pydantic, pytest |
| Backend | **FastAPI** + SSE, deployed on **Railway** |
| Frontend | **Next.js** (App Router) + Tailwind + shadcn/ui + **Recharts** + framer-motion + `react-plaid-link`, deployed on **Vercel** |
| Persistence | In-memory dict + JSON fixtures (no DB needed for a demo). SQLite if time allows. |

---

## Models

| Role | Model | Why |
|---|---|---|
| **Financial State agent** | Claude Haiku 4.5 `claude-haiku-4-5-20251001` | Fast. Annotates numbers math already computed. |
| **Recommendation agent** | Claude Sonnet 5 `claude-sonnet-5` | The one judgement-heavy step. Structured output. |
| **Explanation agent** | Claude Haiku 4.5 | Short plain-English narrative from a before/after diff. |
| **Simulation** | **None. numpy.** | Never route projections through a language model. |

One AI key: `ANTHROPIC_API_KEY`. Plaid: `PLAID_CLIENT_ID` + `PLAID_SECRET`.

---

## Architecture

```
            Plaid (sandbox)                    Retirement inputs
   balances · liabilities · transactions    age, salary, 401(k), contrib %, match
                  │                                   │
                  └─────────────────┬─────────────────┘
                   ┌────────────────▼────────────────┐
                   │      TDF Graph (LangGraph)       │   ← Person 2
                   │                                  │
                   │  plaid_ingest                    │   ← Person 1 · Plaid → FinancialProfile
                   │       ↓                          │
                   │  compute_indicators       MATH   │   ← Person 1 · indicators.py
                   │       ↓                          │
                   │  financial_state          LLM    │   ← Haiku: interpret, flag risks
                   │       ↓                          │
                   │  recommendation           LLM    │   ← Sonnet: priorities + levers
                   │       ↓                          │
                   │  apply_glide_path         MATH   │   ← Person 1 · glide.py (clamped)
                   │       ↓                          │
                   │  simulate                 MATH   │   ← Person 1 · simulate.py
                   │       ↓                          │
                   │  explanation              LLM    │   ← Haiku: "why did it change"
                   └────────────────┬─────────────────┘
                                    │  SSE stream
                   ┌────────────────▼─────────────────┐
                   │   Next.js frontend (Vercel)       │   ← Person 3 + 4
                   │ personas · indicators · glide ·   │
                   │ priorities · fan · why panel      │
                   └───────────────────────────────────┘
```

**Guardrail:** the Recommendation agent never outputs allocation percentages. It chooses from a fixed set of **levers**, each with a bounded effect. `glide.py` turns levers into numbers and clamps equity to `[baseline − 15, baseline + 5]` percentage points. Invalid lever names are rejected and retried once, then fall back to the rules-only plan.

### Graph State

```python
class TDFState(TypedDict):
    # Input
    profile_id: str
    run_id: str
    previous_run_id: str | None          # set by /scenario for before/after

    # plaid_ingest
    profile: FinancialProfile

    # compute_indicators (math)
    indicators: Indicators               # value + band per indicator

    # financial_state (LLM)
    state_summary: str
    risk_flags: list[RiskFlag]

    # recommendation (LLM, structured)
    recommendation: Recommendation       # priorities, levers, contribution_plan, reasoning_trace

    # apply_glide_path (math)
    baseline_path: list[GlidePoint]
    personalized_path: list[GlidePoint]  # each point carries the lever(s) that moved it

    # simulate (math)
    simulation: SimulationResult         # closed form + P10/P50/P90 for both paths

    # explanation (LLM)
    explanation: Explanation             # narrative + changed numbers

    # stream log for frontend
    events: Annotated[list[dict], operator.add]
```

### Levers (the only things the Recommendation agent can choose)

| Lever | Effect (applied by `glide.py`) | Triggered when |
|---|---|---|
| `capture_full_match` | contribution never drops below the match | always considered first |
| `redirect_to_high_apr_debt` | contribution above match → debt until APR>8% balances are paid | any debt with APR > 8% |
| `build_emergency_fund` | route part of pay to cash until 3 months | liquidity < 3 months |
| `de_risk_for_thin_buffer` | −10 equity pts (−5 if horizon < 10y) while liquidity < 3 months | liquidity < 3 months |
| `de_risk_for_debt_load` | −5 equity pts while DTI > 36% | debt burden red |
| `increase_risk_capacity` | +5 equity pts | all indicators green and horizon > 20y |

---

## The Adaptive Loop ("why did my strategy change")

Every run is stored. When finances change, the graph re-runs and the Explanation agent sees both states:

1. A change comes in: the "18 months later" toggle in the demo, a manual what-if, or a Plaid webhook replay (stretch)
2. `POST /scenario` applies the change to the profile and starts a new run with `previous_run_id`
3. Math recomputes indicators, levers and the path
4. The Explanation agent gets `{before, after, reasoning_trace}` and must quote numbers from the diff, never invent them
5. The frontend animates old → new and shows the Why Panel

This is the equivalent of a quarterly re-underwriting that today's target-date funds never do.

---

## Scaffold (create in TheCoderrrrr/HackUMBC)

```
backend/
├── main.py                   FastAPI app, all endpoints, SSE          ← Person 2
├── requirements.txt          fastapi uvicorn langgraph langchain-anthropic plaid-python numpy pydantic pytest
├── .env.example
├── seed_personas.py          creates Maya + Jordan sandbox users, writes fixtures/   ← Person 1
├── fixtures/                 maya.json, jordan.json, jordan_18mo.json (stage fallback)
├── plaid_client/                                                        ← Person 1
│   ├── link.py               create_link_token, exchange_public_token
│   └── ingest.py             balances, liabilities, transactions → FinancialProfile
├── finance/                  NO LLM IMPORTS IN THIS FOLDER             ← Person 1
│   ├── models.py             FinancialProfile, Indicators, GlidePoint, SimulationResult
│   ├── indicators.py
│   ├── glide.py              baseline curve, LEVERS, clamps
│   ├── simulate.py           closed-form FV + Monte Carlo
│   └── test_finance.py
└── graphs/                                                              ← Person 2
    ├── state.py              TDFState
    ├── tdf_graph.py          7-node graph
    ├── prompts.py            3 system prompts
    └── sse.py                event queue + formatting

frontend/                                                                ← Person 3 + 4
└── src/
    ├── app/
    │   ├── page.tsx                    Maya vs Jordan comparison (P3)
    │   ├── profile/[id]/page.tsx       single-persona deep dive (P4)
    │   └── api/[...path]/route.ts      proxy to Railway (P4)
    ├── hooks/useTDFStream.ts           (P4)
    ├── mocks/                          maya.json, jordan.json, jordan_18mo.json (P4)
    └── components/tdf/
        ├── PersonaCard.tsx             (P3)
        ├── IndicatorDashboard.tsx      (P3)
        ├── GlidePathChart.tsx          (P3)
        ├── MonteCarloFan.tsx           (P3)
        ├── PlaidConnectButton.tsx      (P4)
        ├── PipelineSteps.tsx           (P4)
        ├── PriorityStack.tsx           (P4)
        ├── ScenarioToggle.tsx          (P4)
        └── WhyPanel.tsx                (P4)
```

---

# BACKEND

## Person 1 — Plaid + Financial Math + Simulation

**Goal:** Turn Plaid data into a clean `FinancialProfile`, then compute every number in the demo with tested, deterministic Python.

### Files to work in
```
backend/plaid_client/   backend/finance/   backend/seed_personas.py   backend/fixtures/
```

### Tasks

**Hours 0–4 — Plaid + personas**

- [ ] Plaid dashboard signup, sandbox keys into `.env`, share with Person 2
- [ ] `link.py`: `create_link_token(user_id)` and `exchange_public_token(public_token)`
  ```bash
  python3 -c "from plaid_client.link import create_link_token; print(create_link_token('demo'))"
  ```
- [ ] Create Maya and Jordan as **custom sandbox users** (`user_custom` + JSON config with accounts and liabilities) so the numbers are exactly what the story needs
- [ ] `ingest.py` → `FinancialProfile`:
  ```python
  class Debt(BaseModel):
      kind: Literal["credit_card", "student_loan", "mortgage", "other"]
      balance: float
      apr: float          # /liabilities/get; credit cards: purchase APR
      min_payment: float

  class FinancialProfile(BaseModel):
      age: int
      retirement_age: int = 65
      annual_income: float
      monthly_take_home: float         # payroll deposits in transactions
      liquid_savings: float            # depository balances
      monthly_essential_spend: float   # 90 days of transactions, essential categories
      debts: list[Debt]
      retirement_balance: float
      contribution_rate: float
      employer_match_rate: float
  ```
  Retirement inputs (age, salary, 401(k), match) come from a small form or the persona config, since Plaid sandbox won't give a realistic 401(k)
- [ ] `seed_personas.py` writes `fixtures/maya.json`, `jordan.json`, `jordan_18mo.json`. **Every endpoint must work from fixtures alone** (stage fallback)

**Hours 4–10 — The math**

- [ ] `indicators.py` — pure functions, each returns `{value, unit, band}`:
  ```python
  horizon          = retirement_age - age
  liquidity        = liquid_savings / monthly_essential_spend            # red < 1, amber < 3
  debt_burden      = sum(min_payments) * 12 / annual_income              # red > 0.36, amber > 0.20
  high_apr_debt    = sum(balance for debts with apr > 0.08)
  savings_capacity = (take_home - essential - debt_payments) / take_home  # red < 5%, amber < 20%
  readiness        = simulate.closed_form(profile, baseline)[-1] / (10 * annual_income)
  ```
- [ ] `glide.py`:
  - `baseline(age, retirement_age)` → equity share per year: ~98% at 40+ years out, ~90% at 25, ~55% at 0, ~30% at 30 years past. Linear interpolation. **An approximation of a typical TDF curve, not official T. Rowe Price data.**
  - `apply(baseline, levers, profile)` → personalized path; each point records which levers moved it; clamp to `[baseline − 15, baseline + 5]`, cap at 100
  - De-risk levers apply only to the years until the condition is projected to clear (use the contribution plan to project when the card is paid and buffer reaches 3 months)
- [ ] `simulate.py`:
  - `closed_form(profile, path)` → yearly balance with contributions and blended expected return
  - `monte_carlo(profile, path, n=2000, seed=42)` → stocks μ 7% σ 16%, bonds μ 3.5% σ 6%, ρ 0.1, lognormal; returns P10/P50/P90 per year
  - Model the downside: in paths where a shock hits (e.g. 10% yearly chance of a 2-month expense) and liquidity < shock, withdraw from the 401(k) with a 10% penalty. This is what makes the personalized P10 higher.
- [ ] `test_finance.py`:
  - Jordan liquidity red and debt burden amber, Maya all green
  - Clamp never exceeds bounds
  - MC P50 within 5% of closed form when shocks are off
  - Same seed → identical output

**Hours 10–14 — Support Person 2**

- [ ] `GET /baseline-glide` and `GET /profiles/{id}` helpers
- [ ] Scenario application: `apply_change(profile, change)` for `pay_off`, `add_savings`, `salary_change`, `months_forward`
- [ ] Pair with Person 2 on the first end-to-end run

**Deliverable:** `pytest finance/` green, and `FinancialProfile → indicators → path → simulation` in under 1 second from fixtures.

---

## Person 2 — Agents + Orchestration + API

**Goal:** The LangGraph graph, three agent prompts, the SSE stream and every FastAPI endpoint. Owns the backend deploy.

### Files to work in
```
backend/graphs/   backend/main.py
```

### Tasks

**Hours 0–4 — Skeleton + contract**

- [ ] FastAPI app with `/health`, CORS for `FRONTEND_ORIGIN`
- [ ] **Lock the API contract and SSE events with Person 4 in the first hour** (see below)
- [ ] Stub every endpoint to return fixture data so frontend can integrate on day one
- [ ] `sse.py`: asyncio queue per run; each node pushes `node_start` / `node_done`

**Hours 4–10 — Graph + agents**

- [ ] `tdf_graph.py`, 7 nodes in order. Math nodes call Person 1's functions directly; use stubs until they land.
- [ ] **Financial State agent** (Haiku): input = indicators JSON. Output `{summary, risk_flags: [{indicator, note}]}`. Prompt forbids changing or inventing numbers.
- [ ] **Recommendation agent** (Sonnet, `with_structured_output`):
  ```python
  class Priority(BaseModel):
      rank: int
      action: str        # "Pay off credit card"
      target: str        # "$8,000 @ 24.9%"
      rationale: str

  class Recommendation(BaseModel):
      priorities: list[Priority]
      levers: list[LeverName]              # Literal of LEVERS keys
      contribution_plan: dict[str, float]  # {"retirement": .04, "debt": .06, "cash": .02} of pay
      reasoning_trace: list[str]
  ```
  Validate: levers ⊂ LEVERS, `contribution_plan["retirement"] >= employer_match_rate`. Retry once, then use `rules_only_recommendation(indicators)` (write this first, it's also the demo fallback).
- [ ] **Explanation agent** (Haiku): input `{before, after, reasoning_trace}`. Output `{narrative (2–4 sentences), changes: [{label, before, after}]}`. `changes` is computed in Python from the diff; the LLM writes only the narrative. First run (no `before`): explain why the path differs from baseline.

**Hours 10–14 — Endpoints + scenario loop**

- [ ] `/plaid/link-token`, `/plaid/exchange`, `/runs`, `/runs/stream`, `/scenario` (see contract)
- [ ] Store each run in a dict by `run_id`; `/scenario` passes the previous run as `before`
- [ ] Pre-warm: on startup, run both personas once from fixtures and cache so the stage run is instant if the LLM is slow

**Hours 14–16 — Deploy**

- [ ] Railway deploy, env vars, `curl https://<railway>/health`
- [ ] Confirm the SSE stream isn't buffered through the Vercel proxy (send `X-Accel-Buffering: no`, flush per event)

**Deliverable:** `/runs/stream?profile_id=jordan` emits every event in the contract, live and from fixtures, on Railway.

---

# FRONTEND

## Person 3 — Hero Views: Comparison, Indicators, Charts

**Goal:** The screens judges remember. Scenes 1, 3, 4 and 5.

### Base
```bash
npx create-next-app@latest frontend --ts --tailwind --app
cd frontend && npx shadcn@latest init
npx shadcn@latest add card badge button tabs sheet progress tooltip
npm i recharts framer-motion
```

### Tasks

**Hours 0–4 — Layout from mocks**

- [ ] `/` page: two columns (Maya | Jordan). Header: **"Same age. Same fund. Different lives."**
- [ ] `PersonaCard.tsx`: name, age, "Retirement 2060 Fund", salary, Connect button slot (Person 4's component)
- [ ] `GlidePathChart.tsx` v1: baseline only, from `mocks/*.json`

**Hours 4–10 — Hero components**

- [ ] **`IndicatorDashboard.tsx`** (spend the most time here):
  - 5 tiles: Liquidity (months) · Debt burden (DTI %) · Savings capacity (%) · Readiness (%) · Horizon (yrs)
  - Big number, band color (green/amber/red), one-line note from `risk_flags`
  - Count up from 0 with 120ms stagger when `compute_indicators` arrives
- [ ] **`GlidePathChart.tsx`** v2 (Recharts `ComposedChart`):
  - X = age 30 → 95, Y = equity %
  - Baseline dashed grey, personalized solid accent; animate the morph
  - Shaded area between them; tooltip names the lever(s) for that year
  - Retirement-age reference line
- [ ] **`MonteCarloFan.tsx`** (Recharts `AreaChart`): P10–P90 band + P50 line; toggle standard / personalized / both; label P10 at 65 for both

**Hours 10–16 — Live data + polish**

- [ ] Wire all three to `useTDFStream` (Person 4)
- [ ] Before/after animation: when a scenario run arrives, animate from the previous values, not from 0
- [ ] Responsive at projector resolution (1920×1080 and 1280×720)

**Design principles**
- Light, clean, "financial institution" look; one accent color
- Red/amber/green only for indicator bands
- Numbers readable from the back of the room (tiles ≥ 40px)
- Subtle motion only: count-ups, line morphs, slide-ins

**Deliverable:** Scenes 1, 3, 4, 5 look finished from mocks by hour 10 and from live data by hour 16.

---

## Person 4 — Demo Flow: Plaid Link, Stream, Priorities, Why Panel

**Goal:** Everything that moves the story forward. Scenes 2, 4 (priorities) and 6, plus the data plumbing Person 3 builds on.

### Tasks

**Hours 0–4 — Plumbing**

- [ ] Lock the API contract with Person 2 in hour 1
- [ ] `mocks/maya.json`, `jordan.json`, `jordan_18mo.json`: full event sequences matching the SSE contract (Person 3 depends on these)
- [ ] `app/api/[...path]/route.ts`: proxy to `BACKEND_URL` that streams SSE through
- [ ] `useTDFStream.ts` with a mock mode (`?demo=1` replays mock events with realistic delays):
  ```typescript
  export function useTDFStream(profileId: string | null, runId: string | null) {
    const [nodeStatuses, setNodeStatuses] = useState<Record<string, 'idle'|'running'|'done'>>({})
    const [indicators, setIndicators] = useState<Indicators | null>(null)
    const [stateSummary, setStateSummary] = useState<StateSummary | null>(null)
    const [recommendation, setRecommendation] = useState<Recommendation | null>(null)
    const [glidePath, setGlidePath] = useState<GlidePath | null>(null)
    const [simulation, setSimulation] = useState<Simulation | null>(null)
    const [explanation, setExplanation] = useState<Explanation | null>(null)

    useEffect(() => {
      if (!profileId || !runId) return
      const es = new EventSource(`/api/runs/stream?profile_id=${profileId}&run_id=${runId}`)
      es.onmessage = (e) => {
        const ev = JSON.parse(e.data)
        if (ev.event === 'node_start') setNodeStatuses(s => ({ ...s, [ev.node]: 'running' }))
        if (ev.event === 'node_done') {
          setNodeStatuses(s => ({ ...s, [ev.node]: 'done' }))
          if (ev.node === 'compute_indicators') setIndicators(ev.data)
          if (ev.node === 'financial_state')    setStateSummary(ev.data)
          if (ev.node === 'recommendation')     setRecommendation(ev.data)
          if (ev.node === 'apply_glide_path')   setGlidePath(ev.data)
          if (ev.node === 'simulate')           setSimulation(ev.data)
          if (ev.node === 'explanation')        setExplanation(ev.data)
        }
        if (ev.event === 'complete') es.close()
      }
      return () => es.close()
    }, [profileId, runId])

    return { nodeStatuses, indicators, stateSummary, recommendation, glidePath, simulation, explanation }
  }
  ```

**Hours 4–10 — Flow components**

- [ ] **`PlaidConnectButton.tsx`** (`npm i react-plaid-link`): `GET /api/plaid/link-token` → `usePlaidLink` → `POST /api/plaid/exchange` → `POST /api/runs` → start stream. Small "Use demo data" link beside it.
- [ ] **`PipelineSteps.tsx`**: `Accounts linked → Indicators → State assessed → Priorities → Glide path → Simulated → Explained`, driven by `nodeStatuses`
- [ ] **`PriorityStack.tsx`**: numbered cards (action, target, rationale), 150ms stagger; "Why?" expander shows `reasoning_trace`

**Hours 10–16 — Scene 6 + deep-dive page**

- [ ] **`ScenarioToggle.tsx`**: "Today" ↔ "18 months later" → `POST /api/scenario` → new `run_id` → stream
- [ ] **`WhyPanel.tsx`**: narrative in large type + `changes` list as `label: before → after` chips; slides in from the right
- [ ] `/profile/[id]` page: one persona full-width with every component, used for Q&A deep dives
- [ ] Footer disclaimer: *"Educational demo. Not investment advice. Plaid sandbox data."*

**Hours 16–18 — Deploy**

- [ ] Vercel deploy, `BACKEND_URL` set, full run on the deployed URL
- [ ] `?demo=1` works with the backend turned off

**Deliverable:** Full demo clickable end to end, live and in `?demo=1` mode.

---

## Prep: Demo Personas (Person 1, first thing)

| | **Maya** | **Jordan (today)** | **Jordan (18 months later)** |
|---|---|---|---|
| Age / retire at | 30 / 65 | 30 / 65 | 31.5 / 65 |
| Salary | $85,000 | $78,000 | $80,000 |
| Checking + savings | $24,000 | $500 | $7,500 |
| Monthly take-home | $5,600 | $5,200 | $5,300 |
| Monthly essentials | $3,200 | $2,400 | $2,400 |
| Credit card | $0 | $8,000 @ 24.9% | $0 |
| Student loans | $0 | $150,000 @ 6.8% | $141,000 @ 6.8% |
| 401(k) balance / contrib / match | $40K / 10% / 4% | $12K / 6% / 4% | $15K / 10% / 4% |

**Expected outputs.** The scene script's numbers are targets. Readiness and Monte Carlo figures are placeholders: once `finance/` runs, replace every number in the script with the real output.

- Jordan today: liquidity red (0.2 mo), debt burden amber (30%), `de_risk_for_thin_buffer` + `redirect_to_high_apr_debt` + `build_emergency_fund` + `capture_full_match`
- Jordan 18 months: liquidity 3.1 months, card gone, equity back up by ~10 pts
- Maya: all green, `increase_risk_capacity`

---

## API Contracts (lock in hour 1)

```
# Person 2 exposes (backed by Person 1's functions)
GET  /health
GET  /personas                 → [{id, name, age, fund_year, connected}]
GET  /plaid/link-token         → ?persona_id= → {link_token}
POST /plaid/exchange           → {persona_id, public_token} → {profile_id}
GET  /profiles/{id}            → FinancialProfile
POST /runs                     → {profile_id} → {run_id}
GET  /runs/{run_id}            → full TDFState (debug + Q&A)
GET  /runs/stream              → ?profile_id=&run_id= → SSE
POST /scenario                 → {profile_id, previous_run_id, change: {months_forward?, pay_off?, add_savings?, salary_change?}} → {run_id}
GET  /baseline-glide           → ?age=&retirement_age= → [{age, equity}]
```

```jsonc
// SSE events (Person 2 emits, Person 3 + 4 consume)
{"event": "node_start", "node": "plaid_ingest",       "data": null}
{"event": "node_done",  "node": "plaid_ingest",       "data": {"accounts": 4, "debts": 2}}
{"event": "node_done",  "node": "compute_indicators", "data": {
  "liquidity":        {"value": 0.2,  "unit": "months", "band": "red"},
  "debt_burden":      {"value": 0.30, "unit": "ratio",  "band": "amber"},
  "savings_capacity": {"value": 0.16, "unit": "ratio",  "band": "amber"},
  "readiness":        {"value": 0.41, "unit": "ratio",  "band": "amber"},
  "horizon":          {"value": 35,   "unit": "years",  "band": "green"}}}
{"event": "node_done",  "node": "financial_state",    "data": {"summary": "...", "risk_flags": [{"indicator": "liquidity", "note": "..."}]}}
{"event": "node_done",  "node": "recommendation",     "data": {"priorities": [{"rank": 1, "action": "...", "target": "...", "rationale": "..."}], "levers": ["capture_full_match", "redirect_to_high_apr_debt"], "contribution_plan": {"retirement": 0.04, "debt": 0.02, "cash": 0.0}, "reasoning_trace": ["..."]}}
{"event": "node_done",  "node": "apply_glide_path",   "data": {"baseline": [{"age": 30, "equity": 0.97}], "personalized": [{"age": 30, "equity": 0.87, "levers": ["de_risk_for_thin_buffer"]}]}}
{"event": "node_done",  "node": "simulate",           "data": {"closed_form_at_retirement": 0, "baseline": {"p10": [], "p50": [], "p90": []}, "personalized": {"p10": [], "p50": [], "p90": []}}}
{"event": "node_done",  "node": "explanation",        "data": {"narrative": "...", "changes": [{"label": "Equity now", "before": 0.77, "after": 0.87}]}}
{"event": "complete",   "data": {"run_id": "..."}}
```

---

## Timeline (24 hours)

Hour 0 = hacking starts. Shift to match the real HackUMBC schedule.

| Hour | Person 1 (Plaid + math) | Person 2 (agents + API) | Person 3 (hero views) | Person 4 (flow + stream) |
|---|---|---|---|---|
| **0–1** | Plaid keys, sandbox up | Repo scaffold, **lock API contract** | Next.js + shadcn + Recharts | **Lock API contract**, write mocks |
| **1–4** | Personas + `ingest.py` + fixtures | Stub endpoints from fixtures, SSE queue | `/` layout, `PersonaCard`, baseline chart | Proxy route, `useTDFStream` + mock mode |
| **4** | ✅ **Checkpoint:** both personas → `FinancialProfile` · stubs serve fixtures · comparison page renders · mock stream replays |||
| **4–10** | `indicators.py`, `glide.py`, `simulate.py`, tests | Graph + 3 prompts + `rules_only_recommendation` | `IndicatorDashboard`, `GlidePathChart` v2, `MonteCarloFan` | `PlaidConnectButton`, `PipelineSteps`, `PriorityStack` |
| **10** | ✅ **Checkpoint:** `pytest` green · live graph emits every event for Jordan · hero views finished from mocks · Plaid Link returns a token |||
| **10–14** | Scenario `apply_change`, pair on first live run | Endpoints + `/scenario` loop + pre-warm cache | Wire to live stream, before/after animation | `ScenarioToggle`, `WhyPanel`, `/profile/[id]` |
| **14** | ✅ **Checkpoint: full demo runs end to end locally, live data** |||
| **14–16** | Tune personas until expected outputs match | Railway deploy, SSE through proxy | Projector-resolution polish | Vercel deploy, `?demo=1` with backend off |
| **16–20** | **Sleep in shifts** (two people at a time; one backend + one frontend always awake) ||||
| **20–22** | **Full demo run × 3**, fix bugs, lock seeds and prompts |||
| **22–23** | Record 90-sec video, screenshots | Devpost write-up | Final UI fixes | Final deploy check on venue Wi-Fi |
| **23–24** | **Submit Devpost.** Rehearse the pitch and Q&A. ||||

**Rule:** anything not working by hour 14 gets cut or faked from fixtures. No new features after hour 20.

---

## Demo-Day Fallbacks

| If this breaks | Do this |
|---|---|
| Plaid sandbox / Link | "Use demo data" link → loads fixtures, same flow |
| Anthropic API slow or down | Pre-warmed cached runs; `rules_only_recommendation` + template explanation |
| Railway | `?demo=1` replays mock events entirely in the browser |
| Venue Wi-Fi | Phone hotspot; worst case, the recorded video |

---

## Judge Q&A (prep answers)

- **"Isn't this financial advice?"** It's a demo of how a fund provider could personalize a default product. Real deployment would sit inside a registered provider's compliance process. Every change is bounded and explained.
- **"Why not just let the LLM pick the allocation?"** Because numbers must be reproducible and auditable. The LLM picks from six bounded levers; math does the rest.
- **"Why lower equity for someone young?"** Not less saving: less *forced selling*. Without a cash buffer, a downturn plus an emergency means selling low with a 10% penalty. The Monte Carlo P10 shows it.
- **"How does this fit T. Rowe Price?"** It's a personalization layer on top of their existing glide paths, not a new fund. Levers adjust their curve within ±15 pts.
- **"Privacy?"** Plaid tokens stay server-side; only derived indicators reach the agents.

---

## Setup

```bash
# Backend
cd backend
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # fill in keys
python seed_personas.py     # Maya + Jordan → fixtures/
pytest finance/
uvicorn main:app --port 8000 --reload

# Frontend
cd frontend
npm install
echo "BACKEND_URL=http://localhost:8000" > .env.local
npm run dev                 # localhost:3000  (add ?demo=1 for offline mode)
```

---

## Environment Variables

```bash
# backend/.env
ANTHROPIC_API_KEY=sk-ant-...        # all three agents
PLAID_CLIENT_ID=...
PLAID_SECRET=...                    # sandbox secret
PLAID_ENV=sandbox
FRONTEND_ORIGIN=http://localhost:3000

# frontend/.env.local
BACKEND_URL=http://localhost:8000   # Railway URL in prod
```

---

## What Makes This Win

1. **Sponsor fit** — personalizes T. Rowe Price's largest product, the thing their own research says needs personalizing
2. **Real data** — live Plaid connection, not a questionnaire
3. **Visible reasoning** — judges watch indicators compute, the path bend and the "why" appear
4. **Trustworthy AI** — math is deterministic and tested; agents choose bounded levers and explain, never invent numbers
5. **Adapts over time** — the 18-months-later toggle shows the fund re-underwriting you as life changes
6. **Story arc** — two identical 30-year-olds, two different lives, two different funds, in 90 seconds

---

## Stretch Goals (only if the hour-14 checkpoint passed)

- [ ] **Plaid webhook replay** (P1 + P2): simulated `LIABILITIES` / `TRANSACTIONS` webhook triggers the re-run instead of the toggle
- [ ] **Slider sandbox** (P3): drag savings / APR / salary and watch the path respond live (math-only path, debounced, no agents)
- [ ] **Cohort view** (P3): 100 synthetic 30-year-olds, one baseline line vs a spread of personalized lines
- [ ] **Ask your fund** (P2 + P4): chat box that answers "what if I buy a car?" by running a scenario and explaining it
- [ ] **Advisor export** (P2): PDF of indicators, recommendation and reasoning trace

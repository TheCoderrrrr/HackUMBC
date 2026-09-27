# Adaptive Retirement Management (ARM): desktop web app

A React + TypeScript + Vite version of the iOS app (same palette and Geist type), organized so a first-time user always knows where they are. Every figure comes from the profile or an engine response; the app does no financial calculation of its own.

## Run

```bash
# 1. Backend (from backend/)
uvicorn app.main:app --host 127.0.0.1 --port 8000

# 2. Desktop app (from desktop/)
npm install
npm run dev          # http://localhost:5173
npm test             # Vitest suite
npm run build        # typecheck + production build
```

The Vite dev server forwards `/api/*` to the backend, so the backend needs no CORS changes. To use a remote backend (for example the ngrok domain), set `BACKEND_URL` before starting:

```powershell
$env:BACKEND_URL="https://coral-sandbox-apron.ngrok-free.dev"; npm run dev
```

If the backend sets `DEMO_KEY`, set the same value in the desktop env so the Vite proxy can add `X-Demo-Key`. The key stays on the proxy and is not bundled into the browser.

## Pages

| Group | Page | What it does |
|---|---|---|
| Your money | **Overview** | Next step, three at-a-glance tiles that open their Plan tab, where you're heading, a first-steps checklist, collapsible details |
| Your money | **Your plan** | An always-visible projection, then one topic per tab (This month, Saving, Debt, Emergency fund, Your fund, Plan style), a milestones rail, and a **Why this matters** drawer per section |
| Plan ahead | **Explore** | Scenario controls, plus tabs for Compare, Timeline and Saved runs (Tiger Data: save, compare, delete) |
| Plan ahead | **Fund shortlist** | Target-date fund ranking from the reviewed catalog ([FUNDS.md](FUNDS.md)) |
| Learn | **Learn** | Six short lessons; **Try** applies each one to your numbers (a scenario in Explore or a plan style) |
| Learn | **Getting started** | Five-page guide: welcome, how ARM decides, three key ideas, choose a plan style, where to find things. Opens on first visit per profile |

- **Your people** (sidebar → *Add a person*, up to 10): a five-part form (about you, income and spending, savings, employer match, debts) in dollars and percents. The engine previews what it sees as you type (monthly budget after essentials, emergency months, rate for the full match, high-interest debt), and server errors highlight the exact field. Saving stores the numbers in Tiger Data under an anonymous key kept in this browser; each person then works like a demo profile, including private saved plans. The sidebar lists them under *Your people · n/10* with an edit button each, and the list scrolls. *Start from Morgan's numbers* pre-fills the form for demos, and *Erase* removes that person and only their plans.
- **Ask** (bottom right) opens the education chat ([EDUCATION_CHAT.md](EDUCATION_CHAT.md)).
- **Key terms** carry a **?** popover. Definitions that quote numbers read them from the engine's `assumptions`.

## Projection chart (Your plan)

- **Two lines:** your plan and current habits, with the difference shaded and shown as a gap at the selected age.
- **Pinning:** hover to preview, click (or drag the slider) to pin an age.
- **Goal line:** suggested round amounts or a typed one (`1.2m`, `800k`), with a dot where each line reaches it and "N years sooner". The goal is remembered per profile in this browser.
- **Milestones:** debt cleared and emergency fund full; milestones in the same year share a label.
- **Where the logic lives:** `src/data/chart.ts`. It compares and searches engine values only. Yearly values are the engine's points at months 0, 12, 24…, the same rule as the backend's `/v1/plan-styles` and the Tiger continuous aggregate.

## Plan styles

Balanced, Cash security first and Debt payoff first are compared with `POST /v1/plan-styles`: each style's own rule order through the engine, with no AI call. The priority order shown in the guide comes from that response, not from frontend copy. When the live AI chooses a different order than the chosen style, Your plan says so.

## Data and efficiency

- **Saved results** show immediately: the offline bundle in `ios/AdaptiveRetirement/Resources/Demo/` when it exists, otherwise the real engine responses in `contracts/examples/`. Each saved result is its own chunk, loaded the first time it's needed.
- **Live results** replace them when "Live calculation" is on and the backend answers. Failures keep the previous result, labelled "Last live" or "Saved".
- **Code splitting:** Explore, Funds, Learn and Chat load on demand. The first download is 264 KB (80 KB gzipped), down from 1,126 KB.

## Tests (`npm test`)

| File | Covers |
|---|---|
| `src/api/contract.test.ts` | 14 API schemas in `contracts/openapi.json` match the TypeScript types field for field |
| `src/api/client.test.ts` | Error envelopes, unreachable backend, `204 No Content` |
| `src/data/chart.test.ts` | Chart math: gap, goal reach, years sooner, presets, axis ticks, goal parsing, labels, milestones |
| `src/data/display.test.ts` | Sync on real engine output: yearly sampling, chart end = retirement figure, gap = engine totals |
| `src/data/numbers.test.ts` | Form ↔ API conversion (Morgan round-trips exactly), missing fields, error-path mapping, key format |
| `src/data/live.test.ts` | Opt-in, against a running backend: `ARM_API=http://127.0.0.1:8000 npx vitest run src/data/live.test.ts` |

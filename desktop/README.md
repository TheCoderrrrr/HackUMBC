# Adaptive Retirement Management (ARM): desktop web app

A desktop version of the iOS app (same palette, Geist type, Overview / Your plan / Explore, and the "Why this plan?", snapshot and assumptions panels), for testing on a laptop.

## Run

```bash
# 1. Backend (from backend/)
uvicorn app.main:app --host 127.0.0.1 --port 8000

# 2. Desktop app (from desktop/)
npm install
npm run dev
# open http://localhost:5173
```

The Vite dev server forwards `/api/*` to the backend, so the backend needs no CORS changes. To use a remote backend (for example the ngrok domain), set `BACKEND_URL` before starting:

```powershell
$env:BACKEND_URL="https://coral-sandbox-apron.ngrok-free.dev"; npm run dev
```

## Data

- **Saved results** show immediately: Eric's bundle in `ios/AdaptiveRetirement/Resources/Demo/` when it exists, otherwise the real engine responses in `contracts/examples/`.
- **Live results** replace them when the "Live calculation" switch is on and the backend answers. Failures keep the previous result, labelled "Last live" or "Saved".
- Custom scenarios in Explore need the live backend; saved presets work offline once the bundle includes them.
- Without an AI key the backend still answers, labelled "Rules fallback".

Every figure comes from the profile or the engine response; the app does no financial calculation of its own.

## Scenario history (Tiger Data)

Explore → **Scenario history** saves the result on screen and compares two saved runs of the same profile over time, with 5/10/20-year values. Runs live in Tiger Data; set `TIGER_DATABASE_URL` in `backend/.env` (see [`backend/app/analytics/README.md`](../backend/app/analytics/README.md)). Without it the panel says history isn't set up, and everything else works.

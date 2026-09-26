# Backend Runbook (Developer A)

How to run, expose, check and recover the Adaptive Retirement API for the demo. The
backend runs on a teammate's laptop and reaches the iPhone through a temporary
Cloudflare HTTPS tunnel (BACKEND.md section 15).

## 1. One-time setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env               # then put GEMINI_API_KEY in .env (never commit it)
```

Install the tunnel: macOS `brew install cloudflared`; Windows `winget install --id Cloudflare.cloudflared`.

Recommended `.env` for the demo:

```bash
AI_MODEL=gemini-3.5-flash-lite
AI_THINKING_LEVEL=minimal
AI_TOTAL_TIMEOUT_SECONDS=4
```

A bad value stops startup with one line, for example
`Config error: AI_TOTAL_TIMEOUT_SECONDS='abc' must be a number (check backend/.env)`.

## 2. Start (three terminals)

```bash
# 1. API: one worker, because decision replay lives in memory
uvicorn app.main:app --host 127.0.0.1 --port 8000

# 2. Tunnel: prints https://<random-name>.trycloudflare.com
cloudflared tunnel --url http://localhost:8000

# 3. Keep the laptop awake (macOS; on Windows set Power > Sleep to Never)
caffeinate -i
```

The startup log says either `AI enabled (model=...)` or `AI disabled: rules fallback`.

## 3. Check before every rehearsal and before judging

```bash
python scripts/smoke.py                                   # local
python scripts/smoke.py https://<name>.trycloudflare.com  # exactly what the phone uses
```

`RESULT: OK` means health, profiles, all three evaluations and the error cases work.
The `Live AI decisions: n/3` line shows how many came from Gemini this minute.
Then, on the phone: Connection Settings, paste the tunnel URL, run the health check,
and test once on **cellular** (not venue Wi-Fi).

## 4. Reading the AI labels

| `decision_summary.fallback_reason` | Meaning | Action |
|---|---|---|
| `null` with `source: "ai"` | Live Gemini decision | None |
| `AI_UNAVAILABLE` | No key or `AI_ENABLED=false` | Check `.env`, restart |
| `TIMEOUT` | Gemini took longer than the 4s budget | Usually temporary |
| `RATE_LIMITED` | Gemini quota (free tier allows few requests per minute) | Wait, or enable billing |
| `AI_COOLDOWN` | Breaker paused AI after repeated timeouts or a rate limit | Resumes by itself (about 30s) |
| `PROVIDER_ERROR` | Other Gemini or network error | Check the server log |
| `INVALID_*`, `UNSUPPORTED_RATIONALE_CLAIM` | Gemini answered, Python rejected it | Expected occasionally; rules order is used |
| `BLOCKED_FINANCIAL_INPUT` | Profile can't be planned (shortfall or unknown match) | By design; no AI call |

Every fallback is still a correct, funded plan. The app labels it "Rules fallback".

## 5. Recovery

| Problem | Fix |
|---|---|
| Phone can't reach the API | Tunnel restarted: copy the new URL into the app's Connection Settings (no rebuild) |
| Tunnel keeps dropping | Restart `cloudflared`; if the venue blocks it, use the phone hotspot |
| Laptop slept or server died | Restart both terminals; the app keeps working on bundled offline data meanwhile |
| Every request says `AI_COOLDOWN` or `TIMEOUT` | Gemini is slow or out of quota: keep presenting (fallbacks are honest), or switch `AI_MODEL` and restart |
| Startup prints `Config error` | Fix the named value in `backend/.env` |

## 6. After changing the API contract

```bash
python scripts/export_contracts.py   # regenerates contracts/openapi.json and contracts/examples/
pytest                               # test_contracts.py fails if contracts/ is stale
```

Commit the regenerated `contracts/` and tell the iOS developers to re-run their decode check.

## 7. Security reminders

- The Gemini key lives only in `backend/.env` (git-ignored), never in the app or bundles.
- Logs contain only method, route, status and latency: no request bodies, names or keys.
- This is a synthetic-data prototype with no accounts: don't enter real personal data.

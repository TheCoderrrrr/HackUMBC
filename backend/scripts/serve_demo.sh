#!/usr/bin/env bash
# Demo server: API on localhost:8000, published at your fixed ngrok domain, laptop kept awake.
# Usage: scripts/serve_demo.sh your-name.ngrok-free.app [port]   (or set NGROK_DOMAIN)
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="${1:-${NGROK_DOMAIN:-}}"
PORT="${2:-8000}"
if [[ -z "$DOMAIN" ]]; then
  echo "Usage: scripts/serve_demo.sh <your-name>.ngrok-free.app [port]  (or set NGROK_DOMAIN)" >&2
  exit 1
fi
command -v ngrok >/dev/null || { echo "Install ngrok: brew install ngrok" >&2; exit 1; }

PY=".venv/bin/python"; [[ -x "$PY" ]] || PY="python3"

# One worker: decision replay lives in memory.
"$PY" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT" &
API_PID=$!
caffeinate -i -w "$API_PID" &

NGROK_PID=""
cleanup() { kill "$API_PID" "$NGROK_PID" 2>/dev/null || true; }
trap cleanup EXIT

# Wait for the API to answer before opening the tunnel, and fail fast if it crashed
# (port in use, bad .env, ...), so the domain never serves ngrok 502 pages.
echo "API starting on 127.0.0.1:$PORT; public URL: https://$DOMAIN"
until curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; do
  kill -0 "$API_PID" 2>/dev/null || { echo "API failed to start; see the log above" >&2; exit 1; }
  sleep 0.3
done

ngrok http --url="$DOMAIN" "$PORT" --log=stdout --log-level=warn &
NGROK_PID=$!

# Whichever process dies first stops the demo instead of leaving a live tunnel
# answering 502 for a dead API. (Portable poll loop; macOS ships bash 3.2, no wait -n.)
while true; do
  kill -0 "$API_PID" 2>/dev/null || { echo "API exited; stopping the tunnel." >&2; exit 1; }
  kill -0 "$NGROK_PID" 2>/dev/null || { echo "Tunnel exited; stopping the API." >&2; exit 1; }
  sleep 1
done

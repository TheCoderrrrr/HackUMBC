#!/usr/bin/env bash
# Demo server: API on localhost:8000, published at your fixed ngrok domain, laptop kept awake.
# Usage: scripts/serve_demo.sh your-name.ngrok-free.app   (or set NGROK_DOMAIN)
set -euo pipefail
cd "$(dirname "$0")/.."

DOMAIN="${1:-${NGROK_DOMAIN:-}}"
if [[ -z "$DOMAIN" ]]; then
  echo "Usage: scripts/serve_demo.sh <your-name>.ngrok-free.app  (or set NGROK_DOMAIN)" >&2
  exit 1
fi
command -v ngrok >/dev/null || { echo "Install ngrok: brew install ngrok" >&2; exit 1; }

PY=".venv/bin/python"; [[ -x "$PY" ]] || PY="python3"

# One worker: decision replay lives in memory.
"$PY" -m uvicorn app.main:app --host 127.0.0.1 --port 8000 &
API_PID=$!
caffeinate -i -w "$API_PID" &
trap 'kill "$API_PID" 2>/dev/null' EXIT

echo "API starting; public URL: https://$DOMAIN"
ngrok http --url="$DOMAIN" 8000 --log=stdout --log-level=warn

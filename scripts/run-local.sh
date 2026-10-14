#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PUBLIC_URL="${PUBLIC_URL:-http://localhost:8080}"
export WEB_DIR="${WEB_DIR:-$PWD/app/build/web}"
test -f "$WEB_DIR/index.html"
export PYTHONPATH="$PWD/backend"
.venv/bin/python -m schulpilot.migrate
.venv/bin/python -m schulpilot.worker &
worker_pid=$!
trap 'kill "$worker_pid" 2>/dev/null || true' EXIT
.venv/bin/python -m uvicorn schulpilot.main:app --host 127.0.0.1 --port 8080 --no-access-log

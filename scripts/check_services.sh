#!/usr/bin/env bash
set -Eeuo pipefail
PORT=8000
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="${2:-8000}"; shift 2;;
    -h|--help) echo "Usage: bash scripts/check_services.sh [--port 8000]"; exit 0;;
    *) shift;;
  esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
LOG_FILE="$PROJECT_ROOT/.logs/uvicorn.log"

printf "Python: %s\n" "$(python --version 2>&1 || echo 'not in venv')"
printf "FastAPI: %s\n" "$(python -c 'import fastapi; print(fastapi.__version__)' 2>/dev/null || echo 'not installed')"
printf "Uvicorn: %s\n" "$(python -c 'import uvicorn; print(uvicorn.__version__)' 2>/dev/null || echo 'not installed')"

if pgrep -f "uvicorn .*services\.app:app" >/dev/null 2>&1; then
  echo "uvicorn appears to be running."
else
  echo "uvicorn is not running."
fi

echo "--- Port $PORT status ---"
if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN
  else
    echo "No listeners on :$PORT"
  fi
fi

if [[ -f "$LOG_FILE" ]]; then
  echo "--- Last 100 lines of $LOG_FILE ---"
  tail -n 100 "$LOG_FILE"
else
  echo "No uvicorn log file found at $LOG_FILE"
fi

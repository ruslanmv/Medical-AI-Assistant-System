#!/usr/bin/env bash
set -Eeuo pipefail

PORT=8000
PATTERN_DEFAULT='(uvicorn|python -m uvicorn|gunicorn.*uvicorn\.workers\.UvicornWorker)'
PATTERN="$PATTERN_DEFAULT"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok(){ echo -e "${GREEN}✓ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $*${NC}"; }
err(){ echo -e "${RED}✗ $*${NC}"; }

usage(){
  cat <<USAGE
Usage: bash scripts/kill_services.sh [--port 8000] [--pattern 'regex']
Kills processes listening on the given TCP port and common uvicorn/gunicorn workers.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="${2:-8000}"; shift 2;;
    --pattern) PATTERN="${2:-$PATTERN_DEFAULT}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }
need_cmd lsof

kill_pids(){
  local sig="$1"; shift
  local pids=("$@")
  [[ ${#pids[@]} -eq 0 ]] && return 0
  kill "-$sig" "${pids[@]}" 2>/dev/null || true
}

# 1) Kill by command patterns (uvicorn/gunicorn workers)
mapfile -t name_pids < <(pgrep -f "$PATTERN" || true)
if [[ ${#name_pids[@]} -gt 0 ]]; then
  warn "Killing by name pattern: $PATTERN (PIDs: ${name_pids[*]})"
  kill_pids TERM "${name_pids[@]}"
  sleep 0.5
fi

# 2) Kill whoever is LISTENing on the port
mapfile -t port_pids < <(lsof -ti TCP:"$PORT" -sTCP:LISTEN || true)
if [[ ${#port_pids[@]} -gt 0 ]]; then
  warn "Killing listeners on :$PORT (PIDs: ${port_pids[*]})"
  kill_pids TERM "${port_pids[@]}"
  sleep 0.7
fi

# Escalate if needed
mapfile -t still_pids < <(lsof -ti TCP:"$PORT" -sTCP:LISTEN || true)
if [[ ${#still_pids[@]} -gt 0 ]]; then
  warn "Port $PORT still in use after TERM, sending KILL to: ${still_pids[*]}"
  kill_pids KILL "${still_pids[@]}"
  sleep 0.3
fi

if lsof -iTCP:"$PORT" -sTCP:LISTEN -nP >/dev/null 2>&1; then
  err "Port $PORT is STILL in use."
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN || true
  exit 1
else
  ok "Freed port $PORT (and killed prior uvicorn processes if any)."
fi

#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
ok(){ echo -e "${GREEN}✓ $*${NC}"; }
info(){ echo -e "${CYAN}$*${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $*${NC}"; }
err(){ echo -e "${RED}✗ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VENV_DIR="${PROJECT_ROOT}/venv"
ENV_FILE="${PROJECT_ROOT}/.env"
SERVICES_DIR="${PROJECT_ROOT}/services"
LOG_DIR="${PROJECT_ROOT}/.logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/uvicorn.log"
PORT_FILE="$LOG_DIR/last_port"

HOST="0.0.0.0"
PORT=8000
RELOAD=false
FG=false
NO_BUMP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST=${2:-0.0.0.0}; shift 2;;
    --port) PORT=${2:-8000}; shift 2;;
    --reload) RELOAD=true; shift;;
    --fg|--foreground) FG=true; shift;;
    --no-bump) NO_BUMP=true; shift;;
    -h|--help)
      cat <<USAGE
Usage: bash scripts/start_services_only.sh [--host 0.0.0.0] [--port 8000] [--reload] [--fg] [--no-bump]
USAGE
      exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }
need_cmd python3
need_cmd lsof
need_cmd curl

port_in_use(){ lsof -iTCP:"$1" -sTCP:LISTEN -nP >/dev/null 2>&1; }

find_free_port(){
  local start="$1"; local end="${2:-8010}"; local p
  for ((p=start; p<=end; p++)); do
    if ! port_in_use "$p"; then echo "$p"; return 0; fi
  done
  return 1
}

ensure_venv(){
  if [[ -d "$VENV_DIR" ]]; then
    info "Activating venv: $VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    ok "Python $(python --version 2>&1)"
  else
    warn "Venv not found. Creating at $VENV_DIR …"
    python3 -m venv "$VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    python -m pip install -U pip setuptools wheel >/dev/null
    python -m pip install fastapi "uvicorn[standard]" pydantic >/dev/null
    ok "Created and activated venv"
  fi
}

load_env(){
  if [[ -f "$ENV_FILE" ]]; then
    info "Loading env from $ENV_FILE"
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
  else
    warn ".env not found at $ENV_FILE (proceeding with current env)"
  fi
}

preflight_port(){
  if port_in_use "$PORT"; then
    warn "Port $PORT is in use. Attempting to free it…"
    bash "$PROJECT_ROOT/scripts/kill_services.sh" --port "$PORT" || true
  fi

  if port_in_use "$PORT"; then
    if [[ "$NO_BUMP" == true ]]; then
      err "Port $PORT still in use and --no-bump given. Aborting."
      lsof -nP -iTCP:"$PORT" -sTCP:LISTEN || true
      exit 1
    else
      local newp
      newp="$(find_free_port "$PORT" 8010)" || { err "No free port between $PORT–8010."; exit 1; }
      warn "Using alternative free port: $newp"
      PORT="$newp"
    fi
  fi
  echo "$PORT" > "$PORT_FILE" || true
}

start_services(){
  if [[ ! -f "$SERVICES_DIR/app.py" ]]; then
    err "services/app.py not found. Nothing to start."
    exit 1
  fi
  mkdir -p "$SERVICES_DIR"
  [[ -f "$SERVICES_DIR/__init__.py" ]] || : > "$SERVICES_DIR/__init__.py"

  need_cmd uvicorn
  export PYTHONPATH="$PROJECT_ROOT:${PYTHONPATH:-}"

  local reload_flag=()
  [[ "$RELOAD" == true ]] && reload_flag=(--reload)

  info "Starting FastAPI services on http://${HOST}:${PORT} …"
  if [[ "$FG" == true ]]; then
    exec uvicorn services.app:app --host "$HOST" --port "$PORT" --log-level info "${reload_flag[@]}"
  else
    : > "$LOG_FILE" || true
    nohup python -m uvicorn services.app:app --host "$HOST" --port "$PORT" --log-level info "${reload_flag[@]}" \
      >"$LOG_FILE" 2>&1 &
    sleep 1
    if curl -fsS "http://localhost:${PORT}/docs" >/dev/null 2>&1; then
      ok "Services are up: http://localhost:${PORT}/docs (port $PORT)"
    else
      warn "Services didn't respond yet. Recent logs:"
      tail -n 120 "$LOG_FILE" || true
      exit 1
    fi
  fi
}

main(){
  echo -e "${GREEN}=== Starting ONLY local services (no Orchestrate) ===${NC}"
  ensure_venv
  load_env
  preflight_port
  start_services
}

main "$@"

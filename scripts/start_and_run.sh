# -------------------------------
# File: services/__init__.py
# (Ensure 'services' is a proper Python package so `uvicorn services.app:app` imports cleanly.)
# -------------------------------

# (empty file)


# -------------------------------
# File: scripts/kill_services.sh
# Stop any previously running uvicorn for our app
# -------------------------------
#!/usr/bin/env bash
set -Eeuo pipefail
pkill -f "uvicorn services.app:app" >/dev/null 2>&1 || true
pkill -f "python -m uvicorn services.app:app" >/dev/null 2>&1 || true
printf "Killed previous uvicorn processes (if any).\n"


# -------------------------------
# File: scripts/start_services_only.sh  (UPDATED)
# Start ONLY the local FastAPI tool services (no Orchestrate). Adds better logging & import fixes.
# -------------------------------
#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_ok(){ echo -e "${GREEN}✓ $*${NC}"; }
log_info(){ echo -e "${CYAN}$*${NC}"; }
log_warn(){ echo -e "${YELLOW}⚠ $*${NC}"; }
log_err(){ echo -e "${RED}✗ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VENV_DIR="${PROJECT_ROOT}/venv"
ENV_FILE="${PROJECT_ROOT}/.env"
SERVICES_DIR="${PROJECT_ROOT}/services"
LOG_DIR="${PROJECT_ROOT}/.logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/uvicorn.log"

HOST="0.0.0.0"
PORT=8000
RELOAD=false
FG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST=${2:-0.0.0.0}; shift 2;;
    --port) PORT=${2:-8000}; shift 2;;
    --reload) RELOAD=true; shift;;
    --fg|--foreground) FG=true; shift;;
    -h|--help)
      cat <<USAGE
Usage: bash scripts/start_services_only.sh [--host 0.0.0.0] [--port 8000] [--reload] [--fg]
USAGE
      exit 0;;
    *) log_warn "Unknown arg: $1"; shift;;
  esac
done

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { log_err "Missing command: $1"; exit 1; }; }
port_in_use(){ local p="$1"; lsof -i ":$p" -sTCP:LISTEN -P -n >/dev/null 2>&1; }

ensure_venv(){
  if [[ -d "$VENV_DIR" ]]; then
    log_info "Activating venv: $VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    log_ok "Python $(python --version 2>&1)"
  else
    log_warn "Venv not found. Creating at $VENV_DIR …"
    python3 -m venv "$VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    python -m pip install -U pip setuptools wheel >/dev/null
    python -m pip install fastapi "uvicorn[standard]" pydantic >/dev/null
    log_ok "Created and activated venv"
  fi
}

load_env(){
  if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading env from $ENV_FILE"
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
  else
    log_warn ".env not found at $ENV_FILE (proceeding with current env)"
  fi
}

start_services(){
  if [[ ! -f "$SERVICES_DIR/app.py" ]]; then
    log_err "services/app.py not found. Nothing to start."
    exit 1
  fi
  # Ensure services is importable and clean any previous processes
  mkdir -p "$SERVICES_DIR"
  [[ -f "$SERVICES_DIR/__init__.py" ]] || : > "$SERVICES_DIR/__init__.py"
  bash "$PROJECT_ROOT/scripts/kill_services.sh" || true

  need_cmd uvicorn
  export PYTHONPATH="$PROJECT_ROOT:${PYTHONPATH:-}"

  local reload_flag=()
  [[ "$RELOAD" == true ]] && reload_flag=(--reload)

  log_info "Starting FastAPI services on http://${HOST}:${PORT} …"
  if [[ "$FG" == true ]]; then
    # Foreground mode (useful for debugging)
    exec uvicorn services.app:app --host "$HOST" --port "$PORT" --log-level info "${reload_flag[@]}"
  else
    # Background with logs
    nohup python -m uvicorn services.app:app --host "$HOST" --port "$PORT" --log-level info "${reload_flag[@]}" \
      >"$LOG_FILE" 2>&1 &
    sleep 1
    if curl -fsS "http://localhost:${PORT}/docs" >/dev/null 2>&1; then
      log_ok "Services are up: http://localhost:${PORT}/docs"
    else
      log_warn "Services did not respond yet. Recent logs:"
      tail -n 80 "$LOG_FILE" || true
      exit 1
    fi
  fi
}

main(){
  echo -e "${GREEN}=== Starting ONLY local services (no Orchestrate) ===${NC}"
  ensure_venv
  load_env
  start_services
}

main "$@"


# -------------------------------
# File: scripts/check_services.sh
# Quick doctor for common failures; prints logs if import crashed.
# -------------------------------
#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
LOG_FILE="$PROJECT_ROOT/.logs/uvicorn.log"

printf "Python: %s\n" "$(python --version 2>&1 || echo 'not in venv')"
printf "FastAPI: %s\n" "$(python -c 'import fastapi, sys; print(fastapi.__version__)' 2>/dev/null || echo 'not installed')"
printf "Uvicorn: %s\n" "$(python -c 'import uvicorn, sys; print(uvicorn.__version__)' 2>/dev/null || echo 'not installed')"

if pgrep -f "uvicorn services.app:app" >/dev/null 2>&1; then
  echo "uvicorn appears to be running."
else
  echo "uvicorn is not running."
fi

if [[ -f "$LOG_FILE" ]]; then
  echo "--- Last 100 lines of $LOG_FILE ---"
  tail -n 100 "$LOG_FILE"
else
  echo "No uvicorn log file found at $LOG_FILE"
fi

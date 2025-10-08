#!/usr/bin/env bash
# scripts/run_project.sh – One-shot runner for the Medical Orchestrator design
# - Ensures venv
# - Loads .env
# - Activates Orchestrate env (before server start)
# - Starts Orchestrate server (if needed), waits until healthy (backoff, logs)
# - Imports connections, tools, agents, and flow
# - (Optional) starts local services (FastAPI) and Chat UI

set -Eeuo pipefail

# -----------------------------
# Pretty output
# -----------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
ok(){ echo -e "${GREEN}✓ $*${NC}"; }
info(){ echo -e "${CYAN}$*${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $*${NC}"; }
err(){ echo -e "${RED}✗ $*${NC}"; }

# -----------------------------
# Paths (robust to where it's called from)
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VENV_DIR="${PROJECT_ROOT}/venv"
ENV_FILE="${PROJECT_ROOT}/.env"
AGENTS_DIR="${PROJECT_ROOT}/agents"
TOOLS_DIR="${PROJECT_ROOT}/tools"
FLOWS_DIR="${PROJECT_ROOT}/flows"
CONNS_DIR="${PROJECT_ROOT}/connections"
SERVICES_DIR="${PROJECT_ROOT}/services"
KB_DIR="${PROJECT_ROOT}/knowledge_base"
LOG_DIR="${PROJECT_ROOT}/.logs"; mkdir -p "$LOG_DIR"
ORCH_LOG="${LOG_DIR}/orchestrate.log"

# Defaults (can be overridden via .env)
ORCH_HOST_DEFAULT="127.0.0.1"
ORCH_PORT_DEFAULT="4321"
CHAT_URL_DEFAULT="http://localhost:3000/chat-lite"

# -----------------------------
# CLI args
# -----------------------------
START_SERVICES=false
SKIP_UI=false
ORCH_ONLY=false
MAX_WAIT=120

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-services) START_SERVICES=true; shift;;
    --skip-ui)        SKIP_UI=true; shift;;
    --orchestrate-only|--orch-only) ORCH_ONLY=true; shift;;
    --max-wait) MAX_WAIT="${2:-120}"; shift 2;;
    -h|--help)
      cat <<USAGE
Usage: bash scripts/run_project.sh [--start-services] [--skip-ui] [--orchestrate-only] [--max-wait 120]
USAGE
      exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

echo -e "${YELLOW}ℹ️  Project Root: ${PROJECT_ROOT}${NC}"

# -----------------------------
# Helpers
# -----------------------------
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }; }
port_in_use(){ lsof -iTCP:"$1" -sTCP:LISTEN -nP >/dev/null 2>&1; }

# Prefer 'orchestrate' CLI; fallback to 'wxo' if present
resolve_orch_cmd(){
  if command -v orchestrate >/dev/null 2>&1; then echo "orchestrate"; return; fi
  if command -v wxo >/dev/null 2>&1; then echo "wxo"; return; fi
  err "Neither 'orchestrate' nor 'wxo' CLI found in PATH."
  exit 1
}

# -----------------------------
# Steps
# -----------------------------
ensure_venv(){
  need_cmd python3
  if [[ -d "$VENV_DIR" ]]; then
    info "Activating venv: $VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    ok "Python $(python --version 2>&1)"
  else
    warn "Venv not found. Creating at $VENV_DIR ..."
    python3 -m venv "$VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    python -m pip install -U pip setuptools wheel >/dev/null
    # minimal deps for local services; orchestrate CLI is separate package
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

activate_env_local(){
  local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
  info "Activating Orchestrate env: local"
  if ! "$ORCH_CMD" env activate local >/dev/null 2>&1; then
    warn "Could not activate 'local' env. Continuing with current CLI context."
  else
    ok "Environment activated"
  fi
}

orchestrate_health_url(){
  # Use explicit base URL if provided; else derive from host/port
  local base="${ORCHESTRATE_BASE_URL:-}"
  local host="${ORCH_HOST:-${ORCH_HOST_DEFAULT}}"
  local port="${ORCH_PORT:-${ORCH_PORT_DEFAULT}}"
  if [[ -n "$base" ]]; then
    echo "${base%/}/api/v1/health"
  else
    echo "http://${host}:${port}/api/v1/health"
  fi
}

start_orchestrate_server(){
  need_cmd lsof
  need_cmd curl
  local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
  local HEALTH_URL; HEALTH_URL="$(orchestrate_health_url)"

  info "Checking Orchestrate server health at: $HEALTH_URL"
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    ok "Server already healthy"
    return
  fi

  # Try to free the target port if something else is listening
  local url_port; url_port="$(echo "$HEALTH_URL" | sed -E 's#^https?://[^:]+:([0-9]+).*#\1#')"
  if [[ "$url_port" =~ ^[0-9]+$ ]] && port_in_use "$url_port"; then
    warn "Port $url_port is busy. Showing current listener(s):"
    lsof -nP -iTCP:"$url_port" -sTCP:LISTEN || true
    warn "Not killing anything automatically for Orchestrate. Ensure the port is free if this is wrong."
  fi

  info "Starting Orchestrate server ..."
  : > "$ORCH_LOG" || true
  if [[ -f "$ENV_FILE" ]]; then
    # background with logs
    nohup "$ORCH_CMD" server start --env-file="$ENV_FILE" >"$ORCH_LOG" 2>&1 &
  else
    nohup "$ORCH_CMD" server start >"$ORCH_LOG" 2>&1 &
  fi

  # Wait until healthy (exponential-ish backoff up to MAX_WAIT)
  local waited=0 delay=1
  while (( waited < MAX_WAIT )); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
      ok "Server is healthy after ${waited}s"
      return
    fi
    sleep "$delay"
    waited=$(( waited + delay ))
    if (( delay < 5 )); then delay=$(( delay + 1 )); fi
    if (( waited % 5 == 0 )); then info "…waiting for server (t+${waited}s)"; fi
  done

  err "Server did not become healthy within ${MAX_WAIT}s"
  warn "--- Last 120 lines of ${ORCH_LOG} ---"
  tail -n 120 "$ORCH_LOG" || true
  exit 1
}

import_connections(){
  local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
  if [[ ! -d "$CONNS_DIR" ]]; then warn "No connections dir ($CONNS_DIR)"; return; fi
  shopt -s nullglob
  for f in "$CONNS_DIR"/*.{yaml,yml}; do
    info "Import connection: $(basename "$f")"
    "$ORCH_CMD" connections import -f "$f" || warn "Connection import failed (continuing): $f"
  done
  shopt -u nullglob
}

import_tools(){
  local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
  if [[ ! -d "$TOOLS_DIR" ]]; then warn "No tools dir ($TOOLS_DIR)"; return; fi
  shopt -s nullglob
  for f in "$TOOLS_DIR"/*.{yaml,yml}; do
    info "Import OpenAPI tool: $(basename "$f")"
    "$ORCH_CMD" tools import -k openapi -f "$f" || { err "Tool import failed: $f"; exit 1; }
  done
  for f in "$TOOLS_DIR"/*.py; do
    info "Import Python tool: $(basename "$f")"
    "$ORCH_CMD" tools import -k python -f "$f" || { err "Tool import failed: $f"; exit 1; }
  done
  shopt -u nullglob
}

import_agents(){
  local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
  if [[ ! -d "$AGENTS_DIR" ]]; then warn "No agents dir ($AGENTS_DIR)"; return; fi
  shopt -s nullglob
  for f in "$AGENTS_DIR"/*.{yaml,yml}; do
    info "Import agent: $(basename "$f")"
    "$ORCH_CMD" agents import -f "$f" || { err "Agent import failed: $f"; exit 1; }
  done
  shopt -u nullglob
}

import_flow(){
  local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
  if [[ -f "$FLOWS_DIR/medical_orchestrator_flow.py" ]]; then
    info "Importing flow: medical_orchestrator_flow.py"
    "$ORCH_CMD" flows import "$FLOWS_DIR/medical_orchestrator_flow.py" || { err "Flow import failed"; exit 1; }
  else
    warn "Flow file not found in $FLOWS_DIR"
  fi
}

start_services(){
  if [[ "$START_SERVICES" != true ]]; then return; fi
  if [[ -f "$SERVICES_DIR/app.py" ]]; then
    info "Starting local FastAPI services (uvicorn) …"
    pkill -f "uvicorn services.app:app" >/dev/null 2>&1 || true
    nohup uvicorn services.app:app --host 0.0.0.0 --port 8000 >/dev/null 2>&1 &
    sleep 1
    ok "Services listening on http://localhost:8000"
  else
    warn "No services/app.py present — skipping"
  fi
}

maybe_start_chat(){
  local chat_url="${CHAT_URL:-$CHAT_URL_DEFAULT}"
  if [[ "$SKIP_UI" == true ]]; then
    warn "Skipping Chat UI per flag"
    return
  fi
  read -r -p "Start Chat UI now? (y/N): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    local ORCH_CMD; ORCH_CMD="$(resolve_orch_cmd)"
    "$ORCH_CMD" chat start >/dev/null 2>&1 &
    sleep 2
    ok "Chat UI starting. Open: ${chat_url}"
  else
    info "You can start the chat UI later with: orchestrate chat start"
  fi
}

show_info(){
  local host="${ORCH_HOST:-${ORCH_HOST_DEFAULT}}"
  local port="${ORCH_PORT:-${ORCH_PORT_DEFAULT}}"
  local api="http://${host}:${port}"
  local chat_url="${CHAT_URL:-$CHAT_URL_DEFAULT}"

  echo -e "${BLUE}\n=== Useful URLs ===${NC}"
  echo "• Chat UI: ${chat_url}"
  echo "• Orchestrate API: ${api}/docs"
  echo "• Local services (optional): http://localhost:8000/docs"
}

main(){
  echo -e "${GREEN}=== Running Medical Orchestrator Project ===${NC}"
  ensure_venv
  load_env
  activate_env_local           # <-- moved BEFORE server start
  start_orchestrate_server
  show_info

  if [[ "$ORCH_ONLY" == true ]]; then
    ok "Orchestrate is up. Skipping imports and services due to --orchestrate-only."
    exit 0
  fi

  import_connections
  import_tools
  import_agents
  import_flow
  start_services
  maybe_start_chat
  echo -e "${GREEN}\n✔ All done!${NC}"
}

main "$@"

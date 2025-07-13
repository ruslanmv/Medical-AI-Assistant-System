# Makefile — Medical AI Assistant System
#
# Two independent components
# ─────────────────────────
# 1. watsonx-orchestrate        → cloned into ./watsonx-orchestrate
#    • Its own Makefile and venv (./watsonx-orchestrate/venv)
# 2. watsonx-medical-mcp-server → cloned / submodule in ./watsonx-medical-mcp-server
#    • Its own Makefile and venv (./watsonx-medical-mcp-server/.venv)
# ------------------------------------------------------------------------------

# ──────────────────────────────────────────────────────────────────────────────
# Global settings
# ──────────────────────────────────────────────────────────────────────────────
SHELL          := /bin/bash
PYTHON_VERSION ?= 3.11

# ── MCP server ────────────────────────────────────────────────────────────────
MCP_REPO_URL   := https://github.com/ruslanmv/watsonx-medical-mcp-server.git
MCP_DIR        := watsonx-medical-mcp-server
MCP_VENV       := $(MCP_DIR)/.venv
MCP_PYTHON     := $(MCP_VENV)/bin/python
SERVER_MAIN    := $(MCP_DIR)/server.py

# ── Watsonx Orchestrate installer ─────────────────────────────────────────────
ORCH_REPO_URL  := https://github.com/ruslanmv/Installer-Watsonx-Orchestrate.git
ORCH_BRANCH    := automatic
ORCH_DIR       := watsonx-orchestrate
ORCH_VENV      := $(ORCH_DIR)/venv
ORCH_PYTHON    := $(ORCH_VENV)/bin/python

# ── Helper scripts in this repository ────────────────────────────────────────
DEPLOY_SCRIPT          := scripts/deploy.sh
DEPLOY_SPECIALISTS     := scripts/deploy_specialists.sh
SYSTEM_HEALTH_CHECK    := scripts/system_health_check.sh
MONITOR_SCRIPT         := scripts/monitor_agents.py
COLLAB_TEST_SCRIPT     := scripts/test_collaboration.py

# ── Docker image tag ─────────────────────────────────────────────────────────
IMAGE := medical-ai-assistant-system:latest

# ──────────────────────────────────────────────────────────────────────────────
# System check
# ──────────────────────────────────────────────────────────────────────────────
PYTHON_SYSTEM := $(shell command -v python$(PYTHON_VERSION))
ifeq ($(PYTHON_SYSTEM),)
  $(error Python $(PYTHON_VERSION) is not installed or not in PATH.)
endif

# ──────────────────────────────────────────────────────────────────────────────
# Phony targets
# ──────────────────────────────────────────────────────────────────────────────
.PHONY: \
  help \
  init-orch update-orch orch-setup \
  init-mcp  update-mcp  mcp-setup \
  setup reinstall clean \
  start run stop purge run-mcp \
  deploy deploy-specialists health-check monitor collab-test \
  lint format check-format test check \
  docker-build docker-run docker-shell

.DEFAULT_GOAL := help

# ──────────────────────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────────────────────
help:
	@echo "Makefile — Medical AI Assistant System"
	@echo ""
	@echo "Bootstrap:"
	@echo "  init-orch          Clone watsonx-orchestrate installer repo."
	@echo "  update-orch        Pull latest commit in watsonx-orchestrate."
	@echo "  orch-setup         Install watsonx-orchestrate (branch 'automatic')."
	@echo ""
	@echo "  init-mcp           Clone or update watsonx-medical-mcp-server repo."
	@echo "  update-mcp         Pull latest commit in MCP repo."
	@echo "  mcp-setup          Build MCP virtual-env via its own Makefile."
	@echo ""
	@echo "  setup              Ensure BOTH components are fully installed."
	@echo "  reinstall          Clean and rebuild both environments."
	@echo ""
	@echo "Orchestrate server:"
	@echo "  start              🚀 Start the watsonx Orchestrate server."
	@echo "  run                🏃 Import agents/tools & start Orchestrate app."
	@echo "  stop               🛑 Stop Orchestrate server & containers."
	@echo "  purge              🔥 Remove Orchestrate containers & images."
	@echo ""
	@echo "MCP server:"
	@echo "  run-mcp            🚀 Start the MCP server (STDIO)."
	@echo ""
	@echo "Deploy & Ops:"
	@echo "  deploy             Full system deploy (scripts/deploy.sh)."
	@echo "  deploy-specialists Update specialist agents only."
	@echo "  health-check       Comprehensive health verification."
	@echo "  monitor            Runtime metrics report."
	@echo "  collab-test        Multi-agent collaboration tests."
	@echo ""
	@echo "Quality & Testing:"
	@echo "  lint               flake8 + black --check."
	@echo "  format             Auto-format with black."
	@echo "  check-format       Verify formatting only."
	@echo "  test               Run pytest suite."
	@echo "  check              Lint + tests (CI gate)."
	@echo ""
	@echo "Docker:"
	@echo "  docker-build       Build $(IMAGE)."
	@echo "  docker-run         Run container (needs .env)."
	@echo "  docker-shell       Bash into the image."
	@echo ""
	@echo "Cleanup:"
	@echo "  clean              Remove BOTH virtual-envs & Python cache."

# ──────────────────────────────────────────────────────────────────────────────
#  watsonx-orchestrate — clone / update / install
# ──────────────────────────────────────────────────────────────────────────────
init-orch:
	@if [ -d "$(ORCH_DIR)" ]; then \
	  echo "✅ $(ORCH_DIR) already exists."; \
	else \
	  echo "⬇️  Cloning watsonx-orchestrate repo…"; \
	  git clone --branch $(ORCH_BRANCH) --single-branch $(ORCH_REPO_URL) $(ORCH_DIR); \
	fi

update-orch:
	@echo "🔄 Updating watsonx-orchestrate repo…"
	@if [ -d "$(ORCH_DIR)" ]; then \
	  cd $(ORCH_DIR) && git checkout $(ORCH_BRANCH) && git pull origin $(ORCH_BRANCH); \
	else \
	  echo "❌ $(ORCH_DIR) not found. Run 'make init-orch' first."; exit 1; \
	fi
	@echo "✅ Orchestrate repo up to date."

orch-setup: init-orch
	@echo "🏗  Setting up watsonx-orchestrate environment…"

	# 1) Ensure we are on the desired branch
	@cd $(ORCH_DIR) && git checkout $(ORCH_BRANCH) && git pull origin $(ORCH_BRANCH)

	# 2) Guarantee an .env file exists inside watsonx-orchestrate/
	@if [ ! -f "$(ORCH_DIR)/.env" ]; then \
	  if [ -f ".env" ]; then \
	    echo "📄 Copying root .env into $(ORCH_DIR)/.env"; \
	    cp .env $(ORCH_DIR)/.env; \
	  else \
	    echo "❌ No .env found for Watsonx Orchestrate."; \
	    echo "   Please create one (see $(ORCH_DIR)/.env.template) and rerun 'make orch-setup'."; \
	    exit 1; \
	  fi \
	fi

	# 3) Delegate installation to the repo’s own Makefile
	@$(MAKE) --no-print-directory -C $(ORCH_DIR) install

# ──────────────────────────────────────────────────────────────────────────────
#  watsonx-medical-mcp-server — clone / update / setup
# ──────────────────────────────────────────────────────────────────────────────
init-mcp:
	@if [ -d "$(MCP_DIR)" ]; then \
	  if [ -f ".gitmodules" ] && grep -q "$(MCP_DIR)" .gitmodules; then \
	    echo "🔄 Updating MCP submodule…"; \
	    git submodule update --init --recursive $(MCP_DIR); \
	  else \
	    echo "✅ $(MCP_DIR) already exists."; \
	  fi \
	else \
	  if [ -f ".gitmodules" ] && grep -q "$(MCP_DIR)" .gitmodules; then \
	    echo "⬇️  Initialising MCP submodule…"; \
	    git submodule update --init --recursive $(MCP_DIR); \
	  else \
	    echo "⬇️  Cloning MCP repo…"; \
	    git clone $(MCP_REPO_URL) $(MCP_DIR); \
	  fi \
	fi

update-mcp:
	@echo "🔄 Updating MCP repo…"
	@if [ -d "$(MCP_DIR)" ]; then \
	  cd $(MCP_DIR) && git checkout main && git pull origin main; \
	else \
	  echo "❌ $(MCP_DIR) not found. Run 'make init-mcp' first."; exit 1; \
	fi
	@echo "✅ MCP repo up to date."

mcp-setup: init-mcp
	@echo "🏗  Setting up MCP environment…"
	@$(MAKE) --no-print-directory -C $(MCP_DIR) setup

# ──────────────────────────────────────────────────────────────────────────────
#  Global setup / reinstall
# ──────────────────────────────────────────────────────────────────────────────
setup: orch-setup mcp-setup
	@echo "🎉 Both environments are ready."

reinstall: clean
	@$(MAKE) orch-setup
	@$(MAKE) mcp-setup

# ──────────────────────────────────────────────────────────────────────────────
#  Orchestrate operations (delegated)
# ──────────────────────────────────────────────────────────────────────────────
start: orch-setup
	@$(MAKE) --no-print-directory -C $(ORCH_DIR) start

run: orch-setup
	@$(MAKE) --no-print-directory -C $(ORCH_DIR) run

stop:
	@$(MAKE) --no-print-directory -C $(ORCH_DIR) stop

purge:
	@$(MAKE) --no-print-directory -C $(ORCH_DIR) purge

# ──────────────────────────────────────────────────────────────────────────────
#  MCP server
# ──────────────────────────────────────────────────────────────────────────────
run-mcp: mcp-setup
	@echo "🚀 Starting MCP server…"
	@$(MCP_PYTHON) $(SERVER_MAIN)

# ──────────────────────────────────────────────────────────────────────────────
#  Deployment & Ops helpers (use Orchestrate env for Python tooling)
# ──────────────────────────────────────────────────────────────────────────────
deploy: orch-setup
	@chmod +x $(DEPLOY_SCRIPT)
	@$(DEPLOY_SCRIPT)

deploy-specialists: orch-setup
	@chmod +x $(DEPLOY_SPECIALISTS)
	@$(DEPLOY_SPECIALISTS)

health-check: orch-setup
	@chmod +x $(SYSTEM_HEALTH_CHECK)
	@$(SYSTEM_HEALTH_CHECK)

monitor: orch-setup
	@$(ORCH_PYTHON) $(MONITOR_SCRIPT)

collab-test: orch-setup
	@$(ORCH_PYTHON) $(COLLAB_TEST_SCRIPT)

# ──────────────────────────────────────────────────────────────────────────────
#  Quality gates (run under Orchestrate env)
# ──────────────────────────────────────────────────────────────────────────────
lint: orch-setup
	@$(ORCH_PYTHON) -m flake8 .
	@$(ORCH_PYTHON) -m black --check .

format: orch-setup
	@$(ORCH_PYTHON) -m black .

check-format: orch-setup
	@$(ORCH_PYTHON) -m black --check .

test: orch-setup
	@WATSONX_APIKEY=dummy PROJECT_ID=dummy \
	  $(ORCH_PYTHON) -m pytest -v

check: lint test

# ──────────────────────────────────────────────────────────────────────────────
#  Docker
# ──────────────────────────────────────────────────────────────────────────────
docker-build:
	@docker build --progress=plain -t $(IMAGE) .

docker-run: docker-build
	@if [ ! -f .env ]; then \
	  echo "❌ .env not found."; exit 1; \
	fi
	@docker run --rm -it \
	  --env-file .env \
	  --name medical-ai-assistant \
	  $(IMAGE)

docker-shell: docker-build
	@docker run --rm -it \
	  --env-file .env \
	  --entrypoint /bin/bash \
	  $(IMAGE)

# ──────────────────────────────────────────────────────────────────────────────
#  Clean up
# ──────────────────────────────────────────────────────────────────────────────
clean:
	@echo "🧹 Removing virtual-envs & caches…"
	@rm -rf $(ORCH_VENV) $(MCP_VENV) .pytest_cache .mypy_cache
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete."

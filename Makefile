# Makefile — Medical AI Assistant System
#
# • Ensures the watsonx-medical-mcp-server code is present:
#     ▸ If added as a git submodule ➜ git submodule update --init --recursive
#     ▸ Otherwise ➜ git clone
# • Creates a Python 3.11 virtual-env in .venv and installs deps from that repo.
# • Lint, format, test, deploy, Docker, and cleanup helpers.
# • Uses watsonx-medical-mcp-server/server.py when running.

#──────────────────────────────────────────────────────────────────────────────
# Config
#──────────────────────────────────────────────────────────────────────────────
PYTHON_VERSION ?= 3.11
VENV            := .venv
STAMP           := $(VENV)/.install_complete
PYTHON_VENV     := $(VENV)/bin/python

MCP_REPO_URL    := https://github.com/ruslanmv/watsonx-medical-mcp-server.git
MCP_DIR         := watsonx-medical-mcp-server
REQ_FILE        := $(MCP_DIR)/requirements.txt
SERVER_MAIN     := $(MCP_DIR)/server.py

IMAGE           := medical-ai-assistant-system:latest

# Script paths
DEPLOY_SCRIPT          := scripts/deploy.sh
DEPLOY_SPECIALISTS     := scripts/deploy_specialists.sh
SYSTEM_HEALTH_CHECK    := scripts/system_health_check.sh
MONITOR_SCRIPT         := scripts/monitor_agents.py
COLLAB_TEST_SCRIPT     := scripts/test_collaboration.py

#──────────────────────────────────────────────────────────────────────────────
# System checks
#──────────────────────────────────────────────────────────────────────────────
PYTHON_SYSTEM := $(shell command -v python$(PYTHON_VERSION))
ifeq ($(PYTHON_SYSTEM),)
  $(error Python $(PYTHON_VERSION) is not installed or not in PATH.)
endif

#──────────────────────────────────────────────────────────────────────────────
# Phony targets
#──────────────────────────────────────────────────────────────────────────────
.PHONY: \
  help \
  init-mcp update-mcp setup install reinstall clean \
  run deploy deploy-specialists health-check monitor collab-test \
  lint format check-format test check \
  docker-build docker-run docker-shell

.DEFAULT_GOAL := help

#──────────────────────────────────────────────────────────────────────────────
# Help
#──────────────────────────────────────────────────────────────────────────────
help:
	@echo "Makefile — Medical AI Assistant System"
	@echo ""
	@echo "Bootstrap:"
	@echo "  init-mcp          Ensure watsonx-medical-mcp-server code is present."
	@echo "  update-mcp        Pull the latest commit for the submodule."
	@echo "  setup             Create/update the virtual environment."
	@echo "  reinstall         Re-create the virtual environment."
	@echo ""
	@echo "Run & Deploy:"
	@echo "  run               Start the MCP server (stdio)."
	@echo "  deploy            Full system deploy (scripts/deploy.sh)."
	@echo "  deploy-specialists Update specialist agents only."
	@echo ""
	@echo "Ops:"
	@echo "  health-check      Comprehensive health verification."
	@echo "  monitor           Runtime metrics report."
	@echo "  collab-test       Multi-agent collaboration tests."
	@echo ""
	@echo "Quality & Testing:"
	@echo "  lint              flake8 + black --check."
	@echo "  format            Format codebase with black."
	@echo "  check-format      Verify black formatting only."
	@echo "  test              Run pytest suite."
	@echo "  check             Lint + tests (CI gate)."
	@echo ""
	@echo "Docker:"
	@echo "  docker-build      Build $(IMAGE)."
	@echo "  docker-run        Run container (needs .env)."
	@echo "  docker-shell      Bash into the image."
	@echo ""
	@echo "Cleanup:"
	@echo "  clean             Remove virtual-env and Python cache."

#──────────────────────────────────────────────────────────────────────────────
# Clone or update the MCP repo
#──────────────────────────────────────────────────────────────────────────────
init-mcp:
	@if [ -d "$(MCP_DIR)" ]; then \
	  if [ -f ".gitmodules" ] && grep -q "$(MCP_DIR)" .gitmodules; then \
	    echo "🔄 Updating MCP submodule…"; \
	    git submodule update --init --recursive $(MCP_DIR); \
	  else \
	    echo "✅ $(MCP_DIR) directory already exists (non-submodule)."; \
	  fi \
	else \
	  if [ -f ".gitmodules" ] && grep -q "$(MCP_DIR)" .gitmodules; then \
	    echo "⬇️  Initialising MCP submodule…"; \
	    git submodule update --init --recursive $(MCP_DIR); \
	  else \
	    echo "⬇️  Cloning MCP server repo…"; \
	    git clone $(MCP_REPO_URL) $(MCP_DIR); \
	  fi \
	fi

# Pull latest code into the submodule (manual target)
update-mcp:
	@echo "🔄 Pulling latest MCP server code…"
	@if [ -d "$(MCP_DIR)" ]; then \
	  cd $(MCP_DIR) && git checkout main && git pull origin main; \
	else \
	  echo "❌ $(MCP_DIR) not found. Run 'make init-mcp' first."; exit 1; \
	fi
	@echo "✅ Submodule updated."

#──────────────────────────────────────────────────────────────────────────────
# Virtual-env & dependencies
#──────────────────────────────────────────────────────────────────────────────
$(STAMP): init-mcp $(REQ_FILE)
	@echo "📦 Installing dependencies…"
	@$(PYTHON_VENV) -m pip install --upgrade pip
	@$(PYTHON_VENV) -m pip install -r $(REQ_FILE)
	@$(PYTHON_VENV) -m pip install flake8 black pytest
	@touch $(STAMP)
	@echo "✅ Dependencies installed."

install: $(STAMP)

setup: init-mcp
	@if [ -d "$(VENV)" ]; then \
	  echo "✅ Virtual environment exists."; \
	  printf "   Reinstall it? [y/N] "; read ans; \
	  if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
	    $(MAKE) reinstall; \
	  else \
	    $(MAKE) install; \
	  fi; \
	else \
	  echo "🔧 Creating virtual environment…"; \
	  $(PYTHON_SYSTEM) -m venv $(VENV); \
	  $(MAKE) install; \
	fi

reinstall: clean
	@$(PYTHON_SYSTEM) -m venv $(VENV)
	@$(MAKE) install

#──────────────────────────────────────────────────────────────────────────────
# Development & Ops
#──────────────────────────────────────────────────────────────────────────────
run: setup
	@echo "🚀 Starting MCP server…"
	@$(PYTHON_VENV) $(SERVER_MAIN)

deploy: setup
	@chmod +x $(DEPLOY_SCRIPT)
	@$(DEPLOY_SCRIPT)

deploy-specialists: setup
	@chmod +x $(DEPLOY_SPECIALISTS)
	@$(DEPLOY_SPECIALISTS)

health-check: setup
	@chmod +x $(SYSTEM_HEALTH_CHECK)
	@$(SYSTEM_HEALTH_CHECK)

monitor: setup
	@$(PYTHON_VENV) $(MONITOR_SCRIPT)

collab-test: setup
	@$(PYTHON_VENV) $(COLLAB_TEST_SCRIPT)

#──────────────────────────────────────────────────────────────────────────────
# Quality gates
#──────────────────────────────────────────────────────────────────────────────
lint: setup
	@$(PYTHON_VENV) -m flake8 .
	@$(PYTHON_VENV) -m black --check .

format: setup
	@$(PYTHON_VENV) -m black .

check-format: setup
	@$(PYTHON_VENV) -m black --check .

test: setup
	@WATSONX_APIKEY=dummy PROJECT_ID=dummy \
	  $(PYTHON_VENV) -m pytest -v

check: lint test

#──────────────────────────────────────────────────────────────────────────────
# Docker
#──────────────────────────────────────────────────────────────────────────────
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

#──────────────────────────────────────────────────────────────────────────────
# Cleanup
#──────────────────────────────────────────────────────────────────────────────
clean:
	@rm -rf $(VENV) .pytest_cache .mypy_cache
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete."

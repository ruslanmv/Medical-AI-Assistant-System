#!/usr/bin/env bash
set -euo pipefail

# Resolve script location and cd into project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load environment variables from .env file
if [ -f .env ]; then
  # ignore blank lines and comments, and export each var
  export $(grep -v '^\s*#' .env | grep -v '^\s*$' | xargs)
else
  echo "Error: .env file not found in project root ($PROJECT_ROOT/.env)"
  exit 1
fi

# Configure connection with environment variables
orchestrate connections set-credentials \
    --app-id watsonx_medical_assistant \
    --env draft \
    -e WATSONX_APIKEY="$WATSONX_APIKEY" \
    -e PROJECT_ID="$PROJECT_ID" \
    -e WATSONX_URL="$WATSONX_URL" \
    -e MODEL_ID="$MODEL_ID"

echo "Connection configuration completed successfully!"

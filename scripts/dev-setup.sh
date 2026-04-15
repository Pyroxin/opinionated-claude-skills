#!/bin/bash

set -euo pipefail
# Set DEBUG=1 in the environment to enable xtrace for diagnosing
# CI failures or local issues without editing the script.
[[ -n "${DEBUG:-}" ]] && set -x

# Set up local development environment for this repository
#
# Usage: ./scripts/dev-setup.sh
#
# This script:
#   1. Verifies required tools are available (jq, shellcheck, Claude Code)
#   2. Registers the local marketplace in Claude Code
#   3. Configures git to use the repo's versioned hooks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MARKETPLACE_JSON="${PROJECT_DIR}/.claude-plugin/marketplace.json"

echo "Setting up development environment..."

# --- Prerequisites ---
# Check all required tools before making any changes to the environment.

echo ""
echo "Checking prerequisites..."

missing=()

command -v jq >/dev/null 2>&1 || missing+=("jq")
command -v shellcheck >/dev/null 2>&1 || missing+=("shellcheck")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "FATAL: missing required tools: ${missing[*]}" >&2
  echo "Install them before running dev-setup." >&2
  exit 1
fi

echo "  jq: OK"
echo "  shellcheck: OK"

# --- Claude Code ---

echo ""
echo "Checking for Claude Code..."
if command -v claude >/dev/null 2>&1; then
  echo "  Found: $(command -v claude)"
else
  echo "  Not found. Installing..."
  curl -fsSL https://claude.ai/install.sh | bash
  if ! command -v claude >/dev/null 2>&1; then
    echo "FATAL: Claude Code installation failed." >&2
    exit 1
  fi
  echo "  Installed: $(command -v claude)"
fi

# --- Marketplace ---

marketplace_name=$(jq -r '.name' "$MARKETPLACE_JSON")
echo ""
echo "Configuring marketplace '${marketplace_name}'..."

# Check if the marketplace is already installed and whether it points here
existing=$(claude plugin marketplace list --json 2>/dev/null \
  | jq -r ".[] | select(.name == \"${marketplace_name}\")")
existing_source=$(echo "$existing" | jq -r '.source // empty')
existing_path=$(echo "$existing" | jq -r '.installLocation // empty')

if [[ -z "$existing_source" ]]; then
  # Not installed at all
  claude plugin marketplace add "$PROJECT_DIR" 2>/dev/null || true
  echo "  Added local marketplace."
elif [[ "$existing_source" == "directory" && "$existing_path" == "$PROJECT_DIR" ]]; then
  # Already pointing at this clone
  echo "  Local marketplace already configured."
else
  # Installed from a different source or a different local clone
  echo "  Removing existing marketplace (source: ${existing_source}, path: ${existing_path:-n/a})..."
  claude plugin marketplace remove "$marketplace_name"
  claude plugin marketplace add "$PROJECT_DIR" 2>/dev/null || true
  echo "  Replaced with local marketplace."
fi

# --- Git hooks ---
# Configured last so hooks only activate after the environment is ready.

echo ""
echo "Configuring git hooks..."
git -C "$PROJECT_DIR" config core.hooksPath scripts/git-hooks
echo "  core.hooksPath set to 'scripts/git-hooks'"

echo ""
echo "Setup complete. Plugins will be validated on commit and push."

#!/bin/bash

# -x: always verbose; these scripts run in seconds and the trace is
#     valuable for diagnosing CI failures without local reproduction.
set -euxo pipefail

# Install marketplace and verify all plugins and their components
#
# Usage: ./scripts/install-and-verify.sh [--validate-only] [project_dir]
#   --validate-only: Skip installation; only verify structure and run shellcheck
#   project_dir:     Root of the marketplace repo (default: script's parent directory)
#
# Full mode (default):
#   1. Ensures Claude Code is on $PATH (installs if missing)
#   2. Validates the marketplace structure via Claude CLI
#   3. Verifies the marketplace is registered and points at this directory
#   4. Installs each plugin declared in marketplace.json
#   5. Verifies all declared components (skills, agents, commands, hooks) exist
#   6. Runs shellcheck on all shell scripts
#
#   Full mode is used by pre-push and CI. Pre-push is the last gate before
#   changes become public; the cost of full validation (including plugin
#   installation) is justified because it catches integration issues that
#   structural checks alone would miss.
#
# Validate-only mode (--validate-only):
#   Checks JSON validity, verifies declared components exist on disk, and
#   runs shellcheck. No Claude CLI calls, no installation, no state mutation.
#   Used by pre-commit for fast local feedback.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=true ;;
    *) PROJECT_DIR="$arg" ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-$(dirname "$SCRIPT_DIR")}"
MARKETPLACE_JSON="${PROJECT_DIR}/.claude-plugin/marketplace.json"

errors=0

error() {
  echo "  ERROR: $1" >&2
  errors=$((errors + 1))
}

info() {
  echo "  $1"
}

# --- Ensure required tools are available ---

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "FATAL: shellcheck is required but not found on \$PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is required but not found on \$PATH." >&2
  exit 1
fi

# --- Step 1: Ensure Claude Code is available (full mode only) ---

if [[ "$VALIDATE_ONLY" == "false" ]]; then
  echo "Checking for Claude Code..."
  if command -v claude >/dev/null 2>&1; then
    info "Found: $(command -v claude)"
  else
    info "Not found. Installing..."
    curl -fsSL https://claude.ai/install.sh | bash
    if ! command -v claude >/dev/null 2>&1; then
      echo "FATAL: Claude Code installation failed." >&2
      exit 1
    fi
    info "Installed: $(command -v claude)"
  fi
fi

# --- Step 2: Validate marketplace structure ---

marketplace_name=$(jq -r '.name' "$MARKETPLACE_JSON")

echo ""
if [[ "$VALIDATE_ONLY" == "false" ]]; then
  echo "Validating marketplace structure (claude plugin validate)..."
  if claude plugin validate "$PROJECT_DIR"; then
    info "Validation passed."
  else
    error "Marketplace validation failed."
  fi
else
  echo "Checking JSON validity..."
  if [[ ! -f "$MARKETPLACE_JSON" ]]; then
    error "marketplace.json not found at ${MARKETPLACE_JSON}"
  elif jq empty "$MARKETPLACE_JSON" 2>/dev/null; then
    info "marketplace.json: valid JSON."
  else
    error "marketplace.json: invalid JSON."
  fi
fi

# --- Step 3: Verify marketplace registration (full mode only) ---

if [[ "$VALIDATE_ONLY" == "false" ]]; then
  echo ""
  echo "Verifying marketplace registration..."

  existing=$(claude plugin marketplace list --json 2>/dev/null \
    | jq -r ".[] | select(.name == \"${marketplace_name}\")")
  existing_source=$(echo "$existing" | jq -r '.source // empty')
  existing_path=$(echo "$existing" | jq -r '.installLocation // empty')

  if [[ "$existing_source" == "directory" && "$existing_path" == "$PROJECT_DIR" ]]; then
    info "Marketplace points at this directory."
  else
    # Not registered, or points elsewhere. Register at local scope so the
    # verifier is self-contained (CI, fresh clones) without touching user state.
    if [[ -n "$existing_source" ]]; then
      info "Marketplace registered but points at ${existing_path:-$existing_source}; adding local-scope override."
    else
      info "Marketplace not registered; adding at local scope."
    fi
    if ! claude plugin marketplace add "$PROJECT_DIR" --scope local 2>/dev/null; then
      error "Failed to register marketplace at local scope."
    fi
  fi
fi

# --- Step 4: Install plugins at local scope (full mode only) ---
# Installs at local scope so the verifier tests the local-scope copy,
# not a pre-existing user-scope installation. Local scope takes
# precedence over user scope, so Claude will see these during
# verification. Cleaned up after verification completes.

plugin_count=$(jq '.plugins | length' "$MARKETPLACE_JSON")
installed_plugins=()

if [[ "$VALIDATE_ONLY" == "false" ]]; then
  echo ""
  echo "Installing ${plugin_count} plugins (scope: local)..."

  for i in $(seq 0 $((plugin_count - 1))); do
    plugin_name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
    plugin_ref="${plugin_name}@${marketplace_name}"
    info "Installing ${plugin_ref}..."
    if claude plugin install "${plugin_ref}" --scope local 2>/dev/null; then
      installed_plugins+=("$plugin_ref")
    else
      error "Failed to install ${plugin_name}"
    fi
  done
fi

# --- Step 5: Verify components ---

echo ""
echo "Verifying declared components exist on disk..."

for i in $(seq 0 $((plugin_count - 1))); do
  plugin_name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  plugin_source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON")
  plugin_dir="${PROJECT_DIR}/${plugin_source#./}"
  plugin_json="${plugin_dir}/plugin.json"

  echo ""
  echo "  Plugin: ${plugin_name}"

  if [[ ! -f "$plugin_json" ]]; then
    error "${plugin_name}: plugin.json not found at ${plugin_json}"
    continue
  fi

  # Verify plugin.json is well-formed
  if ! jq empty "$plugin_json" 2>/dev/null; then
    error "${plugin_name}: plugin.json is invalid JSON"
    continue
  fi

  # Check each component type: skills, agents, commands
  for component_type in skills agents commands; do
    component_count=$(jq -r ".${component_type} // [] | length" "$plugin_json")
    if [[ "$component_count" -eq 0 ]]; then
      continue
    fi

    for j in $(seq 0 $((component_count - 1))); do
      component_path=$(jq -r ".${component_type}[$j]" "$plugin_json")
      full_path="${plugin_dir}/${component_path#./}"

      case "$component_type" in
        skills)
          if [[ -f "${full_path}/SKILL.md" ]]; then
            info "  skill $(basename "$full_path"): OK"
          else
            error "${plugin_name}: skill missing SKILL.md at ${full_path}"
          fi
          ;;
        agents)
          if [[ -f "$full_path" ]]; then
            info "  agent $(basename "$full_path" .md): OK"
          else
            error "${plugin_name}: agent file missing at ${full_path}"
          fi
          ;;
        commands)
          if [[ -f "$full_path" ]]; then
            info "  command $(basename "$full_path" .md): OK"
          else
            error "${plugin_name}: command file missing at ${full_path}"
          fi
          ;;
      esac
    done
  done

  # Check hooks separately (hooks is an object, not an array)
  has_hooks=$(jq 'has("hooks")' "$plugin_json")
  if [[ "$has_hooks" == "true" ]]; then
    hooks_path=$(jq -r '.hooks' "$plugin_json")
    full_hooks_path="${plugin_dir}/${hooks_path#./}"
    if [[ -f "$full_hooks_path" ]]; then
      info "  hooks: OK"
    else
      error "${plugin_name}: hooks file missing at ${full_hooks_path}"
    fi
  fi
done

# --- Step 6: Shellcheck all shell scripts ---

echo ""
echo "Running shellcheck..."

while IFS= read -r -d '' script; do
  if shellcheck "$script" >/dev/null 2>&1; then
    info "  $(basename "$script"): OK"
  else
    error "shellcheck failed: ${script}"
    shellcheck "$script" >&2 || true
  fi
done < <(find "$PROJECT_DIR" \( -name '*.sh' -o -path '*/git-hooks/*' \) -type f -print0)

# --- Step 7: Clean up local-scope installations (full mode only) ---
# Remove local-scope entries so the user-scope installation (managed by
# dev-setup.sh) is what remains active.

if [[ "$VALIDATE_ONLY" == "false" && ${#installed_plugins[@]} -gt 0 ]]; then
  echo ""
  echo "Cleaning up local-scope installations..."
  for plugin_ref in "${installed_plugins[@]}"; do
    claude plugin uninstall "${plugin_ref}" --scope local 2>/dev/null || true
  done
  info "Local-scope plugins removed."
fi

# Note: local-scope marketplace entries are not cleaned up. They live in
# .claude/settings.local.json (gitignored, project-scoped) and are harmless:
# redundant with any user-scope entry on developer machines, ephemeral on CI.
# claude plugin marketplace remove has no --scope flag, so attempting removal
# risks deleting the developer's user-scope marketplace registration.

# --- Summary ---

echo ""
if [[ "$errors" -eq 0 ]]; then
  if [[ "$VALIDATE_ONLY" == "true" ]]; then
    echo "Structural validation passed (${plugin_count} plugins, shellcheck clean)."
  else
    echo "Full verification passed (${plugin_count} plugins installed and validated)."
  fi
  exit 0
else
  echo "Verification completed with ${errors} error(s)." >&2
  exit 1
fi

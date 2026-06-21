#!/bin/bash

set -euo pipefail
# Set DEBUG=1 in the environment to enable xtrace for diagnosing
# CI failures or local issues without editing the script.
[[ -n "${DEBUG:-}" ]] && set -x

# Install marketplace and verify all plugins and their components
#
# Usage: ./scripts/install-and-verify.sh [--validate-only] [project_dir]
#   --validate-only: Skip installation; only verify structure and run shellcheck
#   project_dir:     Root of the marketplace repo (default: script's parent directory)
#
# Full mode (default):
#   1. Creates a throwaway config dir (CLAUDE_CONFIG_DIR) so installation
#      touches neither the user's ~/.claude nor the workspace's .claude/
#   2. Ensures Claude Code is on $PATH (installs if missing)
#   3. Validates the marketplace structure via Claude CLI
#   4. Registers the marketplace and installs every plugin into the isolated dir
#   5. Verifies all declared components (skills, agents, commands, hooks) exist
#      on disk in the working tree
#   6. Runs shellcheck on all shell scripts
#
#   Full mode is used by pre-push and CI. Pre-push is the last gate before
#   changes become public; the cost of full validation (including plugin
#   installation) is justified because it catches integration issues that
#   structural checks alone would miss. Because the installation happens in an
#   isolated config dir removed by an EXIT trap, a partial or interrupted run
#   leaves no residue in the developer's real config or the workspace.
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

# --- Step 1: Prepare an isolated environment (full mode only) ---
# Redirect CLAUDE_CONFIG_DIR to a throwaway directory before any `claude plugin`
# or `claude plugin validate` call. CLAUDE_CONFIG_DIR governs the CLI's
# plugin/marketplace store (installed_plugins.json, known_marketplaces.json,
# marketplaces/, .claude.json); pointing it at the throwaway dir is what keeps
# registration and installation out of the user's ~/.claude and the workspace's
# .claude/. That store is the only state this script mutates, and every command
# that touches it runs after this export, so the isolation guarantee holds.
#
# The CLI installer below is a separate concern and is NOT confined by
# CLAUDE_CONFIG_DIR: install.sh keys off $HOME -- it creates $HOME/.claude/downloads
# and runs `claude install` to place the launcher and shell integration. It runs
# only when `claude` is absent (CI or a fresh machine), provisions the tool itself
# (the intended persistent effect), and writes no plugin/marketplace state, so it
# does not weaken the isolation guarantee above. install.sh exposes no path env
# vars; its only argument is an optional version. (Source: https://claude.ai/install.sh,
# reviewed 2026-06-20.)
#
# The EXIT trap removes the dir on any exit; the INT/TERM traps just exit (routing
# through EXIT) so an interrupted run (Ctrl-C or SIGTERM) also cleans up -- a bare
# EXIT trap does NOT run when the shell is terminated by an uncaught signal, and
# binding cleanup directly to INT/TERM would let the script resume after the
# signal and delete the config dir out from under itself. Two residue cases the
# trap cannot cover: an untrapped signal (SIGHUP, SIGQUIT, SIGKILL) and a signal
# in the brief window between mktemp and the first trap. Both leave only an empty
# directory under the system temp location -- never ~/.claude or the workspace --
# so the isolation invariant for protected state holds regardless.
#
# The EXIT handler is an inline command, not a named function: a function reached
# only through a trap looks dead to ShellCheck (SC2317 "appears unreachable"),
# which the older analyzer versions on some CI images report as a failure. The
# inline form sidesteps that across versions.

if [[ "$VALIDATE_ONLY" == "false" ]]; then
  ISOLATED_CONFIG="$(mktemp -d)"
  trap '[[ -n "${ISOLATED_CONFIG:-}" ]] && rm -rf "$ISOLATED_CONFIG"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  export CLAUDE_CONFIG_DIR="$ISOLATED_CONFIG"
  echo "Isolated config dir: ${ISOLATED_CONFIG}"

  echo ""
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

# --- Step 3: Register the marketplace (full mode only) ---
# The isolated config dir starts empty, so register unconditionally; there is
# no pre-existing user state to reconcile against and no scope to override.

if [[ "$VALIDATE_ONLY" == "false" ]]; then
  echo ""
  echo "Registering marketplace..."
  if claude plugin marketplace add "$PROJECT_DIR" 2>/dev/null; then
    info "Marketplace registered."
  else
    error "Failed to register marketplace."
  fi
fi

# --- Step 4: Install plugins into the isolated config dir (full mode only) ---
# Default (user) scope resolves to the isolated CLAUDE_CONFIG_DIR, so no
# --scope flag is needed and nothing persists outside the throwaway dir. The
# install step's purpose is to confirm each plugin is installable via the real
# CLI; component existence is checked separately against the working tree in
# Step 5, independent of the installed copy.

plugin_count=$(jq '.plugins | length' "$MARKETPLACE_JSON")

if [[ "$VALIDATE_ONLY" == "false" ]]; then
  echo ""
  echo "Installing ${plugin_count} plugins into isolated config dir..."

  # C-style loop rather than `seq 0 $((plugin_count - 1))`: when plugin_count is
  # 0, BSD seq (macOS) emits "0" rather than an empty range, which would drive an
  # iteration over a nonexistent plugin index. `((i < plugin_count))` is empty
  # when the count is 0 and is portable to bash 3.2.
  for ((i = 0; i < plugin_count; i++)); do
    plugin_name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
    plugin_ref="${plugin_name}@${marketplace_name}"
    info "Installing ${plugin_ref}..."
    if ! claude plugin install "${plugin_ref}" 2>/dev/null; then
      error "Failed to install ${plugin_name}"
    fi
  done
fi

# --- Step 5: Verify components ---

echo ""
echo "Verifying declared components exist on disk..."

# C-style loop; see the note in Step 4 on why `seq` is avoided here.
for ((i = 0; i < plugin_count; i++)); do
  plugin_name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  plugin_source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON")
  plugin_dir="${PROJECT_DIR}/${plugin_source#./}"
  plugin_json="${plugin_dir}/.claude-plugin/plugin.json"

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

  # Component directories (skills/, agents/, commands/) are optional: a plugin
  # may ship any subset, and most here ship only skills/. The find calls below
  # send stderr to /dev/null so an absent directory reads as "no components of
  # that kind" rather than an error. Discovery is structural, not driven by a
  # manifest list, so there is no authoritative "expected" set to diff against;
  # an empty result is legitimate. (Step 6's project-wide find deliberately does
  # NOT suppress stderr -- see the note there.)

  # Auto-discover skills (skills/<name>/SKILL.md)
  while IFS= read -r -d '' skill_md; do
    skill_name=$(basename "$(dirname "$skill_md")")
    if [[ -s "$skill_md" ]]; then
      info "  skill ${skill_name}: OK"
    else
      error "${plugin_name}: SKILL.md is empty at ${skill_md}"
    fi
  done < <(find "${plugin_dir}/skills" -name "SKILL.md" -type f -print0 2>/dev/null)

  # Auto-discover agents (agents/<name>.md)
  while IFS= read -r -d '' agent_md; do
    agent_name=$(basename "$agent_md" .md)
    if [[ -s "$agent_md" ]]; then
      info "  agent ${agent_name}: OK"
    else
      error "${plugin_name}: agent file is empty at ${agent_md}"
    fi
  done < <(find "${plugin_dir}/agents" -name "*.md" -type f -print0 2>/dev/null)

  # Auto-discover commands (commands/<name>.md)
  while IFS= read -r -d '' cmd_md; do
    cmd_name=$(basename "$cmd_md" .md)
    if [[ -s "$cmd_md" ]]; then
      info "  command ${cmd_name}: OK"
    else
      error "${plugin_name}: command file is empty at ${cmd_md}"
    fi
  done < <(find "${plugin_dir}/commands" -name "*.md" -type f -print0 2>/dev/null)

  # Check hooks.json if present
  hooks_file="${plugin_dir}/hooks/hooks.json"
  if [[ -f "$hooks_file" ]]; then
    if jq empty "$hooks_file" 2>/dev/null; then
      info "  hooks: OK"
    else
      error "${plugin_name}: hooks/hooks.json is invalid JSON"
    fi
  fi
done

# --- Step 6: Shellcheck all shell scripts ---

echo ""
echo "Running shellcheck..."

# Unlike the optional per-plugin directories in Step 5, PROJECT_DIR always
# exists, so a find failure here is a real problem. find writes into a temp file
# rather than a process substitution so its exit status is observable: under
# `set -e` a process substitution discards that status, letting a broken
# traversal yield an empty list that masquerades as "shellcheck clean". find's
# stderr is left unredirected so the underlying error is also visible.
scripts_list=$(mktemp)
if ! find "$PROJECT_DIR" \( -name '*.sh' -o -path '*/git-hooks/*' \) -type f -print0 > "$scripts_list"; then
  error "Failed to enumerate shell scripts under ${PROJECT_DIR}"
fi
while IFS= read -r -d '' script; do
  if shellcheck "$script" >/dev/null 2>&1; then
    info "  $(basename "$script"): OK"
  else
    error "shellcheck failed: ${script}"
    shellcheck "$script" >&2 || true
  fi
done < "$scripts_list"
rm -f "$scripts_list"

# --- Step 7: Teardown (full mode only) ---
# The entire installation lives under the isolated CLAUDE_CONFIG_DIR, so
# teardown is a single recursive remove of that directory. It is performed by
# the cleanup trap registered in Step 1 rather than here, so it runs on every
# exit path -- including errexit and Ctrl-C -- not only a clean finish. Both the
# marketplace registration and the plugin installs go away with it; no
# per-plugin uninstall and no marketplace-removal workaround is needed.

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

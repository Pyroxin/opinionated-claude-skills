#!/bin/bash

set -euo pipefail
# Set DEBUG=1 in the environment to enable xtrace for diagnosing issues.
[[ -n "${DEBUG:-}" ]] && set -x

# Ensure this repository's versioned Git hooks are active.
#
# Idempotently points core.hooksPath at scripts/git-hooks so the commit and push
# quality gates run even when a contributor never ran dev-setup.sh. Invoked from
# the SessionStart hook in .claude/settings.json and safe to run repeatedly.
#
# A SessionStart hook's stdout is injected into Claude's context, so this script
# stays silent unless it actually changes something; a no-op run prints nothing.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Act only inside a git work tree; a tarball download has no .git to configure.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

hooks_dir="scripts/git-hooks"
[[ -d "$hooks_dir" ]] || exit 0  # nothing to wire up

# 1. Point Git at the versioned hooks. No-op (and silent) when already set; the
#    assignment is unconditional re-application so an intentionally cleared or
#    diverging value is corrected on the next session.
if [[ "$(git config --local --get core.hooksPath || true)" != "$hooks_dir" ]]; then
  git config --local core.hooksPath "$hooks_dir"
  echo "ensure-git-hooks: set core.hooksPath -> ${hooks_dir}"
fi

# 2. Ensure the hook scripts are executable; a checkout on some filesystems can
#    drop the executable bit, which would silently disable the gate.
for hook in "$hooks_dir"/*; do
  if [[ -f "$hook" && ! -x "$hook" ]]; then
    chmod +x "$hook"
    echo "ensure-git-hooks: marked $(basename "$hook") executable"
  fi
done

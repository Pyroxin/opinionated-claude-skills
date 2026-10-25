#!/bin/sh

###
#   claude-dnt-prefix.sh
#
#   A CLAUDE_CODE_SHELL_PREFIX wrapper that restores DO_NOT_TRACK=1 for the commands
#   Claude Code runs, while Claude Code itself runs with DO_NOT_TRACK=0.
#
#   Why: DO_NOT_TRACK, like DISABLE_TELEMETRY, turns off Claude Code's feature-flag
#   fetching, which gates features (e.g., /skill-doctor, the advisor tool, artifact
#   comments). If your shell exports DO_NOT_TRACK=1
#   for other tools, Claude Code needs DO_NOT_TRACK=0 in its settings "env" block to
#   fetch flags, and settings env values reach every subprocess. This wrapper puts
#   DO_NOT_TRACK=1 back for those subprocesses. See harden-claude-config.sh
#   (--allow-feature-flags, --dnt-prefix).
#
#   Install: copy it somewhere stable, make it executable, and set
#   CLAUDE_CODE_SHELL_PREFIX to its absolute path, unquoted even if the path contains
#   spaces. Observed in Claude Code 2.1.310: quotes in the value became part of the
#   file name. A prefix that names a missing or non-executable file makes every Bash
#   call fail, including one that would repair it, so the fix has to come from a
#   shell outside Claude Code (observed again on 2026-11-01, when a rebase removed
#   this file from the git checkout the prefix pointed into).
#
#   Claude Code routes Bash tool calls, command hooks, status-line commands, and stdio
#   MCP server startup through the prefix; exec-form and PowerShell hooks bypass it.
#   It passes the command line as one shell-quoted argument in $1 (for Bash tool calls,
#   the whole invocation including its environment setup), so $1 must be re-evaluated
#   by a shell rather than executed as a path.
#
#   Which shell: Claude Code runs Bash tool commands under bash or zsh
#   (CLAUDE_CODE_SHELL, or auto-detected from $SHELL) and assembles $1 for that
#   shell, e.g., by sourcing a snapshot of that shell's startup state. The prefix
#   decides which shell re-runs $1, so a fixed /bin/bash would run a zsh invocation
#   under bash, where zsh-only syntax fails and the snapshot's errors are hidden.
#   The wrapper therefore re-runs $1 under $SHELL when it names bash or zsh. That
#   Claude Code sets SHELL to the shell it chose, in the environment of the commands
#   it starts, isn't documented; it was observed on 2026-11-08 (SHELL=/bin/zsh for
#   subprocesses while Claude Code itself had SHELL set to fish). For any other
#   value, or a SHELL that isn't an executable file, /bin/bash is the fallback, as
#   in the documentation's example.
#   https://code.claude.com/docs/en/env-vars (CLAUDE_CODE_SHELL, CLAUDE_CODE_SHELL_PREFIX)
###

# Claude Code passes the whole command line as one argument (see above). Any other
# count means a different calling convention, and a shell's -c would silently drop the
# extra arguments (they'd become $0, $1, ... of the command), so refuse instead.
[ $# -eq 1 ] || { echo "claude-dnt-prefix.sh: expected one argument (the command line), got $#" >&2; exit 2; }

export DO_NOT_TRACK=1
# Requiring a regular, executable file keeps a SHELL that names a missing file
# (e.g., a removed Homebrew bash) or a directory (which passes -x) from breaking
# every call; bash is the fallback then too.
case "${SHELL##*/}" in
  bash|zsh) if [ -f "$SHELL" ] && [ -x "$SHELL" ]; then exec "$SHELL" -c "$1"; fi ;;
esac
exec /bin/bash -c "$1"

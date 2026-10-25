#!/bin/bash
set -euo pipefail

# Run a commit or push hook with everything it prints passed through
# `pii-scan.py --redact-stream`, which replaces each private denylist term with
# `[denylist line N]` (see the pii-scan.py docstring).
#
# Usage: run-redacted.sh HOOK [ARGS...]
#   HOOK is the hook's own path. It runs again as `HOOK --redacted-body ARGS...`
#   with the same stdin (the pre-push hook reads Git's push lines there), and
#   --redacted-body tells it to run its checks instead of calling this script.
#
# Hook output lands in LLM agent transcripts, and a private term in a model
# request can trip the model's safety checks and derail the session. The
# scanners redact what they print themselves, but a hook also runs tools whose
# output nothing else controls (e.g., gitleaks' own diagnostics, git's error
# messages, a textconv driver's stderr, unicode-scan.py's paths), and each new
# tool or error path was another leak. One filter over the hook's whole stdout
# and stderr covers them all. The two are merged into one pipe before the
# filter, so their lines can come out in a different order relative to each
# other, and everything reaches git on one stream. Scripts run by hand, outside
# the hooks, aren't filtered, and redact_stream in pii-scan.py lists what the
# filter can't hide.
#
# Everything this script prints itself is fixed text and exit statuses. uv's
# output and the filter's own stderr are discarded rather than shown, because
# they can name a path (e.g., the denylist's, uv's cache, or a source file in
# a Python traceback), a path can hold a term, and nothing filters them.
#
# The hook fails closed: it fails when the filter can't start, when the filter
# stops partway (e.g., a denylist pattern runs past its time limit on a line;
# the rest of the output is then withheld), and when the hook's checks fail.
# A non-zero status from the checks is the hook's status; otherwise the
# filter's is.

hook="$1"
shift
# cd's error would name the directory, so it's discarded like uv's.
scripts_dir="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || scripts_dir=""
scanner="${scripts_dir}/pii-scan.py"
if [[ -z "$scripts_dir" || ! -f "$scanner" ]]; then
  echo "FATAL: the PII scanner (scripts/pii-scan.py) wasn't found, so the hook's output can't be filtered;" \
    "nothing was checked." >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "FATAL: uv is required to run the hook's output filter but not found on \$PATH; nothing was checked." >&2
  exit 1
fi

# The filter runs in the PII scanner's uv environment, because it needs the
# regex module, and `uv run --offline` can't install that environment. An
# offline sync doesn't make a network request and takes a fraction of a second when
# the environment is already installed; the online sync is needed only on a
# fresh clone or after the dependencies change, and the gate's own sync keeps
# them current. stdin is closed for every command before the hook's own run,
# so none of them can consume the pre-push lines.
if ! uv sync --quiet --offline --script "$scanner" </dev/null >/dev/null 2>&1; then
  echo "Installing the PII scanner's environment for the hook's output filter..." >&2
  # uv can't install anything without writing its cache, which a sandbox can
  # forbid (e.g., Claude Code's sandboxed Bash, where uv fails to take its
  # cache lock). Creating and removing a file there tells that case apart from
  # a failed install without printing uv's message, which names the cache's
  # path. When uv can't name its cache, the sync below reports the failure.
  cache="$(uv cache dir 2>/dev/null)" || cache=""
  if [[ -n "$cache" ]]; then
    probe=""
    if mkdir -p "$cache" 2>/dev/null; then
      probe="$(mktemp "${cache%/}/.hook-write-probe.XXXXXX" 2>/dev/null)" || probe=""
    fi
    if [[ -z "$probe" ]]; then
      echo "FATAL: uv can't write its cache (e.g., inside a sandbox that doesn't allow it), so the PII" \
        "scanner's environment can't be installed and the hook's output can't be filtered; nothing was checked." >&2
      exit 1
    fi
    rm -f "$probe"
  fi
  status=0
  uv sync --quiet --script "$scanner" </dev/null >/dev/null 2>&1 || status=$?
  if [[ $status -ne 0 ]]; then
    echo "FATAL: couldn't install or sync the PII scanner's environment (uv exit ${status}), so the hook's" \
      "output can't be filtered; nothing was checked." >&2
    exit 1
  fi
fi

# A first run on empty input checks that the filter starts and that the
# denylist is usable (e.g., present, and every entry compiles), so a broken
# denylist stops the hook before its checks spend minutes producing output
# that would be withheld. Running the same command by hand shows the filter's
# own message, which names a denylist entry by line number only.
status=0
uv run --quiet --offline "$scanner" --redact-stream </dev/null >/dev/null 2>&1 || status=$?
if [[ $status -ne 0 ]]; then
  echo "FATAL: the hook's output filter couldn't start (exit ${status}), e.g., because the denylist is missing" \
    "or has an entry that doesn't compile; nothing was checked. Its own message is withheld because it can" \
    "name a path; run \`uv run --offline scripts/pii-scan.py --redact-stream </dev/null\` to see it." >&2
  exit "$status"
fi

# errexit is off only in this script, for the pipeline: the hook is a separate
# bash process that sets its own options. PIPESTATUS is read at once, because
# the next command replaces it.
set +e
"$hook" --redacted-body "$@" 2>&1 | uv run --quiet --offline "$scanner" --redact-stream 2>/dev/null
statuses=("${PIPESTATUS[@]}")
set -e
if [[ ${statuses[1]} -ne 0 ]]; then
  echo "FATAL: the hook's output filter stopped (exit ${statuses[1]}), so the rest of the hook's output was" \
    "withheld (e.g., a denylist pattern ran past its time limit on a line, or a line was longer than" \
    "1 MiB). The filter's own message is withheld too, because it can name a path." >&2
fi
if [[ ${statuses[0]} -ne 0 ]]; then
  exit "${statuses[0]}"
fi
exit "${statuses[1]}"

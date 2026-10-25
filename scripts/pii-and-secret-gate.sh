#!/bin/bash

set -euo pipefail
# Set DEBUG=1 in the environment to enable xtrace for diagnosing issues.
[[ -n "${DEBUG:-}" ]] && set -x

# Git's plumbing follows replace refs (refs/replace/*) by default, so a scan
# would read the replacement objects while a push sends the originals. Every
# git command the gate and pii-scan.py run inherits this.
export GIT_NO_REPLACE_OBJECTS=1

# Scan content for secrets (gitleaks) and personal data (scripts/pii-scan.py)
# before it is committed or pushed.
#
# Usage: pii-and-secret-gate.sh pre-commit
#          Scans what is staged for the next commit, as recorded in the index.
#        pii-and-secret-gate.sh commit-msg MESSAGE_FILE
#          Scans the commit message and the author and committer identities
#          the commit will record.
#        pii-and-secret-gate.sh pre-push REMOTE
#          Scans everything each pushed ref publishes: every commit being
#          pushed (files, paths, and metadata), any annotated tag objects, and
#          the ref's name. REMOTE is the remote name (or URL) Git passes the
#          pre-push hook as $1; Git's pre-push lines
#          (<local ref> <local sha> <remote ref> <remote sha>) are read from
#          stdin.
#
# Every hook runs both scans. Pre-commit keeps secrets and personal data out of
# history in the first place; pre-push still checks every pushed commit, not
# only the tip, because commits can be made with hooks bypassed
# (git commit --no-verify) or before the hooks were active, and a pushed
# commit stays retrievable by its own hash after later commits change it.
#
# gitleaks scans twice: its own Git scan, and a scan of the texts the PII scan
# analyzes (every decoding of every new file version, merge results included,
# plus paths, messages, identities, tags, and ref names; see --export-to in
# pii-scan.py), so both scanners read the same content. Every gitleaks call
# uses a configuration the gate writes (gitleaks' default rules), an empty
# ignore directory, and --ignore-gitleaks-allow, so a .gitleaks.toml,
# .gitleaksignore, or gitleaks:allow comment in the repository can't change
# what the gate reports. Each scan runs with --redact and writes a JSON report,
# from which pii-scan.py prints only each leak's rule, location, and commit
# (--gitleaks-report). gitleaks' --verbose output isn't used: despite --redact
# it prints the matched line's surrounding text and, for a Git scan, the
# commit's author and email, any of which can hold a private denylist term.
#
# Nothing the gate prints may hold a denylist term, because its output lands
# in LLM agent transcripts, and a private term in a model request can trip the
# model's safety checks and derail the session (see pii-scan.py's docstring).
# So paths in reports are redacted by pii-scan.py, git's stderr is counted
# rather than printed, and the gate's own messages name a pushed ref by its
# pre-push line number and never name a remote.
# The hooks also pass everything they print, the gate's output included,
# through `pii-scan.py --redact-stream` (see scripts/git-hooks/run-redacted.sh),
# which covers text the gate doesn't control (e.g., gitleaks' own log lines
# and git's error messages). The measures above stay, because the gate run by
# hand isn't filtered.
#
# The PII allowlist is read as committed, never from the working tree, so an
# unstaged edit to it can't approve staged content: pre-commit and commit-msg
# use the version staged in the index, and pre-push uses the version at the
# tip of each pushed ref, so the commits in a push are judged by the allowlist
# that push publishes. Stage an allowlist change with the content it accepts.
#
# Each scanner first runs a positive control and the gate fails if the control
# isn't detected, so a clean result means the scanner looked rather than
# silently failing to match. gitleaks runs locally. For the PII scan, uv
# installs dependencies (the only step that uses the network, for PyPI and the
# spaCy model release), then the control and the scan run with
# `uv run --offline`. Where sandbox-exec (macOS) or a working bubblewrap
# (Linux) is available, they run inside a sandbox with no network access, so
# the scanned text can't leave the machine; the scanner first confirms from
# inside the sandbox that it doesn't have network access (counting any proxy the
# environment names as network), and the gate stops if it does. macOS won't
# start sandbox-exec inside another sandbox (e.g., Claude Code's sandboxed
# Bash), so when it fails to start, the scanner checks whether the gate
# already runs in one; the scan then runs within that outer sandbox, but only
# if the same isolation check passes there. Otherwise the gate stops: a
# sandbox-exec that fails outside any sandbox, or an outer sandbox that allows
# network access (Claude Code's does, through its proxy), means commits and
# pushes have to run from an unsandboxed shell. Where neither tool is
# available, the gate warns and scans offline without a sandbox.
#
# Exits non-zero, blocking the commit or push, when a control fails, gitleaks
# reports a secret, or the PII scan finds anything not in
# scripts/presidio-pii-allowlist.tsv. The PII scan also stops the gate when
# the private denylist (~/.config/pii-scan/denylist.txt, or the file
# PII_SCAN_DENYLIST names) is missing, doesn't hold any term patterns, or has an
# entry it can't use, unless PII_SCAN_DENYLIST=none opts out of it; see the
# docstring of pii-scan.py. The variable reaches the scanner through the
# sandbox, which keeps the environment.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PII_SCANNER="${SCRIPT_DIR}/pii-scan.py"
# Git reports a missing ref as an all-zeros object ID: 40 digits in SHA-1
# repositories, 64 in SHA-256 ones.
is_zero_id() { [[ "$1" =~ ^0+$ ]]; }
is_object_id() { [[ "$1" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; }

mode="${1:-}"
message_file=""
push_remote=""
case "$mode" in
  pre-commit) ;;
  pre-push)
    [[ -n "${2:-}" ]] || { echo "usage: $0 pre-push REMOTE" >&2; exit 2; }
    push_remote="$2"
    ;;
  commit-msg)
    [[ -n "${2:-}" && -f "$2" ]] || { echo "usage: $0 commit-msg MESSAGE_FILE" >&2; exit 2; }
    # Absolute, because the gate changes to the repository root below.
    message_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    ;;
  *) echo "usage: $0 pre-commit|commit-msg MESSAGE_FILE|pre-push REMOTE" >&2; exit 2 ;;
esac

for tool in gitleaks uv; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "FATAL: $tool is required for the PII and secret scans but not found on \$PATH." >&2
    exit 1
  fi
done

# --- Positive control for gitleaks ---
# A token in GitHub's personal-access-token format, generated at run time so
# no file in the repository holds a planted secret for gitleaks to report.
# The random input is read with a fixed size rather than streamed: Git runs
# hooks with SIGPIPE ignored, so a `tr </dev/urandom | head` pipeline never
# stops once head exits. 4096 random bytes leave about 990 alphanumerics, far
# more than the 36 the token needs.
control_secret_scan() {
  local token
  token="ghp_$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 36)"
  if [[ ${#token} -ne 40 ]]; then
    echo "FATAL: couldn't generate the gitleaks control token." >&2
    exit 1
  fi
  # A distinct exit code for "leaks found" separates detection from gitleaks
  # failing to run (e.g., a broken configuration), which also exits non-zero.
  # The token is checked through both modes the gate uses for content: stdin,
  # and a directory like the one the exported texts go in. The control file
  # lives in the scratch directory, which the EXIT trap removes.
  # The control uses the same gitleaks options as the scans, so it proves the
  # configuration actually in use.
  local status=0 control_dir="${scratch}/control"
  printf 'github_token = "%s"\n' "$token" \
    | gitleaks stdin "${gitleaks_opts[@]}" --log-level error --exit-code 42 >/dev/null 2>&1 \
    || status=$?
  check_control_status stdin "$status"
  mkdir -p "${control_dir}/000001"
  printf 'github_token = "%s"\n' "$token" >"${control_dir}/000001/content.txt"
  status=0
  gitleaks dir "$control_dir" "${gitleaks_opts[@]}" --log-level error --exit-code 42 >/dev/null 2>&1 \
    || status=$?
  rm -rf "$control_dir"
  check_control_status dir "$status"
  echo "Secret scan: control token detected."
}

check_control_status() {  # $1 = gitleaks mode, $2 = its exit status
  case "$2" in
    42) ;;
    0)  echo "FATAL: gitleaks ($1) missed its control token; its other results can't be trusted." >&2; exit 1 ;;
    *)  echo "FATAL: gitleaks ($1) failed (exit $2) while scanning its control token." >&2; exit 1 ;;
  esac
}

# Scan the texts the PII scanner exports (see the header) with gitleaks.
# $1 = a fresh directory name; the remaining arguments select what to export.
secret_scan_exported() {
  local dir="$1"; shift
  run_pii_offline --export-to "$dir" "$@"
  secret_scan "$dir" dir "$dir"
}

# Run one gitleaks scan with a JSON report, and stop the gate if it finds a
# leak or fails. --exit-code 42 tells a leak apart from gitleaks failing to
# run (as in control_secret_scan). The report's findings are printed by
# pii-scan.py, which needs the scanner's environment, so prepare_pii_scanner
# runs before any call. Each report gets its own file in the scratch
# directory, which the EXIT trap removes.
# $1 = the --export-to directory the scan covers, or "" for a Git or stdin
# scan; the remaining arguments = gitleaks' mode and its arguments.
secret_scan() {
  local exported="$1" status=0 report
  shift
  report="$(mktemp "${scratch}/gitleaks-report.XXXXXX")"
  gitleaks "$@" "${gitleaks_opts[@]}" --log-level warn --exit-code 42 \
    --report-format json --report-path "$report" || status=$?
  case "$status" in
    0) ;;
    42)
      echo "Secret scan: gitleaks found leaks (secrets redacted; fix or remove each):" >&2
      if ! run_pii_offline --gitleaks-report "$report" ${exported:+--exported "$exported"} >&2; then
        echo "  (couldn't list them; nothing from gitleaks' report is printed in their place)" >&2
      fi
      exit 1
      ;;
    *)
      echo "FATAL: gitleaks ($1) failed (exit ${status}); the secret scan didn't finish." >&2
      exit 1
      ;;
  esac
}

# Run a git command a gitleaks pass runs, discarding its output, and stop the
# gate if gitleaks would scan that output incompletely. gitleaks v8.30.1 never
# checks git's exit status (Fragments in sources/git.go logs Wait's error at
# debug level), so a failing git command (e.g., a textconv driver that fails,
# giving "fatal: unable to read files to diff") passes with exit 0. Any stderr
# line except the rename-limit and auto-packing notices listenForStdErr
# tolerates, empty lines included, makes Fragments return before the
# detectors finish, and gitleaks still exits 0: a textconv that only printed a
# warning and succeeded hid a token that the same scan without the warning
# found. So both a failure and an untolerated stderr line stop the gate.
# Callers pass gitleaks' arguments exactly, because the guard must fail
# whenever gitleaks' own run would; git config the gate doesn't control
# (e.g., a textconv or diff.ignoreSubmodules) applies to both runs alike. A
# textconv that fails only sometimes could still pass here and fail for
# gitleaks; the exported pass scans the same files regardless.
# $1 = what gitleaks scans, for the FATAL message; $2 = a file for git's
# stderr; the remaining arguments = the git command.
check_gitleaks_git() {
  local what="$1" err="$2" status=0 untolerated
  shift 2
  "$@" >/dev/null 2>"$err" || status=$?
  # Counted rather than captured, because command substitution would drop
  # empty lines, which gitleaks counts. grep exits 1 when the count is zero.
  untolerated="$(grep -cvF \
    -e 'exhaustive rename detection was skipped' \
    -e 'inexact rename detection was skipped' \
    -e 'you may want to set your diff.renameLimit' \
    -e 'See "git help gc" for manual housekeeping' \
    -e 'Auto packing the repository in background for optimum performance' \
    "$err")" || [[ $? -eq 1 ]]
  # git's stderr isn't printed, because a textconv driver or other configured
  # command can write file content there, which can hold a denylist term (see
  # the header); its line counts say enough to start looking.
  if [[ $status -ne 0 || "$untolerated" != 0 ]]; then
    echo "FATAL: the ${what} exited ${status} and wrote $(wc -l <"$err" | tr -d ' ') line(s) to" \
      "stderr, ${untolerated} of them other than notices gitleaks tolerates, and gitleaks passes" \
      "when either happens; stopping before the secret scan. A diff driver (e.g., a textconv)" \
      "or git config probably wrote to stderr; run the same git command yourself to see it:" \
      "$*" >&2
    exit 1
  fi
}

# Check a pre-push range before gitleaks scans it. gitleaks runs
# `git -C . log -p -U0 {log-opts}` (NewGitLogCmdContext, sources/git.go,
# gitleaks v8.30.1) and, when that git command fails, logs git's error and
# exits 0 (e.g., `gitleaks git --log-opts=no-such-ref .`), so given a range
# git rejects, the history pass wouldn't scan anything and would pass. The
# value is split the way gitleaks splits it, on each single space with empty
# fields kept (strings.Split(logOpts, " ")), and git must accept it and list
# exactly the commits the PII scan reads, so both scanners cover the same set.
#
# git rev-list never builds a diff, so it can't see a textconv that fails or
# warns while `git log -p` renders a pushed file; that git log then ends the
# history pass early with exit 0, as check_gitleaks_git explains. So the same
# git log runs here first, with gitleaks' arguments exactly (no
# --no-ext-diff, which gitleaks doesn't pass to git log). That repeats the
# git log -p work over the range: cheap for an ordinary push, but a push
# that scans a large repository's whole history (e.g., a new branch to a URL)
# pays for it twice. The cheaper checks run first, so a rejected range stops
# the gate before this one.
#
# The whole value is one argument to gitleaks. Linux caps one argument at 32
# pages (MAX_ARG_STRLEN; 128 KiB with 4 KiB pages), room for about 3,100
# distinct tracking-ref IDs in SHA-1 or 2,000 in SHA-256; past that, gitleaks
# fails to start and set -e stops the gate. macOS caps only the total
# (ARG_MAX, 1 MiB).
# $1 = the --log-opts value; $2 = the PII scan's commits (git rev-list output).
check_log_opts() {
  local words=() word listed
  # The appended space ends the last field; `read -d ' '` with an empty IFS
  # keeps empty fields and other whitespace as strings.Split does.
  while IFS= read -r -d ' ' word; do words+=("$word"); done <<<"$1 "
  if ! listed="$(git rev-list "${words[@]}")"; then
    echo "FATAL: git rejects the range gitleaks would scan (--log-opts=\"$1\"), and gitleaks" \
      "passes when its git log fails; stopping before the secret scan." >&2
    exit 1
  fi
  if [[ "$listed" != "$2" ]]; then
    echo "FATAL: the range gitleaks would scan (--log-opts=\"$1\") lists different commits than" \
      "the PII scan reads; stopping before the secret scan." >&2
    exit 1
  fi
  check_gitleaks_git "git log gitleaks scans for this range (--log-opts=\"$1\")" \
    "${scratch}/history-log.err" git -C . log -p -U0 "${words[@]}"
}

# Run the git diff the pre-commit gitleaks pass runs, and stop the gate if
# gitleaks would scan it incompletely (see check_gitleaks_git). gitleaks
# v8.30.1 runs `git -C . diff -U0 --no-ext-diff --staged .`
# (NewGitDiffCmdContext, sources/git.go); the guard passes it without
# --ignore-submodules for the reason check_gitleaks_git gives.
check_staged_diff() {
  check_gitleaks_git "git diff gitleaks scans for staged changes" \
    "${scratch}/staged-diff.err" git -C . diff -U0 --no-ext-diff --staged .
}

# Set fetch_dsts to the destination patterns of remote $1's fetch refspecs
# (remote.{name}.fetch, e.g., refs/remotes/{name}/* from
# +refs/heads/*:refs/remotes/{name}/*), i.e., the refs a fetch from it
# writes. A global array rather than output, because a FATAL inside command
# substitution would end only the subshell.
fetch_destinations() {
  local refspecs status=0 spec
  fetch_dsts=()
  refspecs="$(git config --get-all "remote.${1}.fetch")" || status=$?
  if [[ $status -eq 1 ]]; then
    return 0  # git config exits 1 when the key is absent: no fetch refspecs
  fi
  if [[ $status -ne 0 ]]; then
    # The remote isn't named, because a remote name can hold a denylist term
    # (see the header); the command in the message lists them all.
    echo "FATAL: couldn't read the fetch refspecs of a configured remote (git config exit ${status});" \
      "nothing was scanned. To find it, run: git config --get-regexp '^remote\\..*\\.fetch\$'" >&2
    exit 1
  fi
  while IFS= read -r spec; do
    spec="${spec#+}"
    # A negative refspec (^{pattern}) only narrows what the others fetch, and
    # one without a destination (no colon, or nothing after it) doesn't
    # store anything beyond FETCH_HEAD. Git rejects a pattern with more than one *
    # (every remote command, `git remote` included, then fails with "invalid
    # refspec", stopping the gate earlier), so one is skipped here only as a
    # fallback.
    if [[ "$spec" == "^"* || "$spec" != *:* ]]; then continue; fi
    spec="${spec#*:}"
    if [[ -z "$spec" || "$spec" == *"*"*"*"* ]]; then continue; fi
    fetch_dsts+=("$spec")
  done <<<"$refspecs"
}

# Succeed when ref $1 matches refspec destination $2. The comparison is
# literal except for the destination's one `*`, which matches any run of
# characters, slashes included, as a fetch stores refs/heads/{x}/{y} under
# refs/remotes/{remote}/{x}/{y}. Characters in a remote name or refspec
# never act as glob or regex syntax, because quoted expansions inside
# [[ == ]] match literally.
matches_destination() {
  local prefix suffix
  if [[ "$2" != *"*"* ]]; then
    [[ "$1" == "$2" ]]
    return
  fi
  prefix="${2%%\**}"
  suffix="${2#*\*}"
  [[ ${#1} -ge $((${#prefix} + ${#suffix})) && "$1" == "$prefix"* && "$1" == *"$suffix" ]]
}

# --- PII scanner, offline ---
# How the scanner is cut off from the network, decided by choose_pii_sandbox
# after the dependencies are installed, because the macOS decision may need
# to run the scanner itself:
#   sandbox-exec  the gate's own Seatbelt profile (macOS);
#   bwrap         bubblewrap with its own network namespace, holding only
#                 loopback (Linux, where Claude Code's sandbox already
#                 requires it);
#   outer         no wrapper, because the gate already runs inside a macOS
#                 sandbox that sandbox-exec can't start within, and that
#                 sandbox removes network access itself;
#   none          neither tool is available; the gate warns and scans
#                 offline without a sandbox.
# pii_sandbox holds the command prefix for the first two and stays empty for
# the others. The isolation check in prepare_pii_scanner runs in every mode
# except none, so `outer` is accepted only when the scanner, run the same
# unwrapped way the scans run, finds that it doesn't have network access.
pii_sandbox=()
pii_isolation=none
PII_SANDBOX_PROFILE='(version 1)(allow default)(deny network*)'

choose_pii_sandbox() {
  if command -v sandbox-exec >/dev/null 2>&1; then
    # Probed with a no-op rather than assumed to work: macOS doesn't let
    # sandbox-exec start inside another Seatbelt sandbox (e.g., an agent
    # committing from Claude Code's sandboxed Bash), where it exits 71 with
    # "sandbox_apply: Operation not permitted".
    local status=0 reason sandboxed=0
    sandbox-exec -p "$PII_SANDBOX_PROFILE" true 2>"${scratch}/sandbox-exec.err" || status=$?
    if [[ $status -eq 0 ]]; then
      pii_sandbox=(sandbox-exec -p "$PII_SANDBOX_PROFILE")
      pii_isolation=sandbox-exec
      return
    fi
    reason="$(head -n 1 "${scratch}/sandbox-exec.err")"
    # A failure to start isn't by itself evidence of an outer sandbox, so the
    # scanner checks directly; only a positive answer counts, and "can't
    # tell" fails the gate like "not sandboxed".
    uv run --quiet --offline "$PII_SCANNER" --check-sandboxed || sandboxed=$?
    if [[ $sandboxed -ne 0 ]]; then
      echo "FATAL: sandbox-exec failed to start (exit ${status}: ${reason:-no error message})," \
        "and this process isn't inside another sandbox (or that couldn't be checked), so the" \
        "PII scan can't be isolated from the network; nothing was scanned." >&2
      exit 1
    fi
    pii_isolation=outer
  elif command -v bwrap >/dev/null 2>&1 \
      && bwrap --dev-bind / / --unshare-net --die-with-parent true >/dev/null 2>&1; then
    # The probe runs a no-op, because some distributions restrict the user
    # namespaces bubblewrap needs, and then it can't start at all.
    pii_sandbox=(bwrap --dev-bind / / --unshare-net --die-with-parent)
    pii_isolation=bwrap
  fi
}

run_pii_offline() {
  ${pii_sandbox[@]+"${pii_sandbox[@]}"} uv run --quiet --offline "$PII_SCANNER" "$@"
}

prepare_pii_scanner() {
  # An online sync contacts the network even when the environment is already
  # installed (e.g., to fetch the spaCy model's URL dependency), so without a
  # network it fails and would block every commit and push. Retry from uv's
  # cache; if that fails too, the dependencies are missing and set -e stops
  # the gate.
  if ! uv sync --quiet --script "$PII_SCANNER"; then
    echo "WARNING: couldn't sync the PII scanner's dependencies online; retrying offline from uv's cache." >&2
    uv sync --quiet --offline --script "$PII_SCANNER"
  fi
  choose_pii_sandbox
  if [[ "$pii_isolation" != none ]]; then
    # The sandbox's own positive control: a scanner that can still reach the
    # network means the sandbox didn't take effect, so nothing runs.
    if ! run_pii_offline --check-isolation; then
      if [[ "$pii_isolation" == outer ]]; then
        echo "FATAL: sandbox-exec can't start inside another sandbox, and the outer sandbox allows" \
          "network access, so the PII scan can't be isolated; nothing was scanned. Run the commit or" \
          "push from a shell outside that sandbox (e.g., not from Claude Code's sandboxed Bash)." >&2
      else
        echo "FATAL: the PII scanner's sandbox didn't remove network access; nothing was scanned." >&2
      fi
      exit 1
    fi
    if [[ "$pii_isolation" == outer ]]; then
      echo "PII scan: an outer sandbox removes network access; sandbox-exec can't start inside it," \
        "so the scan runs within that sandbox without its own."
    fi
  else
    echo "WARNING: neither sandbox-exec nor a working bwrap is available, so the PII scan runs" \
      "offline but without a network sandbox. Install bubblewrap to add one." >&2
  fi
  echo "PII scan: checking detectors against the control fixture..."
  run_pii_offline --control
}

cd "$REPO_ROOT"

# Scratch space for the exported texts, the gitleaks control, and the gitleaks
# configuration, removed on every exit so no exported copy of repository
# content or control token stays on disk. The template is absolute because
# bare `mktemp -d` ignores TMPDIR on macOS (see install-and-verify.sh).
tmp_root="${TMPDIR:-/tmp}"
scratch="$(mktemp -d "${tmp_root%/}/pii-secret-gate.XXXXXXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# gitleaks reads a .gitleaks.toml, a .gitleaksignore, and gitleaks:allow
# comments from what it scans, so content being scanned could otherwise decide
# what the scan reports. The gate supplies its own configuration (gitleaks'
# default rules, nothing more) and an empty ignore directory instead.
# --no-color, because gitleaks colors its log lines even when they go to a
# pipe, and the escape codes would land in transcripts; a code inside a term
# would also split it where the hooks' output filter can't match it.
mkdir -p "${scratch}/gitleaks-ignore"
printf '[extend]\nuseDefault = true\n' >"${scratch}/gitleaks.toml"
gitleaks_opts=(--config "${scratch}/gitleaks.toml" --gitleaks-ignore-path "${scratch}/gitleaks-ignore"
  --ignore-gitleaks-allow --no-banner --no-color --redact)

if [[ "$mode" == "pre-commit" ]]; then
  # --ignore-submodules=none, because diff.ignoreSubmodules=all or
  # submodule.{name}.ignore=all would hide a staged submodule pointer change,
  # and the gate would exit here without scanning its path (see
  # SHOW_SUBMODULES in pii-scan.py). --no-textconv and --no-ext-diff, because
  # this check needs only whether blobs differ: a textconv driver would run
  # here with its stderr reaching the terminal (and the transcript), and one
  # that renders two different blobs alike would hide the change.
  if git diff --cached --quiet --no-textconv --no-ext-diff --ignore-submodules=none --diff-filter=ACMRT; then
    exit 0  # nothing staged records new content
  fi
  control_secret_scan
  prepare_pii_scanner  # before any secret_scan, which reports through it
  echo "Secret scan: staged changes..."
  check_staged_diff
  secret_scan "" git --pre-commit --staged .
  echo "Secret scan: staged files, every decoding, and their paths..."
  secret_scan_exported "${scratch}/staged" --staged
  echo "PII scan: staged files..."
  run_pii_offline --staged
  exit 0
fi

if [[ "$mode" == "commit-msg" ]]; then
  control_secret_scan
  prepare_pii_scanner  # before secret_scan, which reports through it
  echo "Secret scan: commit message and identities..."
  { git var GIT_AUTHOR_IDENT; git var GIT_COMMITTER_IDENT; echo; cat "$message_file"; } \
    | secret_scan "" stdin
  echo "PII scan: commit message and identities..."
  run_pii_offline --message-file "$message_file"
  exit 0
fi

# --- pre-push: work out what each pushed ref publishes ---
# All of stdin is read first, because the scanners started for each ref below
# would otherwise consume the remaining pre-push lines.
push_lines=()
while read -r line; do
  [[ -n "$line" ]] && push_lines+=("$line")
done

# For each ref: the gitleaks Git range, the commits it lists, a description,
# and the scanner arguments (the commits, annotated tags, ref name, and
# allowlist revision), stored as parallel arrays because bash 3.2 doesn't have
# nested arrays.
ref_ranges=()
ref_commits=()
ref_descs=()
ref_args=()
# Messages name a ref by its line in the pre-push input (blank lines not
# counted), not by name, because a ref name can hold a denylist term (see the
# header).
line_number=0
for line in ${push_lines[@]+"${push_lines[@]}"}; do
  line_number=$((line_number + 1))
  # Parsed from the right: Git writes the local ref as the user typed it, which
  # can contain spaces (e.g., `git push origin ':/fix 0:refs/heads/x'`), while
  # the remote ref and both object IDs can't. Anything that doesn't parse to
  # two object IDs stops the gate rather than being skipped.
  remote_sha="${line##* }"; rest="${line% *}"
  remote_ref="${rest##* }"; rest="${rest% *}"
  local_sha="${rest##* }"
  if ! is_object_id "$local_sha" || ! is_object_id "$remote_sha"; then
    echo "FATAL: couldn't parse pre-push line ${line_number}; nothing was scanned." >&2
    exit 1
  fi
  is_zero_id "$local_sha" && continue  # a deletion doesn't publish anything
  # A pushed tag object (possibly a tag of a tag) publishes its name, tagger,
  # and message as well as what it points at; collect each tag object and
  # peel to the commit, one level at a time so a tag of a tag adds both.
  # The object line is always a tag object's first line. sed reads the whole
  # tag: one that quit early would leave git writing a long message into a
  # closed pipe, and git's exit status 141 would stop the gate under pipefail.
  args=(--ref "$remote_ref")
  object="$local_sha"
  while [[ "$(git cat-file -t "$object")" == "tag" ]]; do
    args+=(--tag "$object")
    object="$(git cat-file tag "$object" | sed -n '1s/^object //p')"
  done
  object_type="$(git cat-file -t "$object")"
  if [[ "$object_type" != "commit" ]]; then
    echo "FATAL: the ref on pre-push line ${line_number} points at a ${object_type}; the gate scans only commits and tags of commits." >&2
    exit 1
  fi
  # A new ref, or a remote tip this repository doesn't have (e.g., a force
  # push over commits never fetched), can't anchor a remote..local range, so
  # scan everything the destination remote's tracking refs don't already hold.
  # Commits held only by other remotes are scanned, because they may come from
  # a private remote and be published for the first time by this push. When
  # REMOTE isn't a configured remote (e.g., a URL), there are no tracking refs
  # to trust, so the whole history of the pushed tip is scanned.
  #
  # Tracking refs record what a fetch from the remote's first URL found, so
  # they say what the push destination holds only when the push goes to that
  # same URL alone. A remote can push elsewhere (e.g., a pushurl naming a
  # different repository, or several url or pushurl entries, each of which
  # receives the push), and then the whole history is scanned too. The URLs
  # are compared as `git remote get-url` reports them, after insteadOf and
  # pushInsteadOf rewriting, so one repository reached by different URLs for
  # fetch and push (e.g., HTTPS and SSH) also counts as different; that costs
  # a longer scan, never a missed commit.
  #
  # Tracking refs can also be stale, and the gate can't tell: after
  # `git remote set-url` points the remote at a different repository, they
  # still record the old one until the next fetch, and after another client
  # rewinds or deletes a remote branch, they still name commits the remote no
  # longer holds. A push of a new ref, or over a tip this repository doesn't
  # have, then publishes those commits without scanning them. Fetch (with
  # --prune) before such a push in either case.
  #
  # The remote's tracking refs are the refs its fetch refspecs write (see
  # fetch_destinations), not every ref under refs/remotes/{remote}/: Git
  # names remotes with slashes (e.g., `a` and `a/b`, which `git remote add`
  # refuses together but `git config remote.a/b.url {url}` allows), and
  # refs/remotes/a/* also covers refs/remotes/a/b/*, so a prefix match
  # would trust commits only `a/b` holds when pushing to `a` and publish them
  # unscanned. A ref that another remote's refspecs could also write isn't
  # trusted either, because it may record that other remote's commits. With
  # `a` and `a/b` at their default refspecs, a push to `a` scans what only
  # `a/b` holds, a branch of `a` named `b/{name}` (stored where `a/b`'s refs
  # are) isn't trusted, and a push to `a/b` scans the whole history, because
  # `a`'s refspec covers every `a/b` ref; that costs a longer scan, never a
  # missed commit.
  # Only refs under refs/remotes/ count, because a refspec can write
  # elsewhere (e.g., `+refs/*:refs/*` for a fetch mirror writes
  # refs/heads/*), and local commits move those refs too. A remote without
  # fetch refspecs doesn't have tracking refs, so the whole history is scanned.
  # Remotes defined in the legacy .git/remotes/ files keep their refspecs
  # outside git config, so the overlap check doesn't see them.
  #
  # The tracking refs enter the range as the object IDs they name (^{id}),
  # not as --remotes=REMOTE, because the range also reaches gitleaks as one
  # space-separated --log-opts string, and a remote name can hold a space:
  # `git remote add` refuses one, but `git config 'remote.{a b}.url' {url}`
  # doesn't, and `git remote` then lists it. Its refspec can't name
  # refs/remotes/{a b}/* (Git forbids spaces in ref names), though one
  # writing elsewhere (e.g., refs/remotes/{ab}/*) works. Refs are matched by
  # matches_destination rather than through a for-each-ref pattern, because
  # a remote name or refspec holding glob characters (e.g., `?` or `[`)
  # would turn the pattern into a glob. Several tracking refs often name one
  # commit (e.g., refs/remotes/{remote}/HEAD), so each ID is listed once.
  if is_zero_id "$remote_sha" || ! git cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
    fetch_url="" push_urls=""
    # Assigned on its own line so a failure stops the gate. grep without -q
    # reads all of its input; with -q, a remote list longer than a pipe's
    # buffer would fail printf, and pipefail would make the gate treat a
    # configured remote as unconfigured.
    remotes="$(git remote)"
    if printf '%s\n' "$remotes" | grep -xF -- "$push_remote" >/dev/null; then
      # Assigned on their own lines so a get-url failure stops the gate (set -e)
      # rather than leaving two empty strings that compare equal.
      fetch_url="$(git remote get-url -- "$push_remote")"
      push_urls="$(git remote get-url --push --all -- "$push_remote")"
    fi
    range=("$object")
    range_desc="${object} and its history"
    if [[ -n "$fetch_url" && "$push_urls" == "$fetch_url" ]]; then
      fetch_destinations "$push_remote"
      own_dsts=(${fetch_dsts[@]+"${fetch_dsts[@]}"})
      other_dsts=()
      while IFS= read -r name; do
        if [[ -n "$name" && "$name" != "$push_remote" ]]; then
          fetch_destinations "$name"
          other_dsts+=(${fetch_dsts[@]+"${fetch_dsts[@]}"})
        fi
      done <<<"$remotes"
      # Assigned on its own line so a for-each-ref failure stops the gate.
      tracking="$(git for-each-ref --format='%(objectname) %(refname)' refs/remotes/)"
      tracked_ids=""
      while read -r id ref; do
        trusted=0
        for dst in ${own_dsts[@]+"${own_dsts[@]}"}; do
          if [[ -n "$id" ]] && matches_destination "$ref" "$dst"; then trusted=1; break; fi
        done
        for dst in ${other_dsts[@]+"${other_dsts[@]}"}; do
          if [[ $trusted -eq 1 ]] && matches_destination "$ref" "$dst"; then trusted=0; break; fi
        done
        if [[ $trusted -eq 1 ]]; then
          tracked_ids+="${id}"$'\n'
        fi
      done <<<"$tracking"
      excluded=0
      while read -r id; do
        if [[ -n "$id" ]]; then
          range+=("^${id}")
          excluded=$((excluded + 1))
        fi
      done <<<"$(printf '%s' "$tracked_ids" | sort -u)"
      if [[ $excluded -gt 0 ]]; then
        range_desc="${object}, without the ${excluded} commit(s) the remote's tracking refs name and their history"
      fi
    fi
  else
    range=("${remote_sha}..${object}")
    range_desc="${range[0]}"
  fi
  # Listed outside a process substitution so a git failure stops the gate
  # instead of producing an empty list that reads as "nothing to scan".
  if ! listed="$(git rev-list "${range[@]}")"; then
    echo "FATAL: couldn't list the commits for ${range[*]}; nothing was scanned." >&2
    exit 1
  fi
  while read -r commit; do
    [[ -n "$commit" ]] && args+=(--commit "$commit")
  done <<<"$listed"
  args+=(--allowlist-rev "$object")
  # The range is stored as the exact --log-opts string gitleaks receives, and
  # the commit list beside it, so check_log_opts can compare the two.
  ref_ranges+=("${range[*]}")
  ref_commits+=("$listed")
  ref_descs+=("$range_desc")
  # Every element of args and range is a ref name, an object ID (bare, with a
  # leading ^, or as A..B), or an option, none of which can contain whitespace
  # (Git forbids it in ref names; a remote name, which can hold a space when
  # set through git config, appears in neither). So the space-joined args
  # round-trip through word splitting below, and gitleaks' split of the range
  # string yields the elements of range.
  ref_args+=("${args[*]}")
done

if [[ ${#ref_args[@]} -eq 0 ]]; then
  echo "PII and secret scans: the push doesn't publish anything new to scan."
  exit 0
fi

control_secret_scan
prepare_pii_scanner
for i in "${!ref_args[@]}"; do
  # shellcheck disable=SC2206  # intentional word splitting; see above
  args=(${ref_args[$i]})
  echo "Secret scan: ${ref_descs[$i]}..."
  check_log_opts "${ref_ranges[$i]}" "${ref_commits[$i]}"
  secret_scan "" git --log-opts="${ref_ranges[$i]}" .
  echo "Secret scan: every decoding of the pushed files, paths, messages, tags, and ref name..."
  secret_scan_exported "${scratch}/ref-${i}" "${args[@]}"
  echo "PII scan: ${ref_descs[$i]}..."
  run_pii_offline "${args[@]}"
done

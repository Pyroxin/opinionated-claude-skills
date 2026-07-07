#!/usr/bin/env bash

###
#   harden-claude-config.sh
#
#   Merge Claude Code privacy and sandbox hardening into a settings.json. MERGES, never
#   overwrites: existing settings and unrelated env vars are preserved; only the
#   keys this tool manages are touched.
#
#   Previews by default — writes nothing unless you pass --write (-w).
#
#   Symlink-safe: if the target is a symlink, the file it points at is updated and
#   the link is preserved. A run that would change nothing writes nothing.
#
#   The model is compositional. The base is the full hardening set; each flag
#   either ADDS a key or RELAXES a channel. Relaxations pin an explicit "off"
#   value where one exists, so the config stays robust to future default changes.
#   Attribution has two channels: commit/PR model/tool attribution and remote
#   session URL attribution. They are separate because the former is useful
#   project provenance, while the latter identifies a shareable session.
#
#   BASE (no flags) — maximum lockdown:
#     env:
#       CLAUDE_CODE_ENABLE_TELEMETRY=0, DISABLE_TELEMETRY=1, DISABLE_ERROR_REPORTING=1,
#       DISABLE_FEEDBACK_COMMAND=1, CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1,
#       DISABLE_AUTOUPDATER=1, DO_NOT_TRACK=1, CLAUDE_CODE_ENABLE_AUTO_MODE=0, and the
#       OTel SDK/exporters off with the content + identifier gates pinned disabled.
#     settings (top-level):
#       skipWebFetchPreflight=true            don't send each fetched hostname to api.anthropic.com
#       attribution={"commit":"","pr":"","sessionUrl":false}
#                                               strip commit/PR/session attribution
#     sandbox (managed one level deep, like env: sibling subkeys you add by hand,
#     e.g. excludedCommands or network, survive re-runs; "credentials" is written
#     as one unit and needs Claude Code >= 2.1.187):
#       enabled=true                          OS-enforced Bash sandbox (macOS: Seatbelt;
#                                             Linux/WSL2: bubblewrap + socat)
#       autoAllowBashIfSandboxed=false        sandboxed commands still use the regular
#                                             permission flow in every permission mode
#       credentials.files                     read-deny ~/.ssh, ~/.aws, ~/.gnupg, ~/.netrc
#                                             inside the sandbox; tools that need them fall
#                                             back to an unsandboxed retry behind a prompt
#
#   RELAX flags:
#     --allow-updates              env DISABLE_AUTOUPDATER=0. CLI + plugins auto-update.
#     --allow-feedback             env DISABLE_FEEDBACK_COMMAND=0 + CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=0.
#                                  (Surveys still won't appear: DISABLE_TELEMETRY + DO_NOT_TRACK
#                                  suppress them independently of the survey flag.)
#     --allow-webfetch-preflight   settings skipWebFetchPreflight=false. Restores the WebFetch
#                                  domain safety check (the hostname preflight to Anthropic).
#     --allow-model-attribution    Allow commit/PR model/tool attribution while keeping
#                                  attribution.sessionUrl=false.
#     --allow-session-attribution  Allow session URL attribution. Combine with
#                                  --allow-model-attribution to use Claude Code's full default.
#     --allow-auto-mode            env CLAUDE_CODE_ENABLE_AUTO_MODE=1: let the user cycle into
#                                  the "auto" permission mode. The variable gates availability
#                                  on Bedrock/Vertex/Foundry/gateway providers; on the Anthropic
#                                  API auto mode is available regardless of it, and only managed
#                                  settings (permissions.disableAutoMode) can forbid it there.
#     --allow-sandbox-auto-allow   sandbox autoAllowBashIfSandboxed=true: sandboxed Bash runs
#                                  without permission prompts in every permission mode (the
#                                  sandbox's own auto-allow, independent of the "auto"
#                                  permission mode). The base pins this false on every run, so
#                                  use this flag rather than hand-editing to keep it true.
#     --disable-sandbox            Pin sandbox.enabled=false. Other sandbox keys are left in
#                                  place (inert while disabled). Overrides
#                                  --allow-sandbox-auto-allow.
#
#     The "0" off-value relies on Claude Code's value parser — documented for sibling vars
#     (CLAUDE_CODE_DISABLE_AUTO_MEMORY, CLAUDE_CODE_ENABLE_AWAY_SUMMARY), inferred for these.
#
#   ADD flags:
#     --allow-only-plugin-updates     env DISABLE_AUTOUPDATER=1 + FORCE_AUTOUPDATE_PLUGINS=1
#                                     ("binary manual, plugins fresh"; overrides --allow-updates).
#     --disable-nonessential-traffic  env + CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 (future-proof layer;
#                                     re-pins env-governed optional traffic channels after relaxation).
#     --enable-1h-cache               env + ENABLE_PROMPT_CACHING_1H=1 (Bedrock/API-key; no-op on subscription).
#
#   Operational:
#     -w, --write       Apply the changes. Without it the script only previews.
#     -n, --dry-run     Preview only (the default; wins over --write if both are given).
#         --no-backup   Skip the timestamped backup of the target.
#     -h, --help        Show this help and exit.
#
#   Path: defaults to ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json; override
#   by passing one path argument.
#
#   Requires: jq. Runs on macOS and Linux (POSIX-ish bash; no bash 4 features).
###

set -euo pipefail

_info()  { printf '%s\n' "$*"; }
_die()   { printf 'error: %s\n' "$*" >&2; exit 1; }

_usage() {
  # Print the leading comment block (between the first two ### markers) as help.
  sed -n '/^###$/,/^###$/p' "$0" | sed '1d;$d;s/^#\{0,1\} \{0,1\}//'
}

_resolve_symlink_target() {
  link_target="$(readlink "$1")" || _die "could not read symlink: $1"
  case "$link_target" in
    /*) printf '%s\n' "$link_target" ;;
    *)  printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$link_target" ;;
  esac
}

_file_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

# --- The hardening base. Edit here to evolve the shared posture. --------------
CORE_ENV='{
  "CLAUDE_CODE_ENABLE_TELEMETRY": "0",
  "DISABLE_TELEMETRY": "1",
  "DISABLE_ERROR_REPORTING": "1",
  "DISABLE_FEEDBACK_COMMAND": "1",
  "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
  "DISABLE_AUTOUPDATER": "1",
  "DO_NOT_TRACK": "1",
  "CLAUDE_CODE_ENABLE_AUTO_MODE": "0",
  "OTEL_SDK_DISABLED": "true",
  "OTEL_PROPAGATORS": "none",
  "OTEL_TRACES_EXPORTER": "none",
  "OTEL_LOG_LEVEL": "error",
  "OTEL_METRICS_EXEMPLAR_FILTER": "always_off",
  "OTEL_TRACES_SAMPLER": "always_off",
  "OTEL_LOG_USER_PROMPTS": "0",
  "OTEL_LOG_TOOL_DETAILS": "0",
  "OTEL_LOG_TOOL_CONTENT": "0",
  "OTEL_LOG_RAW_API_BODIES": "0",
  "OTEL_METRICS_INCLUDE_SESSION_ID": "false",
  "OTEL_METRICS_INCLUDE_VERSION": "false",
  "OTEL_METRICS_INCLUDE_ACCOUNT_UUID": "false",
  "OTEL_METRICS_INCLUDE_ENTRYPOINT": "false",
  "OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES": "false",
  "OTEL_METRIC_EXPORT_INTERVAL": "315569520"
}'

# Top-level settings keys (outside the env block).
CORE_TOP='{
  "skipWebFetchPreflight": true,
  "attribution": { "commit": "", "pr": "", "sessionUrl": false }
}'

# The Bash sandbox posture: OS-enforced boundaries with prompts still governed by
# the permission mode (autoAllowBashIfSandboxed=false), and credential paths made
# unreadable inside the sandbox — tools that need them fall back to an unsandboxed
# retry behind a permission prompt. Merged one level deep (like env) so hand-added
# sibling subkeys survive re-runs; "credentials" is replaced as one unit.
CORE_SANDBOX='{
  "enabled": true,
  "autoAllowBashIfSandboxed": false,
  "credentials": {
    "files": [
      { "path": "~/.ssh", "mode": "deny" },
      { "path": "~/.aws", "mode": "deny" },
      { "path": "~/.gnupg", "mode": "deny" },
      { "path": "~/.netrc", "mode": "deny" }
    ]
  }
}'

# --- Parse arguments ----------------------------------------------------------
do_write=0
dry_run_explicit=0
do_backup=1
allow_updates=0
allow_feedback=0
allow_webfetch_preflight=0
allow_model_attribution=0
allow_session_attribution=0
allow_auto_mode=0
allow_sandbox_auto_allow=0
disable_sandbox=0
allow_only_plugin=0
disable_nonessential=0
enable_1h=0
target=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -w|--write)                     do_write=1 ;;
    -n|--dry-run)                   dry_run_explicit=1 ;;
    --no-backup)                    do_backup=0 ;;
    --allow-updates)                allow_updates=1 ;;
    --allow-feedback)               allow_feedback=1 ;;
    --allow-webfetch-preflight)     allow_webfetch_preflight=1 ;;
    --allow-model-attribution)      allow_model_attribution=1 ;;
    --allow-session-attribution)    allow_session_attribution=1 ;;
    --allow-auto-mode)              allow_auto_mode=1 ;;
    --allow-sandbox-auto-allow)     allow_sandbox_auto_allow=1 ;;
    --disable-sandbox)              disable_sandbox=1 ;;
    --allow-only-plugin-updates)    allow_only_plugin=1 ;;
    --disable-nonessential-traffic) disable_nonessential=1 ;;
    --enable-1h-cache)              enable_1h=1 ;;
    -h|--help)                      _usage; exit 0 ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        [ -z "$target" ] || _die "more than one path given"
        target="$1"; shift
      done
      break
      ;;
    -*)                             _usage >&2; _die "unknown option: $1" ;;
    *)
      [ -z "$target" ] || _die "more than one path given ('$target' and '$1')"
      target="$1"
      ;;
  esac
  shift
done

target="${target:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"

# An explicit --dry-run always wins over --write.
[ "$dry_run_explicit" -eq 1 ] && do_write=0

# --- Preconditions ------------------------------------------------------------
command -v jq >/dev/null 2>&1 || _die "jq is required but not found (macOS: brew install jq; Fedora: sudo dnf install jq)"

# --- Compose the hardening from the flags -------------------------------------
# ENV_SET / TOP_SET = keys to write. TOP_UNSET = top-level keys to delete (the
# attribution relaxation, whose "relaxed" state is "use the product default").
# Everything else is additive; later values win, so re-runs are idempotent.
ENV_SET="$CORE_ENV"
TOP_SET="$CORE_TOP"
SANDBOX_SET="$CORE_SANDBOX"
TOP_UNSET='[]'

_env() { ENV_SET="$(jq -n --argjson a "$ENV_SET" --argjson b "$1" '$a + $b')"; }
_top() { TOP_SET="$(jq -n --argjson a "$TOP_SET" --argjson b "$1" '$a + $b')"; }
_sandbox() { SANDBOX_SET="$(jq -n --argjson a "$SANDBOX_SET" --argjson b "$1" '$a + $b')"; }
_top_del() {
  TOP_SET="$(jq --arg k "$1" 'del(.[$k])' <<<"$TOP_SET")"
  TOP_UNSET="$(jq -n --argjson a "$TOP_UNSET" --arg k "$1" '($a + [$k]) | unique')"
}

[ "$allow_updates" -eq 1 ]            && _env '{"DISABLE_AUTOUPDATER": "0"}'
[ "$allow_feedback" -eq 1 ]           && _env '{"DISABLE_FEEDBACK_COMMAND": "0", "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "0"}'
[ "$allow_only_plugin" -eq 1 ]        && _env '{"DISABLE_AUTOUPDATER": "1", "FORCE_AUTOUPDATE_PLUGINS": "1"}'
[ "$enable_1h" -eq 1 ]                && _env '{"ENABLE_PROMPT_CACHING_1H": "1"}'
[ "$allow_webfetch_preflight" -eq 1 ] && _top '{"skipWebFetchPreflight": false}'
[ "$allow_auto_mode" -eq 1 ]          && _env '{"CLAUDE_CODE_ENABLE_AUTO_MODE": "1"}'
[ "$allow_sandbox_auto_allow" -eq 1 ] && _sandbox '{"autoAllowBashIfSandboxed": true}'
# Disabling the sandbox resets the managed subkeys to the pinned "off" alone, so it
# overrides --allow-sandbox-auto-allow; hand-added sandbox subkeys still merge through.
[ "$disable_sandbox" -eq 1 ]          && SANDBOX_SET='{"enabled": false}'

if [ "$allow_model_attribution" -eq 1 ] && [ "$allow_session_attribution" -eq 1 ]; then
  _top_del 'attribution'
elif [ "$allow_model_attribution" -eq 1 ]; then
  _top '{"attribution": {"sessionUrl": false}}'
elif [ "$allow_session_attribution" -eq 1 ]; then
  _top '{"attribution": {"commit": "", "pr": ""}}'
fi

# Nonessential traffic is an additive umbrella switch in Claude Code, but this
# script also writes the concrete switches so the JSON remains explicit
# and internally consistent after any earlier relaxation flag.
[ "$disable_nonessential" -eq 1 ]     && _env '{
  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
  "DISABLE_TELEMETRY": "1",
  "DISABLE_ERROR_REPORTING": "1",
  "DISABLE_FEEDBACK_COMMAND": "1",
  "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
  "DISABLE_AUTOUPDATER": "1",
  "DO_NOT_TRACK": "1"
}'

# --- Load and validate the target --------------------------------------------
if [ -e "$target" ]; then
  [ ! -d "$target" ] || _die "$target is a directory, not a JSON file; refusing to touch it"
  [ -r "$target" ] || _die "$target is not readable; refusing to touch it"
  jq empty "$target" >/dev/null 2>&1 || _die "$target exists but is not valid JSON; refusing to touch it"
  current="$(cat "$target")"
else
  if [ "$do_write" -eq 1 ]; then
    _info "note: $target does not exist; it will be created."
  else
    _info "note: $target does not exist; re-run with --write to create it."
  fi
  current='{}'
fi

current_type="$(printf '%s' "$current" | jq -r 'type')"
[ "$current_type" = "object" ] \
  || _die "existing top-level JSON is a $current_type, not an object; refusing to merge"

env_type="$(printf '%s' "$current" | jq -r '.env | type')"
[ "$env_type" = "object" ] || [ "$env_type" = "null" ] \
  || _die "existing .env is a $env_type, not an object; refusing to merge"

sandbox_type="$(printf '%s' "$current" | jq -r '.sandbox | type')"
[ "$sandbox_type" = "object" ] || [ "$sandbox_type" = "null" ] \
  || _die "existing .sandbox is a $sandbox_type, not an object; refusing to merge"

current_env="$(printf '%s' "$current" | jq -c '.env // {}')"
current_sandbox="$(printf '%s' "$current" | jq -c '.sandbox // {}')"

# --- Report the diff ----------------------------------------------------------
# Emits "+ added", "~ changed: old -> new", "= unchanged", "- removed" per key.
_diff_set() {  # $1 = current object, $2 = desired SET object, $3 = indent
  jq -nr --argjson cur "$1" --argjson set "$2" --arg pad "$3" '
    ($set | keys_unsorted)[] as $k
    | if   ($cur | has($k) | not) then "\($pad)+ \($k) = \($set[$k])"
      elif ($cur[$k] != $set[$k])  then "\($pad)~ \($k): \($cur[$k]) -> \($set[$k])"
      else                              "\($pad)= \($k) (unchanged)"
      end'
}

_info "Hardening changes for $target:"
_info "  env:"
_diff_set "$current_env" "$ENV_SET" "    "
_info "  sandbox:"
_diff_set "$current_sandbox" "$SANDBOX_SET" "    "
_info "  settings:"
_diff_set "$current" "$TOP_SET" "    "
jq -nr --argjson cur "$current" --argjson unset "$TOP_UNSET" '
  $unset[] as $k | select($cur | has($k)) | "    - \($k) (removed, was \($cur[$k]))"'

# --- Merge (set env + top-level keys, delete relaxed top-level keys) ----------
merged="$(printf '%s' "$current" | jq \
  --argjson env "$ENV_SET" --argjson top "$TOP_SET" --argjson sandbox "$SANDBOX_SET" --argjson unset "$TOP_UNSET" '
  .env = ((.env // {}) + $env)
  | .sandbox = ((.sandbox // {}) + $sandbox)
  | . += $top
  | reduce $unset[] as $k (.; del(.[$k]))
')"

if [ "$do_write" -eq 0 ]; then
  _info ""
  _info "(preview only — nothing written; re-run with --write to apply)"
  exit 0
fi

# Skip the write (and its backup) when the merge is a semantic no-op. Compared
# in canonical form so formatting/key-order differences don't force a rewrite.
if [ "$(printf '%s' "$current" | jq -S .)" = "$(printf '%s' "$merged" | jq -S .)" ]; then
  _info ""
  _info "(no changes needed — already hardened)"
  exit 0
fi

# --- Atomic write, with optional backup ---------------------------------------
# Follow a symlinked target so the atomic mv updates the file it points at,
# rather than replacing the symlink itself with a regular file.
symlink_depth=0
while [ -L "$target" ]; do
  symlink_depth=$((symlink_depth + 1))
  [ "$symlink_depth" -le 40 ] || _die "too many symlink levels while resolving target"
  real_target="$(_resolve_symlink_target "$target")"
  [ -n "$real_target" ] || _die "could not resolve symlink: $target"
  _info "note: $target is a symlink -> writing through to $real_target (link preserved)"
  target="$real_target"
done

mkdir -p "$(dirname "$target")"

if [ "$do_backup" -eq 1 ] && [ -e "$target" ]; then
  backup="$target.bak.$(date +%Y%m%d%H%M%S)"
  cp "$target" "$backup"
  _info "backup: $backup"
fi

tmp="$(mktemp "$target.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$merged" > "$tmp"
jq empty "$tmp" >/dev/null 2>&1 || _die "merged result was not valid JSON; target left unchanged"
if [ -e "$target" ]; then
  mode="$(_file_mode "$target")" || _die "could not read file mode for $target"
  chmod "$mode" "$tmp"
fi
mv "$tmp" "$target"
trap - EXIT

_info "wrote: $target"

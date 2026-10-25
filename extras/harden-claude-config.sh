#!/usr/bin/env bash

###
#   harden-claude-config.sh
#
#   Merge Claude Code privacy, sandbox, and permission hardening into a settings.json. MERGES, never
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
#       CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 strips credentials (recognized by variable
#       name or value shape) from the environment of every subprocess Claude Code
#       starts — Bash commands, hooks, and stdio MCP servers — sandboxed or not.
#       GitHub tokens and proxy settings are deliberately kept by the scrub.
#       DISABLE_TELEMETRY and DO_NOT_TRACK also turn off feature-flag fetching, which
#       gates features such as /skill-doctor, the advisor tool, and artifact comments;
#       see --allow-feature-flags.
#     settings (top-level):
#       skipWebFetchPreflight=true            don't send each fetched hostname to api.anthropic.com
#       attribution={"commit":"","pr":"","sessionUrl":false}
#                                               strip commit/PR/session attribution
#     sandbox (managed one level deep, like env: sibling subkeys you add by hand,
#     e.g., excludedCommands or network, survive re-runs; credentials.files and
#     credentials.envVars are merged by path and name: an entry of yours for a
#     managed path or name keeps its place and its other fields, but its mode is
#     set to deny, which the preview shows as a "~" line; your other entries are
#     kept; "credentials" needs Claude Code >= 2.1.187):
#       enabled=true                          OS-enforced Bash sandbox (macOS: Seatbelt;
#                                             Linux/WSL2: bubblewrap + socat)
#       autoAllowBashIfSandboxed=false        sandboxed commands still use the regular
#                                             permission flow in every permission mode
#       failIfUnavailable=true                fail closed: refuse to start Claude Code when
#                                             the sandbox can't initialize (e.g. missing
#                                             bubblewrap/socat on Linux), instead of the
#                                             default warn-and-run-unsandboxed
#       credentials.files                     read-deny ~/.ssh, ~/.aws, ~/.gnupg, ~/.netrc,
#                                             ~/.config/gcloud, ~/.azure inside the sandbox;
#                                             tools that need them fall back to an
#                                             unsandboxed retry behind a prompt, so a
#                                             cloud profile granted to Claude still works
#                                             one approval at a time (see
#                                             --allow-cloud-credential-files). ~/.codex is
#                                             not denied: the Codex plugin runs codex through
#                                             Bash, which needs to read it.
#       credentials.envVars                   unset these in sandboxed commands (exact names;
#                                             Claude Code doesn't have a built-in list or wildcards):
#                                             Anthropic: ANTHROPIC_API_KEY,
#                                             ANTHROPIC_AUTH_TOKEN, CLAUDE_CODE_OAUTH_TOKEN,
#                                             ANTHROPIC_FOUNDRY_API_KEY,
#                                             ANTHROPIC_FOUNDRY_AUTH_TOKEN,
#                                             ANTHROPIC_AWS_API_KEY, AWS_BEARER_TOKEN_BEDROCK;
#                                             OpenAI/Codex: OPENAI_API_KEY, OPENAI_ADMIN_KEY,
#                                             CODEX_API_KEY, CODEX_ACCESS_TOKEN, and
#                                             Codex's own launch context
#                                             (NON_INHERITABLE_ENV_VARS in
#                                             https://github.com/openai/codex/blob/main/codex-rs/protocol/src/shell_environment.rs).
#                                             Codex removes these from the commands it
#                                             starts; a Claude Code session started in the
#                                             same environment as Codex (e.g., a container
#                                             where they're set) would otherwise have them:
#                                             CODEX_EXEC_SERVER_NOISE_AUTH_TOKEN,
#                                             NODE_REPL_AUTH_TOKEN,
#                                             CODEX_GUARDIAN_DECISIONS_API_KEY,
#                                             OPENAI_FEDERATION_RULE_ID,
#                                             OPENAI_IDENTITY_TOKEN_FILE,
#                                             OPENAI_WORKLOAD_IDENTITY_CONTEXT;
#                                             AWS: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
#                                             AWS_SESSION_TOKEN, AWS_ACCESS_KEY,
#                                             AWS_SECRET_KEY (legacy SDK aliases),
#                                             AWS_CONTAINER_AUTHORIZATION_TOKEN,
#                                             AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE,
#                                             AWS_CONTAINER_CREDENTIALS_FULL_URI,
#                                             AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
#                                             (ECS, Batch, EKS Pod Identity, Lambda
#                                             SnapStart), AWS_WEB_IDENTITY_TOKEN_FILE,
#                                             AWS_PROFILE; Google: GOOGLE_API_KEY,
#                                             GEMINI_API_KEY; Azure: AZURE_CLIENT_SECRET,
#                                             AZURE_CLIENT_CERTIFICATE_PASSWORD,
#                                             AZURE_OPENAI_API_KEY, AZURE_OPENAI_AD_TOKEN.
#                                             The aim is that commands can't reuse ambient
#                                             credentials (the ones Claude Code uses for
#                                             inference, or ones the host happens to
#                                             provide) while a credential deliberately
#                                             granted to Claude still works. A mode you set
#                                             for one of these names (e.g., mask, for the
#                                             sandbox proxy's AWS SigV4 re-signing) is
#                                             changed to deny; the entry's other fields,
#                                             such as injectHosts, are kept. A deny entry
#                                             unsets only the inherited value before each
#                                             command, so a command that names a profile
#                                             itself (--profile NAME, or AWS_PROFILE=NAME
#                                             on the command) still uses it.
#                                             AWS_SHARED_CREDENTIALS_FILE and
#                                             AWS_CONFIG_FILE are left alone: they locate
#                                             granted profiles rather than carry secrets.
#                                             The scrub above covers the same ground
#                                             heuristically for all subprocesses; this list
#                                             guarantees these names in the sandbox.
#       network.deniedDomains                 add the cloud metadata endpoints, which hand
#                                             out the host's own credentials: EC2 IMDS
#                                             (169.254.169.254, [fd00:ec2::254]), ECS task
#                                             credentials (169.254.170.2), and the EKS Pod
#                                             Identity agent (169.254.170.23,
#                                             [fd00:ec2::23]). The sandbox proxy already
#                                             refuses hostnames that resolve to link-local
#                                             addresses, but a bare IP is decided by the
#                                             permission mode, and bypassPermissions allows
#                                             it; a denied entry is refused in every mode
#                                             (https://code.claude.com/docs/en/sandboxing).
#                                             Added to any existing list, never replacing
#                                             it. Bracketed IPv6 entries need Claude Code
#                                             >= 2.1.229.
#     Keep the inference credential out of the places a grant lives: if Claude Code
#     authenticates to Bedrock through a profile in ~/.aws (especially [default]),
#     allowing that directory exposes it. Use an environment variable for inference
#     (denied above) and named profiles for anything granted to Claude.
#     permissions.ask (additive: missing entries are appended; the existing list, its
#     order, and the allow/deny arrays are never touched):
#       Bash(git push), Bash(git push *)      every git push prompts for approval, in every
#                                             permission mode — ask rules bind auto mode,
#                                             bypassPermissions, and sandbox auto-allow
#                                             alike, and win over any matching allow rule
#
#   RELAX flags:
#     --allow-updates              env DISABLE_AUTOUPDATER=0. CLI + plugins auto-update.
#     --allow-feedback             env DISABLE_FEEDBACK_COMMAND=0 + CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=0.
#                                  (Surveys still won't appear unless --allow-feature-flags is
#                                  also given: DISABLE_TELEMETRY + DO_NOT_TRACK suppress them
#                                  independently of the survey flag.)
#     --allow-feature-flags        Remove env DISABLE_TELEMETRY (and any
#                                  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC left from an
#                                  earlier run) and set DO_NOT_TRACK=0, so
#                                  Claude Code fetches feature flags. Telemetry events (which,
#                                  per Claude Code's docs, don't include code, file paths, or
#                                  Bash commands) then reach Anthropic; there's no
#                                  setting that fetches flags with metrics off. Error
#                                  reporting, /feedback, and the survey stay off through
#                                  their own variables. DISABLE_TELEMETRY is removed rather
#                                  than set to 0 because any non-empty value opts out.
#                                  For the same reason, either variable exported in the
#                                  shell that starts Claude Code keeps flags off, and no
#                                  setting can unset it; the script warns when the shell
#                                  running it exports one, so unset it in your shell
#                                  startup files too.
#                                  Settings env values reach every subprocess, so
#                                  DO_NOT_TRACK=0 would also reach the commands Claude runs;
#                                  pair this with --dnt-prefix to restore DO_NOT_TRACK=1
#                                  for them. Incompatible with --disable-nonessential-traffic,
#                                  which turns flag fetching off again.
#     --dnt-prefix PATH            env CLAUDE_CODE_SHELL_PREFIX=PATH (an absolute path to an
#                                  executable, e.g., a copy of extras/claude-dnt-prefix.sh
#                                  outside any git working tree; the script warns when the
#                                  path, or the file a symlink there resolves to, is inside
#                                  one).
#                                  Claude Code runs Bash tool calls, command hooks, status-line
#                                  commands, and stdio MCP server startup through it; the
#                                  wrapper exports DO_NOT_TRACK=1 and re-runs the command
#                                  under the shell Claude Code chose (bash or zsh, read
#                                  from SHELL), falling back to /bin/bash.
#                                  Exec-form and PowerShell hooks bypass the prefix. Requires
#                                  --allow-feature-flags. Write the path unquoted, even with
#                                  spaces: in Claude Code 2.1.310, quotes in the value became
#                                  part of the file name, and a prefix that named a missing
#                                  file made every Bash call fail.
#     --allow-subprocess-credentials
#                                  env CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0. For setups where a
#                                  subprocess genuinely needs a credential from Claude Code's
#                                  environment, e.g. a stdio MCP server reading an API key that
#                                  is not set in its own "env" block.
#     --allow-cloud-credential-files
#                                  Remove the "deny" entries for ~/.aws, ~/.config/gcloud,
#                                  and ~/.azure from sandbox.credentials.files (an entry
#                                  you set with another mode stays), so sandboxed commands can use
#                                  cloud profiles without an unsandboxed retry. ~/.ssh,
#                                  ~/.gnupg, and ~/.netrc stay denied. See the note above
#                                  about keeping the inference credential out of ~/.aws.
#     --allow-metadata-endpoints   Remove the cloud metadata endpoints from
#                                  sandbox.network.deniedDomains (entries you added
#                                  yourself are kept), for EC2 hosts where a sandboxed
#                                  command should use the instance's role through the
#                                  instance metadata service. It doesn't make ECS task
#                                  roles, EKS Pod Identity, or IRSA work: the SDKs find
#                                  those credentials through
#                                  AWS_CONTAINER_CREDENTIALS_RELATIVE_URI,
#                                  AWS_CONTAINER_CREDENTIALS_FULL_URI,
#                                  AWS_CONTAINER_AUTHORIZATION_TOKEN(_FILE), and
#                                  AWS_WEB_IDENTITY_TOKEN_FILE, which
#                                  sandbox.credentials.envVars still unsets, so the
#                                  ECS and Pod Identity endpoints it un-denies go unused.
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
#     --allow-unsandboxed-start    sandbox failIfUnavailable=false: when the sandbox can't
#                                  initialize, warn and run unsandboxed (the product default)
#                                  instead of refusing to start. For machines where the
#                                  sandbox dependencies can't be installed.
#     --disable-sandbox            Pin sandbox.enabled=false. Other sandbox keys are left in
#                                  place (inert while disabled). Overrides the other sandbox
#                                  flags.
#
#     The "0" off-value relies on Claude Code's value parser, which reads 0/false/no/off as
#     off for on/off variables. CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, DISABLE_TELEMETRY,
#     and DISABLE_ERROR_REPORTING are documented exceptions that read only whether they're
#     set, so "0" still turns them on; relaxing one of them means deleting the key, which
#     is why --allow-feature-flags removes DISABLE_TELEMETRY.
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

# Prints the file a path resolves to after following every symlink in turn.
# Written as a loop over readlink because `readlink -f` is missing from older
# macOS releases. Returns 1 on a loop or an unreadable link rather than exiting,
# so a caller that only uses the result for a warning can fall back.
_resolve_symlink_chain() {
  local path="$1" depth=0 link_target
  while [ -L "$path" ]; do
    depth=$((depth + 1))
    [ "$depth" -le 40 ] || return 1
    link_target="$(readlink "$path")" || return 1
    case "$link_target" in
      /*) path="$link_target" ;;
      *)  path="$(cd "$(dirname "$path")" && pwd -P)/$link_target" || return 1 ;;
    esac
  done
  printf '%s\n' "$path"
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
  "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "1",
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
# sibling subkeys survive re-runs; "credentials" and "network.deniedDomains" are
# merged entry by entry (see CORE_CRED_FILES and CORE_DENIED_DOMAINS).
# Ask rules the base appends to permissions.ask. Ask rules prompt in every
# permission mode (including auto and bypassPermissions) and take precedence
# over matching allow rules, so these hold even when everything else is
# auto-approved. Additive: existing entries and order are preserved.
CORE_ASK='[
  "Bash(git push)",
  "Bash(git push *)"
]'

CORE_SANDBOX='{
  "enabled": true,
  "autoAllowBashIfSandboxed": false,
  "failIfUnavailable": true
}'

# sandbox.credentials entries, merged by path (files) and by name (envVars) so
# the user's own entries survive: an existing entry for a managed path or name
# has its mode set to the managed one in place, keeping its position and other
# fields, and every other entry is kept as it is.
CORE_CRED_FILES='[
  { "path": "~/.ssh", "mode": "deny" },
  { "path": "~/.aws", "mode": "deny" },
  { "path": "~/.gnupg", "mode": "deny" },
  { "path": "~/.netrc", "mode": "deny" },
  { "path": "~/.config/gcloud", "mode": "deny" },
  { "path": "~/.azure", "mode": "deny" }
]'

CORE_CRED_ENVVARS='[
      { "name": "ANTHROPIC_API_KEY", "mode": "deny" },
      { "name": "ANTHROPIC_AUTH_TOKEN", "mode": "deny" },
      { "name": "CLAUDE_CODE_OAUTH_TOKEN", "mode": "deny" },
      { "name": "ANTHROPIC_FOUNDRY_API_KEY", "mode": "deny" },
      { "name": "ANTHROPIC_FOUNDRY_AUTH_TOKEN", "mode": "deny" },
      { "name": "ANTHROPIC_AWS_API_KEY", "mode": "deny" },
      { "name": "AWS_BEARER_TOKEN_BEDROCK", "mode": "deny" },
      { "name": "OPENAI_API_KEY", "mode": "deny" },
      { "name": "OPENAI_ADMIN_KEY", "mode": "deny" },
      { "name": "CODEX_API_KEY", "mode": "deny" },
      { "name": "CODEX_ACCESS_TOKEN", "mode": "deny" },
      { "name": "CODEX_EXEC_SERVER_NOISE_AUTH_TOKEN", "mode": "deny" },
      { "name": "NODE_REPL_AUTH_TOKEN", "mode": "deny" },
      { "name": "CODEX_GUARDIAN_DECISIONS_API_KEY", "mode": "deny" },
      { "name": "OPENAI_FEDERATION_RULE_ID", "mode": "deny" },
      { "name": "OPENAI_IDENTITY_TOKEN_FILE", "mode": "deny" },
      { "name": "OPENAI_WORKLOAD_IDENTITY_CONTEXT", "mode": "deny" },
      { "name": "AWS_ACCESS_KEY_ID", "mode": "deny" },
      { "name": "AWS_SECRET_ACCESS_KEY", "mode": "deny" },
      { "name": "AWS_SESSION_TOKEN", "mode": "deny" },
      { "name": "AWS_ACCESS_KEY", "mode": "deny" },
      { "name": "AWS_SECRET_KEY", "mode": "deny" },
      { "name": "AWS_CONTAINER_AUTHORIZATION_TOKEN", "mode": "deny" },
      { "name": "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", "mode": "deny" },
      { "name": "AWS_CONTAINER_CREDENTIALS_FULL_URI", "mode": "deny" },
      { "name": "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "mode": "deny" },
      { "name": "AWS_WEB_IDENTITY_TOKEN_FILE", "mode": "deny" },
      { "name": "AWS_PROFILE", "mode": "deny" },
      { "name": "GOOGLE_API_KEY", "mode": "deny" },
      { "name": "GEMINI_API_KEY", "mode": "deny" },
      { "name": "AZURE_CLIENT_SECRET", "mode": "deny" },
      { "name": "AZURE_CLIENT_CERTIFICATE_PASSWORD", "mode": "deny" },
      { "name": "AZURE_OPENAI_API_KEY", "mode": "deny" },
      { "name": "AZURE_OPENAI_AD_TOKEN", "mode": "deny" }
]'

# Cloud credential directories that --allow-cloud-credential-files removes from
# credentials.files (their "deny" entries only; another mode the user set is
# kept). Kept separate from the base so the flag and the docs name the same set.
CLOUD_CREDENTIAL_FILES='["~/.aws", "~/.config/gcloud", "~/.azure"]'

# Metadata endpoints that hand out the host's own role credentials. Merged into
# sandbox.network.deniedDomains as a set, not written as a unit, because the
# network block usually holds the user's own allowedDomains.
CORE_DENIED_DOMAINS='[
  "169.254.169.254",
  "[fd00:ec2::254]",
  "169.254.170.2",
  "169.254.170.23",
  "[fd00:ec2::23]"
]'

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
allow_unsandboxed_start=0
disable_sandbox=0
allow_feature_flags=0
dnt_prefix=""
dnt_prefix_given=0
allow_subprocess_credentials=0
allow_cloud_credential_files=0
allow_metadata_endpoints=0
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
    --allow-unsandboxed-start)      allow_unsandboxed_start=1 ;;
    --disable-sandbox)              disable_sandbox=1 ;;
    --allow-feature-flags)          allow_feature_flags=1 ;;
    --dnt-prefix)
      [ "$#" -ge 2 ] || _die "--dnt-prefix needs a path"
      dnt_prefix="$2"; dnt_prefix_given=1; shift ;;
    --dnt-prefix=*)                 dnt_prefix="${1#--dnt-prefix=}"; dnt_prefix_given=1 ;;
    --allow-subprocess-credentials) allow_subprocess_credentials=1 ;;
    --allow-cloud-credential-files) allow_cloud_credential_files=1 ;;
    --allow-metadata-endpoints)     allow_metadata_endpoints=1 ;;
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

# Nonessential-traffic mode turns flag fetching off again, so asking for both is a
# contradiction rather than something to resolve silently.
if [ "$allow_feature_flags" -eq 1 ] && [ "$disable_nonessential" -eq 1 ]; then
  _die "--allow-feature-flags and --disable-nonessential-traffic contradict each other"
fi
# The prefix exists only to restore DO_NOT_TRACK=1 for subprocesses, which matters only
# once --allow-feature-flags has set it to 0. A prefix that names a missing or
# non-executable file breaks every Bash call, so check it before writing it.
# Checked on whether the option was given, not on whether its value is empty, so
# --dnt-prefix="" is rejected instead of silently skipping the wrapper.
if [ "$dnt_prefix_given" -eq 1 ]; then
  [ "$allow_feature_flags" -eq 1 ] || _die "--dnt-prefix requires --allow-feature-flags"
  [ -n "$dnt_prefix" ] || _die "--dnt-prefix needs a non-empty path"
  case "$dnt_prefix" in
    /*) ;;
    *) _die "--dnt-prefix needs an absolute path (Claude Code doesn't expand ~ or variables)" ;;
  esac
  [ -f "$dnt_prefix" ] && [ -x "$dnt_prefix" ] \
    || _die "--dnt-prefix target is not an executable file: $dnt_prefix"
  # A checkout, rebase, or stash in that working tree can remove the file or its
  # executable bit, and then every Bash call fails, including any that could
  # restore it. Warned rather than refused, because pointing at a checkout is a
  # legitimate way to test edits to the wrapper. Both the given path's directory
  # and the resolved file's are checked: a symlink outside any working tree that
  # points into one breaks just the same when the file it points at disappears.
  _in_work_tree() {
    [ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]
  }
  if command -v git >/dev/null 2>&1; then
    if _in_work_tree "$(dirname "$dnt_prefix")" \
        || { resolved_prefix="$(_resolve_symlink_chain "$dnt_prefix")" \
             && _in_work_tree "$(dirname "$resolved_prefix")"; }; then
      echo "warning: --dnt-prefix names a file inside a git working tree, or a symlink to one; a" \
        "checkout or rebase there can remove it and break every Bash call. Prefer a copy outside" \
        "any working tree." >&2
    fi
  fi
fi

# --- Preconditions ------------------------------------------------------------
command -v jq >/dev/null 2>&1 || _die "jq is required but not found (macOS: brew install jq; Fedora: sudo dnf install jq)"

# --- Compose the hardening from the flags -------------------------------------
# ENV_SET / TOP_SET = keys to write. TOP_UNSET = top-level keys to delete (the
# attribution relaxation, whose "relaxed" state is "use the product default").
# ENV_UNSET = env keys to delete, for presence-only variables such as
# DISABLE_TELEMETRY, where any value (even "0") keeps the behavior on.
# Everything else is additive; later values win, so re-runs are idempotent.
ENV_SET="$CORE_ENV"
TOP_SET="$CORE_TOP"
SANDBOX_SET="$CORE_SANDBOX"
ASK_SET="$CORE_ASK"
# FILES_ADD / ENVVARS_ADD = credentials entries to add, or whose mode to set on
# an existing entry for the same path or name; FILES_DEL = paths whose "deny"
# entries to remove.
FILES_ADD="$CORE_CRED_FILES"
ENVVARS_ADD="$CORE_CRED_ENVVARS"
FILES_DEL='[]'
# DENIED_ADD = deniedDomains entries to add; DENIED_DEL = entries to remove.
DENIED_ADD="$CORE_DENIED_DOMAINS"
DENIED_DEL='[]'
TOP_UNSET='[]'
ENV_UNSET='[]'

_env() { ENV_SET="$(jq -n --argjson a "$ENV_SET" --argjson b "$1" '$a + $b')"; }
_env_del() {
  ENV_SET="$(jq --arg k "$1" 'del(.[$k])' <<<"$ENV_SET")"
  ENV_UNSET="$(jq -n --argjson a "$ENV_UNSET" --arg k "$1" '($a + [$k]) | unique')"
}
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
[ "$allow_subprocess_credentials" -eq 1 ] && _env '{"CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "0"}'
if [ "$allow_feature_flags" -eq 1 ]; then
  # Both are presence-only and turn flag fetching off, so a value left from an
  # earlier --disable-nonessential-traffic run must be deleted too.
  _env_del 'DISABLE_TELEMETRY'
  _env_del 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'
  _env '{"DO_NOT_TRACK": "0"}'
  # Settings can delete these keys but can't unset a value Claude Code inherits
  # from the shell that starts it, and either one still turns flags off. The
  # shell running this script is the best available guess at that shell.
  for inherited in DISABLE_TELEMETRY CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
    if [ -n "${!inherited:-}" ]; then
      printf 'warning: %s is set in this shell; if Claude Code inherits it, feature flags stay off. Unset it where your shell sets it.\n' "$inherited" >&2
    fi
  done
fi
[ -n "$dnt_prefix" ] && _env "$(jq -n --arg p "$dnt_prefix" '{"CLAUDE_CODE_SHELL_PREFIX": $p}')"
[ "$allow_sandbox_auto_allow" -eq 1 ] && _sandbox '{"autoAllowBashIfSandboxed": true}'
[ "$allow_unsandboxed_start" -eq 1 ]  && _sandbox '{"failIfUnavailable": false}'
if [ "$allow_cloud_credential_files" -eq 1 ]; then
  FILES_ADD="$(jq --argjson drop "$CLOUD_CREDENTIAL_FILES" '
    map(select(.path as $p | $drop | index($p) | not))' <<<"$FILES_ADD")"
  FILES_DEL="$CLOUD_CREDENTIAL_FILES"
fi
if [ "$allow_metadata_endpoints" -eq 1 ]; then
  DENIED_DEL="$CORE_DENIED_DOMAINS"
  DENIED_ADD='[]'
fi
# Disabling the sandbox resets the managed subkeys to the pinned "off" alone, so it
# overrides the other sandbox flags; hand-added sandbox subkeys still merge through.
if [ "$disable_sandbox" -eq 1 ]; then
  SANDBOX_SET='{"enabled": false}'
  # The DEL lists are cleared too: removing entries from a sandbox that's off
  # doesn't change anything it enforces, and would leave the config weaker if
  # the sandbox is turned back on by hand.
  DENIED_ADD='[]'
  DENIED_DEL='[]'
  FILES_ADD='[]'
  FILES_DEL='[]'
  ENVVARS_ADD='[]'
fi

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

network_type="$(printf '%s' "$current" | jq -r '.sandbox.network | type')"
[ "$network_type" = "object" ] || [ "$network_type" = "null" ] \
  || _die "existing .sandbox.network is a $network_type, not an object; refusing to merge"

denied_type="$(printf '%s' "$current" | jq -r '.sandbox.network.deniedDomains | type')"
[ "$denied_type" = "array" ] || [ "$denied_type" = "null" ] \
  || _die "existing .sandbox.network.deniedDomains is a $denied_type, not an array; refusing to merge"

cred_type="$(printf '%s' "$current" | jq -r '.sandbox.credentials | type')"
[ "$cred_type" = "object" ] || [ "$cred_type" = "null" ] \
  || _die "existing .sandbox.credentials is a $cred_type, not an object; refusing to merge"
for cred_key in files envVars; do
  cred_key_type="$(printf '%s' "$current" | jq -r --arg k "$cred_key" '.sandbox.credentials[$k] | type')"
  [ "$cred_key_type" = "array" ] || [ "$cred_key_type" = "null" ] \
    || _die "existing .sandbox.credentials.$cred_key is a $cred_key_type, not an array; refusing to merge"
done

perm_type="$(printf '%s' "$current" | jq -r '.permissions | type')"
[ "$perm_type" = "object" ] || [ "$perm_type" = "null" ] \
  || _die "existing .permissions is a $perm_type, not an object; refusing to merge"

ask_type="$(printf '%s' "$current" | jq -r '.permissions.ask | type')"
[ "$ask_type" = "array" ] || [ "$ask_type" = "null" ] \
  || _die "existing .permissions.ask is a $ask_type, not an array; refusing to merge"

current_env="$(printf '%s' "$current" | jq -c '.env // {}')"
current_sandbox="$(printf '%s' "$current" | jq -c '.sandbox // {}')"
current_ask="$(printf '%s' "$current" | jq -c '.permissions.ask // []')"
current_denied="$(printf '%s' "$current" | jq -c '.sandbox.network.deniedDomains // []')"
current_files="$(printf '%s' "$current" | jq -c '.sandbox.credentials.files // []')"
current_envvars="$(printf '%s' "$current" | jq -c '.sandbox.credentials.envVars // []')"

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
_diff_rules() {  # $1 = current array, $2 = desired array, $3 = indent
  jq -nr --argjson cur "$1" --argjson want "$2" --arg pad "$3" '
    $want[] as $r
    | if ($cur | index($r)) != null then "\($pad)= \($r) (already present)"
      else                               "\($pad)+ \($r)"
      end'
}

_info "  env:"
_diff_set "$current_env" "$ENV_SET" "    "
jq -nr --argjson cur "$current_env" --argjson unset "$ENV_UNSET" '
  $unset[] as $k | select($cur | has($k)) | "    - \($k) (removed, was \($cur[$k]))"'
_info "  sandbox:"
_diff_set "$current_sandbox" "$SANDBOX_SET" "    "
# Credentials entries are matched by key (path or name), as the merge matches
# them, so an existing entry whose mode the merge changes shows as "~" rather
# than as a "+" that would hide the change.
_diff_creds() {  # $1 = current array, $2 = managed array, $3 = key field, $4 = indent
  jq -nr --argjson cur "$1" --argjson add "$2" --arg key "$3" --arg pad "$4" '
    $add[] as $e
    | [$cur[] | select(.[$key] == $e[$key])] as $same
    | if ($same | length) == 0 then "\($pad)+ \($e[$key]) \($e.mode)"
      elif ($same | all(.mode == $e.mode)) then "\($pad)= \($e[$key]) \($e.mode) (already present)"
      else ($same[] | select(.mode != $e.mode) | "\($pad)~ \($e[$key]): \(.mode) -> \($e.mode)")
      end'
}
_info "  sandbox.credentials.files:"
_diff_creds "$current_files" "$FILES_ADD" path "    "
jq -nr --argjson cur "$current_files" --argjson del "$FILES_DEL" --arg pad "    " '
  $cur[] | select(.mode == "deny" and (.path as $p | $del | index($p)) != null)
  | "\($pad)- \(.path) \(.mode) (removed)"'
_info "  sandbox.credentials.envVars:"
_diff_creds "$current_envvars" "$ENVVARS_ADD" name "    "
_info "  sandbox.network.deniedDomains:"
_diff_rules "$current_denied" "$DENIED_ADD" "    "
jq -nr --argjson cur "$current_denied" --argjson del "$DENIED_DEL" --arg pad "    " '
  $del[] as $d | select($cur | index($d) != null) | "\($pad)- \($d) (removed)"'
_info "  permissions.ask:"
_diff_rules "$current_ask" "$ASK_SET" "    "
_info "  settings:"
_diff_set "$current" "$TOP_SET" "    "
jq -nr --argjson cur "$current" --argjson unset "$TOP_UNSET" '
  $unset[] as $k | select($cur | has($k)) | "    - \($k) (removed, was \($cur[$k]))"'

# --- Merge (set env + top-level keys, delete relaxed top-level keys) ----------
merged="$(printf '%s' "$current" | jq \
  --argjson env "$ENV_SET" --argjson top "$TOP_SET" --argjson sandbox "$SANDBOX_SET" \
  --argjson ask "$ASK_SET" --argjson unset "$TOP_UNSET" --argjson envunset "$ENV_UNSET" \
  --argjson dadd "$DENIED_ADD" --argjson ddel "$DENIED_DEL" \
  --argjson fadd "$FILES_ADD" --argjson fdel "$FILES_DEL" --argjson vadd "$ENVVARS_ADD" '
  # Sets the managed mode on existing entries for a managed key and appends the
  # managed entries that are missing; see the credentials step below.
  def merge_creds($managed; $key):
    map(. as $e
        | ($managed | map(select(.[$key] == $e[$key])) | first) as $m
        | if $m == null then $e else $e + {mode: $m.mode} end)
    | . as $kept
    | . + [$managed[] | select(.[$key] as $k | ($kept | map(.[$key]) | index($k)) == null)];
  .env = ((.env // {}) + $env)
  | reduce $envunset[] as $k (.; del(.env[$k]))
  | .sandbox = ((.sandbox // {}) + $sandbox)
  # credentials entries merge by key: remove the "deny" entries a relax flag
  # names, set the managed mode on any existing entry for a managed path or
  # name (in place, so its position and other fields are kept), then append
  # the managed entries that lack an existing entry. Updating in place rather
  # than re-appending keeps the array order stable, so a file that already
  # holds every managed entry compares equal and is left unwritten. Nothing is
  # written when there is nothing to add or remove, so --disable-sandbox leaves
  # an existing block as it is.
  | if ($fadd | length) > 0 or ((.sandbox.credentials.files // []) | any(.mode == "deny" and (.path as $p | $fdel | index($p)) != null))
    then .sandbox.credentials.files =
           ((.sandbox.credentials.files // [])
            | map(select((.mode == "deny" and (.path as $p | $fdel | index($p)) != null) | not))
            | merge_creds($fadd; "path"))
    else . end
  | if ($vadd | length) > 0
    then .sandbox.credentials.envVars =
           ((.sandbox.credentials.envVars // []) | merge_creds($vadd; "name"))
    else . end
  # deniedDomains is a set merge: add the managed entries, remove only the ones a
  # relax flag names, and never create an empty network block for nothing.
  # The branch runs only when there is an entry to add or a listed entry to
  # remove, so an empty result there means this run removed every entry; the
  # emptied array, and a network object left empty by that, are dropped. An
  # empty array or network object written by hand never enters the branch and
  # is kept.
  | if ($dadd | length) > 0 or ((.sandbox.network.deniedDomains // []) | any(. as $d | $ddel | index($d)))
    then .sandbox.network.deniedDomains =
           (((.sandbox.network.deniedDomains // []) - $ddel)
            + ($dadd - (.sandbox.network.deniedDomains // [])))
         | if .sandbox.network.deniedDomains == [] then del(.sandbox.network.deniedDomains) else . end
         | if .sandbox.network == {} then del(.sandbox.network) else . end
    else . end
  | .permissions.ask = ((.permissions.ask // []) + ($ask - (.permissions.ask // [])))
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

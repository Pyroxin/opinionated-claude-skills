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
#   7-8. Checks placeholder notation and skill content conventions
#   9. Checks that Anthropic documentation links resolve to real pages
#
#   Full mode is used by pre-push and CI. Pre-push is the last gate before
#   changes become public; the cost of full validation (including plugin
#   installation) is justified because it catches integration issues that
#   structural checks alone would miss. Because the installation happens in an
#   isolated config dir removed by an EXIT trap, a partial or interrupted run
#   leaves no residue in the developer's real config or the workspace.
#
# Validate-only mode (--validate-only):
#   Checks JSON validity, verifies declared components exist on disk, runs the
#   shell linter, and checks skill content conventions (placeholder notation,
#   footnotes, reasoning-in-output instructions; heading tags and bracket
#   placeholders as warnings), each behind a positive control. No Claude CLI
#   calls, no installation, no state mutation.
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

# --- Portable temp-directory root ---
# Every mktemp call in this repo passes an absolute template. The bare forms
# (`mktemp -d`, `mktemp`) diverge across the two platforms this repo targets:
#
#   GNU coreutils: with no TEMPLATE, uses tmp.XXXXXXXXXX and implies --tmpdir,
#     so $TMPDIR is honored.
#   macOS (BSD):   "If no arguments are passed or if only the -d flag is passed
#     mktemp behaves as if -t tmp was supplied", and -t resolves against the
#     _CS_DARWIN_USER_TEMP_DIR confstr *before* falling back to $TMPDIR.
#
# The macOS precedence is the problem: a caller that redirects $TMPDIR -- a
# sandbox, a CI runner, a test harness -- is silently ignored, and mktemp writes
# to /var/folders/... instead, which fails outright when that path is not
# writable. An absolute template bypasses both fallback paths and resolves
# identically on GNU and BSD.
#
# -p cannot serve this purpose: GNU documents that "With this option, TEMPLATE
# must not be an absolute name", so -p and an absolute template are mutually
# exclusive there. Ten X's clears GNU's three-X minimum (BSD accepts one).
tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"

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
  ISOLATED_CONFIG="$(mktemp -d "${tmp_root}/claude-marketplace-config.XXXXXXXXXX")"
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
    # The installer places the launcher in ~/.local/bin, which is not guaranteed
    # to be on PATH in minimal or non-interactive environments: GitHub's runners
    # already include it, but a fresh container (e.g. a local `act` run) does not,
    # so the check below would report a successful install as a failure. Add it
    # explicitly before probing for the CLI.
    export PATH="$HOME/.local/bin:$PATH"
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

  # Auto-discover themes (themes/<name>.json)
  #
  # Themes are an experimental plugin component, so Claude Code may change their
  # manifest schema between releases. Check only what a theme needs in order to
  # load and be selectable -- parseable JSON, plus a non-empty `name` (the label
  # in /theme) and `base` (the preset the overrides apply to). The `overrides`
  # map is deliberately not inspected: its color-token vocabulary is Anthropic's
  # to define and grows with the UI, so validating it here would turn every
  # upstream token addition into a spurious local failure.
  while IFS= read -r -d '' theme_json; do
    theme_name=$(basename "$theme_json" .json)
    if ! jq empty "$theme_json" 2>/dev/null; then
      error "${plugin_name}: theme is invalid JSON at ${theme_json}"
    elif [[ -z "$(jq -r '.name // empty' "$theme_json")" ]]; then
      error "${plugin_name}: theme ${theme_name} has no 'name'"
    elif [[ -z "$(jq -r '.base // empty' "$theme_json")" ]]; then
      error "${plugin_name}: theme ${theme_name} has no 'base'"
    else
      info "  theme ${theme_name}: OK"
    fi
  done < <(find "${plugin_dir}/themes" -name "*.json" -type f -print0 2>/dev/null)

  # Auto-discover output styles (output-styles/<name>.md)
  #
  # Claude Code loads an output style by reading its frontmatter and injecting
  # the body into the system prompt, so a malformed file fails silently: the
  # style disappears from the /config picker with no error. `claude plugin
  # validate` does not reach these files either -- it validates plugin.json
  # alone -- so this is the only gate on them. Check the frontmatter delimiters
  # and a non-empty `description` (the picker's label; `name` legitimately
  # defaults to the filename). Where a style uses this repository's XML section
  # convention, check the tags balance, since an unclosed tag silently swallows
  # the rest of the file when the body reaches the model.
  while IFS= read -r -d '' style_md; do
    style_name=$(basename "$style_md" .md)
    if [[ ! -s "$style_md" ]]; then
      error "${plugin_name}: output style file is empty at ${style_md}"
    elif [[ "$(head -n 1 "$style_md")" != "---" ]]; then
      error "${plugin_name}: output style ${style_name} has no frontmatter delimiter on line 1"
    elif ! awk 'NR>1 && /^---$/{found=1; exit} END{exit !found}' "$style_md"; then
      error "${plugin_name}: output style ${style_name} has an unterminated frontmatter block"
    elif ! grep -q '^description:[[:space:]]*[^[:space:]]' "$style_md"; then
      error "${plugin_name}: output style ${style_name} has no 'description'"
    else
      unbalanced=$(grep -o -E '^</?[a-z_]+>$' "$style_md" \
        | sed 's|</||; s|<||; s|>||' \
        | sort | uniq -c | awk '$1 % 2 == 1 {print $2}' | tr '\n' ' ')
      if [[ -n "${unbalanced// /}" ]]; then
        error "${plugin_name}: output style ${style_name} has unbalanced XML tags: ${unbalanced}"
      else
        info "  output style ${style_name}: OK"
      fi
    fi
  done < <(find "${plugin_dir}/output-styles" -name "*.md" -type f -print0 2>/dev/null)

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
scripts_list=$(mktemp "${tmp_root}/claude-marketplace-scripts.XXXXXXXXXX")
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

# --- Step 7: Placeholder notation ---
#
# expert-skill-creator reserves angle brackets for XML tags and braces for value
# placeholders, so a kebab-case token in angle brackets (such as <project-root>)
# is ambiguous with a section tag. Only prose is checked: inside fenced code the
# brackets belong to whatever notation the block quotes, such as a CLI usage
# synopsis or a generic type. The <placeholder_notation> section that defines the
# rule is skipped as well, since stating the rule requires showing the
# counterexample it rules out.

echo ""
echo "Checking placeholder notation..."

FIXTURE_DIR="${SCRIPT_DIR}/validator-fixtures"

# Positive control: a check counts as working only when it reports exactly the
# known cases its fixture in scripts/validator-fixtures/ holds, because a check
# that cannot report a finding returns a clean result on every input. The
# fixtures also hold look-alikes each check must skip (e.g., fenced examples),
# so a count above the expected number fails the control too.
self_test() {
  local name="$1" program="$2" expected="$3" found
  found=$(awk "$program" "${FIXTURE_DIR}/${name}.md" | grep -c . || true)
  if [[ "$found" -ne "$expected" ]]; then
    error "check '${name}' reported ${found} findings on its fixture, which holds ${expected}; its results cannot be trusted"
  else
    info "  ${name} control: ${found} of ${expected} known cases reported"
  fi
}

# shellcheck disable=SC2016 # an awk program; its $ fields are not shell expansions
placeholder_check='
  /^[[:space:]]*```/       { fence = !fence; next }
  /^<placeholder_notation>$/  { exempt = 1; next }
  /^<\/placeholder_notation>$/ { exempt = 0; next }
  fence || exempt          { next }
  {
    rest = $0
    while (match(rest, /<[a-z][a-z0-9]*(-[a-z0-9]+)+>/)) {
      printf "    line %d: %s\n", FNR, substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
    }
  }'
self_test placeholders "$placeholder_check" 1

notation_list=$(mktemp "${tmp_root}/claude-marketplace-notation.XXXXXXXXXX")
if ! find "$PROJECT_DIR" \( -path '*/skills/*/*.md' -o -path '*/agents/*.md' \) -type f -print0 > "$notation_list"; then
  error "Failed to enumerate skill and agent markdown under ${PROJECT_DIR}"
fi
while IFS= read -r -d '' doc; do
  findings=$(awk "$placeholder_check" "$doc")
  if [[ -n "$findings" ]]; then
    error "angle-bracket placeholder in ${doc#"${PROJECT_DIR}"/} (use braces)"
    printf '%s\n' "$findings" >&2
  else
    info "  $(basename "$(dirname "$doc")")/$(basename "$doc"): OK"
  fi
done < "$notation_list"
rm -f "$notation_list"

# --- Step 8: Skill content conventions ---
#
# These checks enforce expert-skill-creator conventions mechanically, so that
# compliance does not depend on whether an author read the guidance. Each runs
# per file, over skills (SKILL.md and reference files), agents, and output
# styles, and each first passes its positive control (see self_test above).
#
# Errors, which fail the run:
#   footnotes - a [^label] used without a definition in the same file, or
#     defined and never used. Each file carries its own sources, because a
#     skill's reference files are read separately from SKILL.md.
#   reasoning - an instruction to put the model's reasoning in its output
#     (e.g., a <thinking> section, a "reasoning": field, "think step by
#     step"), which current Claude models may decline as reasoning_extraction.
#     A line that names reasoning_extraction is discussing the rule and is
#     skipped, and expert-skill-creator is exempt, because stating the rule
#     requires quoting the patterns it rules out.
#
# Warnings, reported with counts but not failing the run:
#   heading-tags - a heading whose next non-blank line is not its own XML tag.
#   brackets - a [lowercase words] placeholder where braces are the convention.
#   Both conventions postdate most skills in this repository; each skill comes
#   into line when it is next upgraded through expert-skill-creator. Make them
#   errors once their counts reach zero.

echo ""
echo "Checking skill content conventions..."

# shellcheck disable=SC2016 # an awk program; its $ fields are not shell expansions
footnote_check='
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  {
    line = $0
    if (match(line, /^\[\^[A-Za-z0-9_-]+\]:/)) {
      label = substr(line, 1, RLENGTH - 1)
      if (!(label in def)) def[label] = FNR
      line = substr(line, RLENGTH + 1)
    }
    gsub(/`[^`]*`/, "", line)
    while (match(line, /\[\^[A-Za-z0-9_-]+\]/)) {
      label = substr(line, RSTART, RLENGTH)
      if (!(label in use)) use[label] = FNR
      line = substr(line, RSTART + RLENGTH)
    }
  }
  END {
    for (u in use) if (!(u in def)) printf "    line %d: %s is used but never defined\n", use[u], u
    for (d in def) if (!(d in use)) printf "    line %d: %s is defined but never used\n", def[d], d
  }'

# shellcheck disable=SC2016 # an awk program; its $ fields are not shell expansions
reasoning_check='
  {
    l = tolower($0)
    if (l ~ /reasoning_extraction/) next
    if (l ~ /<(thinking|reasoning|scratchpad)>/ ||
        l ~ /"(reasoning|thinking|trace)"[[:space:]]*:/ ||
        l ~ /think step[- ]by[- ]step|chain[- ]of[- ]thought/ ||
        l ~ /(show|narrate|write out|explain) (your|its) (internal )?(reasoning|thinking|work)/)
      printf "    line %d: %s\n", FNR, substr($0, 1, 100)
  }'

# shellcheck disable=SC2016 # an awk program; its $ fields are not shell expansions
heading_check='
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  pending && NF {
    if ($0 !~ /^<[a-z_]+( [^>]*)?>$/) printf "    line %d: %s\n", heading_line, heading
    pending = 0
  }
  /^##+ / { pending = 1; heading = $0; heading_line = FNR }'

# shellcheck disable=SC2016 # an awk program; its $ fields are not shell expansions
bracket_check='
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  {
    line = $0 " "
    gsub(/`[^`]*`/, "", line)
    while (match(line, /\[[a-z][a-z0-9 _-]+\]/)) {
      next_char = substr(line, RSTART + RLENGTH, 1)
      if (next_char != "(" && next_char != "[" && next_char != ":")
        printf "    line %d: %s\n", FNR, substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
    }
  }'

self_test footnotes "$footnote_check" 2
self_test reasoning "$reasoning_check" 12
self_test heading-tags "$heading_check" 1
self_test brackets "$bracket_check" 2

# The list stays until Step 9, which extracts documentation links from it.
content_list=$(mktemp "${tmp_root}/claude-marketplace-content.XXXXXXXXXX")
if ! find "$PROJECT_DIR" \( -path '*/skills/*/*.md' -o -path '*/agents/*.md' -o -path '*/output-styles/*.md' \) -not -path '*/.git/*' -type f -print0 > "$content_list"; then
  error "Failed to enumerate skill, agent, and output-style markdown under ${PROJECT_DIR}"
fi
files_checked=0
heading_warnings=0
bracket_warnings=0
while IFS= read -r -d '' doc; do
  rel="${doc#"${PROJECT_DIR}"/}"
  files_checked=$((files_checked + 1))

  findings=$(awk "$footnote_check" "$doc") || error "footnote check failed to run on ${rel}"
  if [[ -n "$findings" ]]; then
    error "footnote reference or definition without its counterpart in ${rel}"
    printf '%s\n' "$findings" >&2
  fi

  case "$rel" in
    */skills/expert-skill-creator/*) ;;
    *)
      findings=$(awk "$reasoning_check" "$doc") || error "reasoning check failed to run on ${rel}"
      if [[ -n "$findings" ]]; then
        error "instruction to put reasoning in the output in ${rel} (current Claude models may decline it as reasoning_extraction)"
        printf '%s\n' "$findings" >&2
      fi
      ;;
  esac

  count=$(awk "$heading_check" "$doc" | grep -c . || true)
  if [[ "$count" -gt 0 ]]; then
    info "  WARNING: ${rel}: ${count} heading(s) without their own XML tag"
    heading_warnings=$((heading_warnings + count))
  fi
  count=$(awk "$bracket_check" "$doc" | grep -c . || true)
  if [[ "$count" -gt 0 ]]; then
    info "  WARNING: ${rel}: ${count} [bracket] placeholder(s); use braces"
    bracket_warnings=$((bracket_warnings + count))
  fi
done < "$content_list"
if [[ "$files_checked" -eq 0 ]]; then
  error "No skill, agent, or output-style markdown found under ${PROJECT_DIR}; the content checks examined nothing"
fi
info "  ${files_checked} files checked for footnotes and reasoning instructions; warnings not yet enforced: ${heading_warnings} heading-tag, ${bracket_warnings} bracket-placeholder"

# --- Step 9: Documentation links (full mode only) ---
#
# Anthropic's documentation sites answer HTTP 200 for pages that do not exist,
# so a status code cannot show that a page exists. The check reads each page's
# Markdown instead: a platform.claude.com page starts with front matter that
# carries a `title:` field, while a missing page returns "Not Found"; a
# code.claude.com page's first top-level heading is its title, while a missing
# page's is "# Page Not Found". A missing control page on each site has to be
# reported missing, and a known page present, before any result is believed.
# Links to other hosts are not checked. This step needs the network, so it runs
# only in full mode (pre-push and CI).

doc_page_exists() {
  local url="${1%.md}" body heading
  body=$(curl -sSL --max-time 30 "${url}.md") || return 1
  case "$url" in
    https://platform.claude.com/*)
      [[ "${body:0:400}" == *$'\ntitle: '* ]] ;;
    https://code.claude.com/*)
      heading=$(printf '%s\n' "$body" | awk '/^# / && !seen { print; seen = 1 }')
      [[ -n "$heading" && "$heading" != "# Page Not Found" ]] ;;
    *)
      return 1 ;;
  esac
}

if [[ "$VALIDATE_ONLY" != "true" ]]; then
  echo ""
  echo "Checking documentation links..."
  link_controls_ok=true
  for control in https://platform.claude.com/docs/en/validator-control-missing-page \
                 https://code.claude.com/docs/en/validator-control-missing-page; do
    if doc_page_exists "$control"; then
      error "link check reports the missing control page ${control} as present"
      link_controls_ok=false
    fi
  done
  for control in https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices \
                 https://code.claude.com/docs/en/skills; do
    if ! doc_page_exists "$control"; then
      error "link check reports the known page ${control} as missing"
      link_controls_ok=false
    fi
  done
  if [[ "$link_controls_ok" == "true" ]]; then
    url_list=$(mktemp "${tmp_root}/claude-marketplace-urls.XXXXXXXXXX")
    while IFS= read -r -d '' doc; do
      grep -ohE 'https://(platform|code)\.claude\.com/docs/en/[A-Za-z0-9/_.-]+' "$doc" || true
    done < "$content_list" | sed -E 's/[.)]+$//' | sort -u > "$url_list"
    link_count=0
    while IFS= read -r url; do
      link_count=$((link_count + 1))
      if ! doc_page_exists "$url"; then
        error "documentation link does not resolve to a page: ${url}"
      fi
    done < "$url_list"
    info "  ${link_count} documentation links checked after both sites' controls passed"
    rm -f "$url_list"
  fi
fi
rm -f "$content_list"

# --- Step 10: Teardown (full mode only) ---
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
    echo "Structural validation passed (${plugin_count} plugins; shellcheck, placeholder notation, and skill content checks clean)."
  else
    echo "Full verification passed (${plugin_count} plugins installed and validated)."
  fi
  exit 0
else
  echo "Verification completed with ${errors} error(s)." >&2
  exit 1
fi

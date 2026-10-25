# Testing

This document records local validation procedures for this repository. It is
organized by testing topic so new checks can be added without reshaping the
file.

## Standard Validation

Run the fast structural validation before committing:

```bash
./scripts/install-and-verify.sh --validate-only
```

This checks JSON validity, verifies declared plugin components exist, runs
ShellCheck over the repository's shell scripts, and checks skill, agent, and
output-style Markdown for the conventions `expert-skill-creator` defines:
placeholder notation, footnotes resolving in both directions within each file,
and instructions that ask the model to put its reasoning in the output. Heading
tags and bracket placeholders are reported as warnings with counts until the
existing skills come into line. A skill that couldn't be uploaded outside
Claude Code (`scripts/portable-skill.sh` lists the rules; it needs dasel v3) is also reported as a
warning, and `build-skills.sh` leaves it out of the ZIPs. A `SKILL.md` that
can't be read (e.g., mode 000) stops both the validation and the build with an
error, rather than being reported as lacking frontmatter and left out.

Each content check first runs against a fixture in
`scripts/validator-fixtures/` holding a known instance of every pattern it
applies, and fails the run if it reports a different number of findings. When
you change a check, update its fixture and the expected count passed to
`self_test` in the same change. The portability check is the exception: each
`portable-skill*.md` fixture has a `.expected` file with its exact findings, so
update those files instead.

Run the full validation path when you need to exercise the Claude Code plugin
installation flow in an isolated config directory:

```bash
./scripts/install-and-verify.sh
```

Full mode also checks that every link to Anthropic's documentation sites
resolves to a real page. Those sites return HTTP 200 for missing pages, so the
check reads each page's Markdown, and it runs only after a missing control page
on each site is reported missing and a known page is reported present.

Build the release ZIPs when changing skill packaging or release behavior. The
ZIP builds are deprecated and expected to be removed:

```bash
./scripts/build-skills.sh
```

## CI Workflow Smoke Tests

Use `act push` to catch workflow issues before pushing:

```bash
act push
```

This repository includes `.actrc` so `act` uses an Ubuntu image with the tools
expected by `.github/workflows/release.yml`. The container architecture is not
pinned, so the job runs natively on the host: amd64 on an Intel machine, arm64
on Apple Silicon. `release.yml` picks its ShellCheck and dasel downloads from
`uname -m`, so both architectures get working binaries.

Do not add `--container-architecture linux/amd64` back to run an arm64 host's
job as amd64. Under the resulting emulation the Bun-compiled Claude Code
installer that `install-and-verify.sh` fetches dies with SIGSEGV, so the job
fails at the "Install and verify plugins" step for a reason unrelated to the
change under test.

`act push` is not a perfect recreation of GitHub Actions. Treat it as a local
smoke test for the workflow, not as a proof that GitHub Actions will behave
identically. Two known divergences: the release-publishing step is skipped under
`act` because the workflow guards it with `if: ${{ !env.ACT }}`, and the job
occasionally exits 137 with act reporting `no such container` during cleanup.
That exit is a container-lifecycle failure, not a workflow failure; re-run
before investigating it.

## Script Tests

Use temporary directories for scripts that mutate Claude Code configuration or
other user state; never aim test runs at `~/.claude/settings.json`.

### `extras/harden-claude-config.sh`

The script edits Claude Code settings files. Test it only against temporary
files:

```bash
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

printf '{"env":{"KEEP":"yes"}}\n' > "$cfg"
./extras/harden-claude-config.sh --write --no-backup "$cfg"
jq -S . "$cfg"
```

Cover these regression cases when changing the script:

- Normal merge preserves unrelated top-level keys and unrelated `.env` entries.
- Base hardening writes `attribution.commit=""`, `attribution.pr=""`, and
  `attribution.sessionUrl=false`.
- `--allow-model-attribution` removes the `attribution.commit` and
  `attribution.pr` overrides while keeping `attribution.sessionUrl=false`.
- `--allow-session-attribution` removes only the session URL override; when
  combined with `--allow-model-attribution`, the managed `attribution` object
  is removed entirely.
- `--allow-only-plugin-updates` keeps `DISABLE_AUTOUPDATER=1` even when
  combined with `--allow-updates`, and writes `FORCE_AUTOUPDATE_PLUGINS=1`.
- `--disable-nonessential-traffic` wins after `--allow-updates` and
  `--allow-feedback`, while `--allow-only-plugin-updates` still writes
  `FORCE_AUTOUPDATE_PLUGINS=1`. WebFetch preflight remains controlled by
  `--allow-webfetch-preflight`, matching Claude Code's separate WebFetch
  preflight setting.
- Base hardening writes `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, adds the managed
  `sandbox.credentials` entries (`files` by path, `envVars` by name), and keeps
  hand-added sibling `sandbox` keys such as `excludedCommands`. A user's own
  credentials entries (e.g., `~/.kube`, `GITHUB_TOKEN`) are kept; an entry for
  a managed path or name with another mode (e.g., `~/.ssh` `allow`, or
  `AWS_ACCESS_KEY_ID` `mask` with `injectHosts`) keeps its position and its
  other fields, gets `mode: "deny"`, and shows in the preview as
  `~ AWS_ACCESS_KEY_ID: mask -> deny`; a managed-path entry already set to
  `deny` with an extra field shows as `=`; a rerun doesn't change anything. A
  file that holds every managed entry with a user entry placed between two of
  them is a no-op under `--write` (no rewrite, no backup), so the merge doesn't
  reorder entries. `--disable-sandbox` leaves an existing credentials block as it is
  and doesn't create one. A non-object `credentials` or a non-array `files` or
  `envVars` is rejected with a clear error.
- The `envVars` deny list names exactly the variables in
  `extras/harden-codex-config.sh`'s `CREDENTIAL_ENV_VARS`, so both scripts
  strip the same credentials. Compare them when changing either list:

  ```bash
  diff <(grep -o '"name": "[A-Z_]*"' extras/harden-claude-config.sh | cut -d'"' -f4 | sort) \
       <(sed -n '/^CREDENTIAL_ENV_VARS = (/,/^)$/p' extras/harden-codex-config.sh \
           | grep -v '^ *#' | grep -o '"[A-Z_]*"' | tr -d '"' | sort)
  ```
- Base hardening adds the five cloud metadata endpoints to
  `sandbox.network.deniedDomains`, keeping existing `allowedDomains` and
  `deniedDomains` entries; a rerun doesn't add duplicates.
- `--allow-metadata-endpoints` removes only those five entries, keeps entries
  the user added, and doesn't create a `network` block in a file that has none.
- `--allow-cloud-credential-files` removes the `deny` entries for `~/.aws`,
  `~/.config/gcloud`, and `~/.azure` from `sandbox.credentials.files` (the
  preview shows each as `-`), keeps `~/.ssh`, `~/.gnupg`, `~/.netrc`, and the
  user's own entries, and a later base run adds them back.
- A non-object `.sandbox.network` or non-array `deniedDomains` is rejected with
  a clear error.
- `--allow-feature-flags` deletes `DISABLE_TELEMETRY` (setting it to `"0"`
  would still opt out) and writes `DO_NOT_TRACK=0`; the preview reports the
  deletion as a `-` line. Run after `--disable-nonessential-traffic`, it also
  deletes `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`. Run from a shell that
  exports either variable (e.g., `DISABLE_TELEMETRY=1 ./extras/...`), it warns
  on stderr; without the flag, or with neither variable set, it doesn't.
- `--dnt-prefix PATH` writes `CLAUDE_CODE_SHELL_PREFIX` verbatim, including a
  path with spaces, and is rejected without `--allow-feature-flags`, with a
  relative path, with an empty value (`--dnt-prefix=""`), or when the target
  isn't an executable file. A target inside a git working tree (e.g., the
  checkout's `extras/claude-dnt-prefix.sh`) prints a warning on stderr, and so
  does a symlink outside any working tree that resolves to that file, directly
  or through a chain of links; a copy outside any working tree, and a symlink
  to such a copy, don't. Check the symlink cases with GNU coreutils first on
  `PATH` too.
- `--allow-feature-flags` with `--disable-nonessential-traffic` is rejected.
- `--allow-subprocess-credentials` writes `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=0`.
- A top-level non-object JSON value, e.g., `[]`, is rejected with a clear error.
- A non-object `.env` value is rejected with a clear error.
- A symlinked settings path updates the target file and preserves the symlink.
- A symlink chain updates the final target file and preserves every symlink in
  the chain.
- A dangling symlinked settings path creates the missing target file and
  preserves the symlink.
- A second write against an already-hardened file is a semantic no-op and does
  not create a backup.
- Existing file mode is preserved on a changing write.
- Directory and unreadable-file targets are rejected with a clear error.

Useful focused probes:

```bash
# Top-level non-object rejection.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"
printf '[]\n' > "$cfg"
./extras/harden-claude-config.sh --write --no-backup "$cfg"
```

```bash
# Dangling symlink creation without replacing the link.
tmpdir="$(mktemp -d)"
target="$tmpdir/missing.json"
link="$tmpdir/settings.json"
ln -s "$target" "$link"

./extras/harden-claude-config.sh --write --no-backup "$link"
test -L "$link"
test -e "$target"
jq -S . "$target"
```

```bash
# Plugin-only updates should override --allow-updates for the binary updater.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-updates \
  --allow-only-plugin-updates \
  "$cfg"

jq -S '.env | {
  DISABLE_AUTOUPDATER,
  FORCE_AUTOUPDATE_PLUGINS
}' "$cfg"
```

```bash
# Nonessential traffic should re-pin relaxed optional channels.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-updates \
  --allow-feedback \
  --allow-webfetch-preflight \
  --allow-only-plugin-updates \
  --disable-nonessential-traffic \
  "$cfg"

jq -S '.env | {
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC,
  DISABLE_AUTOUPDATER,
  DISABLE_FEEDBACK_COMMAND,
  CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY,
  FORCE_AUTOUPDATE_PLUGINS
}' "$cfg"
jq -e '.skipWebFetchPreflight == false' "$cfg"
```

```bash
# Model/tool attribution can be allowed while session URL attribution stays off.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-model-attribution \
  "$cfg"

jq -e '
  (.attribution | has("commit") | not)
  and (.attribution | has("pr") | not)
  and (.attribution.sessionUrl == false)
' "$cfg"
```

```bash
# Full attribution relaxation removes the managed attribution object.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"

./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-model-attribution \
  --allow-session-attribution \
  "$cfg"

jq -e 'has("attribution") | not' "$cfg"
```

```bash
# Feature flags: DISABLE_TELEMETRY is deleted, and the DNT prefix path keeps
# its spaces.
tmpdir="$(mktemp -d)"
cfg="$tmpdir/settings.json"
mkdir "$tmpdir/dir with space"
cp ./extras/claude-dnt-prefix.sh "$tmpdir/dir with space/prefix.sh"

./extras/harden-claude-config.sh --write --no-backup "$cfg"
./extras/harden-claude-config.sh \
  --write \
  --no-backup \
  --allow-feature-flags \
  --dnt-prefix "$tmpdir/dir with space/prefix.sh" \
  "$cfg"

jq -e --arg p "$tmpdir/dir with space/prefix.sh" '
  (.env | has("DISABLE_TELEMETRY") | not)
  and (.env.DO_NOT_TRACK == "0")
  and (.env.CLAUDE_CODE_SHELL_PREFIX == $p)
' "$cfg"

# The wrapper restores DO_NOT_TRACK=1 for the command it runs.
DO_NOT_TRACK=0 "$tmpdir/dir with space/prefix.sh" 'test "$DO_NOT_TRACK" = 1'

# It re-runs the command under SHELL when that names bash or zsh, the shell
# Claude Code assembled the command for, and under /bin/bash otherwise
# (e.g., fish, unset, or a path that doesn't exist).
SHELL="$(command -v zsh)" "$tmpdir/dir with space/prefix.sh" 'test -n "$ZSH_VERSION"'
SHELL="$(command -v bash)" "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'
SHELL=/usr/bin/fish "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'
SHELL=/nonexistent/zsh "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'
env -u SHELL "$tmpdir/dir with space/prefix.sh" 'test -n "$BASH_VERSION"'

# Any argument count other than one is refused (exit 2) rather than dropping
# arguments.
"$tmpdir/dir with space/prefix.sh" true extra; test $? -eq 2
"$tmpdir/dir with space/prefix.sh"; test $? -eq 2
```

### `extras/harden-codex-config.sh`

The script edits Codex TOML configuration files. Test it only against temporary
files:

```bash
tmpdir="$(mktemp -d)"
cfg="$tmpdir/config.toml"

printf 'model = "gpt-5.5"\n\n[analytics]\nenabled = true\n' > "$cfg"
./extras/harden-codex-config.sh --write --no-backup "$cfg"
./extras/harden-codex-config.sh --write --no-backup "$cfg"
```

Cover these regression cases when changing the script:

- Normal merge preserves unrelated keys, including MCP server configuration and
  plugin settings.
- Empty arrays are preserved, including `args = []` under an MCP server.
- Written files semantically round-trip: parse the written TOML and compare it
  with the intended merged data.
- Base hardening writes `sandbox_mode="read-only"`,
  `approval_policy="on-request"`, `web_search="disabled"`,
  `analytics.enabled=false`, `feedback.enabled=false`, OTel exporters set to
  `"none"`, and `otel.log_user_prompt=false`.
- Base hardening writes `shell_environment_policy.inherit="core"` and keeps
  `shell_environment_policy.ignore_default_excludes=false` so spawned command
  environments remain filtered for likely secrets.
- Base hardening writes `features.apps=false`,
  `features.codex_git_commit=false`, and `features.memories=false`.
- Base hardening writes `features.shell_snapshot=false` (openai/codex#22124)
  and prints a note on stderr about tools found only through shell startup
  files when it changes the setting; a rerun on an already-hardened config
  doesn't print a note. `--allow-shell-snapshot` writes `true`. `codex features list`
  with that config as `CODEX_HOME` reports `shell_snapshot` as `false`.
- Base hardening writes the credential names as
  `shell_environment_policy.filters` entries, or into a legacy `exclude` array
  when the config already has `exclude` or `include_only`; Codex loads each
  result. A config mixing `filters` with either legacy array, or a legacy
  value that isn't a list of strings, stops the script with an error naming
  the key. A credential name in `shell_environment_policy.set` (any case) is
  removed, the preview shows the removal without the value, and other `set`
  entries stay.
- Base hardening writes `cli_auth_credentials_store="keyring"`;
  `--allow-file-credentials` writes `"auto"` instead. With an `auth.json` next
  to the target and keyring storage selected, the script warns on stderr.
- Base hardening writes
  `plugins."unified-computer-use@openai-bundled".enabled=false` and removes a
  `notify` command that runs `SkyComputerUseClient`, but keeps any other
  `notify` command; `--allow-computer-use` writes `enabled=true` and leaves
  `notify` alone. A second run is a no-op. The client is recognized by its
  file name, directly, behind `/usr/bin/env` with options and assignments, and
  inside `sh -c`. A shell running a script (e.g., `bash notify.sh`) is kept
  without a warning; a program whose name only contains the client's (e.g.,
  `SkyComputerUseClient-status-reporter`) is kept,
  with a warning on stderr.
- `--allow-workspace-write`, `--allow-network`, `--allow-web-search`,
  `--allow-live-web-search`, `--allow-login-shell`, `--allow-updates`,
  `--allow-feedback`, `--allow-analytics`, `--allow-otel-metrics`,
  `--allow-apps`, `--allow-codex-git-commit`, and `--allow-memories` write
  explicit relaxed values.
- A managed path that collides with a non-table value, e.g.,
  `analytics = true`, is rejected with a clear error.
- Invalid TOML is rejected with a clear error.
- Directory and unreadable-file targets are rejected with a clear error rather
  than a traceback.
- A symlinked config path updates the target file and preserves the symlink.
- A dangling symlinked config path creates the missing target file and
  preserves the symlink.
- A second write against an already-hardened file is a semantic no-op and does
  not create a backup.
- The default target respects `CODEX_HOME`.
- TOML date, time, datetime, and empty-list values remain valid after a write.
- Comments and formatting are not preserved on a write that changes values.

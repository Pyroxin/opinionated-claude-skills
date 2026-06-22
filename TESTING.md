# Testing

This document records local validation procedures for this repository. It is
organized by testing topic so new checks can be added without reshaping the
file.

## Standard Validation

Run the fast structural validation before committing:

```bash
./scripts/install-and-verify.sh --validate-only
```

This checks JSON validity, verifies declared plugin components exist, and runs
ShellCheck over the repository's shell scripts.

Run the full validation path when you need to exercise the Claude Code plugin
installation flow in an isolated config directory:

```bash
./scripts/install-and-verify.sh
```

Build the release ZIPs when changing skill packaging or release behavior:

```bash
./scripts/build-skills.sh
```

## CI Workflow Smoke Tests

Use `act push` to catch workflow issues before pushing:

```bash
act push
```

This repository includes `.actrc` so `act` uses an Ubuntu image with the tools
expected by `.github/workflows/release.yml` and runs the container as
`linux/amd64`, matching GitHub's hosted runner architecture.

`act push` is not a perfect recreation of GitHub Actions. Treat it as a local
smoke test for the workflow, not as a proof that GitHub Actions will behave
identically. In particular, the release-publishing step is skipped under `act`
because the workflow guards it with `if: ${{ !env.ACT }}`.

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
- A top-level non-object JSON value, e.g., `[]`, is rejected with a clear error.
- A non-object `.env` value is rejected with a clear error.
- A symlinked settings path updates the target file and preserves the symlink.
- A dangling symlinked settings path creates the missing target file and
  preserves the symlink.
- A second write against an already-hardened file is a semantic no-op and does
  not create a backup.

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

# Contributing

I'm still figuring out what I want here. Below follows a potential outline for this document.

In the meantime, feel free to file an issue to open a discussion. PRs will not be accepted without an issue to discuss.

If adding a new skill, also consider making your own marketplace.

## How These Skills Were Created

### The Iterative Process

### Research Phase

### Writing with Claude

### Validation and Refinement

## How to Update Skills

### Prerequisites

You need `jq` and `shellcheck` on your `PATH`; `./scripts/dev-setup.sh` checks for them, registers the local marketplace, and points Git at the repo's versioned hooks (installing Claude Code first if it's missing).

The commit and push quality gates live in `scripts/git-hooks` and are activated through `core.hooksPath`. If you work in this repo with Claude Code, you don't have to remember `dev-setup.sh` for the gates: a `SessionStart` hook in `.claude/settings.json` runs `scripts/ensure-git-hooks.sh` at the start of every session, idempotently re-pointing `core.hooksPath` at `scripts/git-hooks`. It stays silent unless it actually changes something.

### Making Changes

### Pre-Commit Validation

See [TESTING.md](TESTING.md) for local validation procedures, including the
isolated script regression checks and `act push` workflow smoke test.

### Submitting Changes

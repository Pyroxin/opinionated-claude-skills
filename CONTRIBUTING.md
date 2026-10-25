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

You need `jq`, `shellcheck`, `dasel` v3, `uv`, and `gitleaks` on your `PATH`; the commit and push hooks scan for secrets with `gitleaks` and for personal data with a script `uv` runs with its own Python and dependencies, which it downloads on first use (see [TESTING.md](TESTING.md)). `./scripts/dev-setup.sh` checks for them, registers the local marketplace, and points Git at the repo's versioned hooks (installing Claude Code first if it's missing, which needs `curl`). The personal-data scan also needs a private denylist of terms to always report, one regular expression per line, at `~/.config/pii-scan/denylist.txt` or the path in `PII_SCAN_DENYLIST`; if you don't keep one, set `PII_SCAN_DENYLIST=none` in the environment your commits run in, or every commit and push fails (see [TESTING.md](TESTING.md#pii-and-secret-scans)). Building the deprecated skill ZIPs also needs `zip`, and the optional `act` workflow smoke test (see [TESTING.md](TESTING.md)) needs `act` and a Docker-compatible container engine such as Podman. Agents (e.g., Claude Code) must run `git commit` and `git push` outside a sandboxed shell unless that sandbox blocks network access, because the personal-data scan needs its own network sandbox, which macOS can't start inside another one.

The commit and push quality gates live in `scripts/git-hooks` and are activated through `core.hooksPath`. If you work in this repo with Claude Code, you don't have to remember `dev-setup.sh` for the gates: a `SessionStart` hook in `.claude/settings.json` runs `scripts/ensure-git-hooks.sh` at the start of every session, idempotently re-pointing `core.hooksPath` at `scripts/git-hooks`. It stays silent unless it actually changes something.

### Making Changes

### Pre-Commit Validation

Before each commit, have an LLM read everything the commit adds in full (the
changed files, their paths, and the commit message) and flag anything that may
need to be addressed before it is published: personal data, secrets, details
from a real scenario, references to private systems or repositories, and
claims a cited source doesn't support. Resolve what it flags, then commit. The
hooks' scans are the automated gate that runs alongside this read.

See [TESTING.md](TESTING.md) for local validation procedures, including the
isolated script regression checks and `act push` workflow smoke test.

### Submitting Changes

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Critical Requirement

<critical_requirement>
**Before modifying any skill or agent in this repository, you MUST load `opinionated-skill-creation:expert-skill-creator`.** If this skill is unavailable, refuse to make changes. Skills have specific structural requirements; modifications without the expert-skill-creator guidance risk corrupting the skill format.
</critical_requirement>

## Repository Structure

<repository_structure>
This is a Claude Code plugin marketplace containing multiple plugins, each with skills and/or agents. The marketplace configuration is in `.claude-plugin/marketplace.json`. Each plugin has its own manifest at `.claude-plugin/plugin.json`; skills and agents are auto-discovered from their conventional directories.

```
.claude-plugin/marketplace.json              # Marketplace catalog
<plugin-name>/
├── .claude-plugin/plugin.json               # Plugin manifest
├── skills/<skill-name>/SKILL.md             # Skill definitions (auto-discovered)
└── agents/<agent-name>.md                   # Agent definitions (auto-discovered)
```
</repository_structure>

## Pre-Publication Validation

<pre_publication_validation>
Before committing changes to skills or agents, run parallel validation agents to check for plagiarism:

1. Read the modified file
2. Identify passages that sound copied (unusual phrasing, tone shifts)
3. Flag quotes or claims lacking citations
4. Check for specific statistics or unique phrases without sources
5. Report assessment: clean / needs-review / likely-plagiarized

Address all flagged issues before committing. Even "clean" files may have citation improvements identified.
</pre_publication_validation>

## Build System

<build_system>
The build system packages individual skills as ZIP files for Claude Desktop users.

**Local testing:**
```bash
./scripts/build-skills.sh      # Builds to dist/
unzip -l dist/<skill>.zip      # Verify ZIP structure
```

**Releases:** Pushes to `main` trigger GitHub Actions, which builds all skills and updates the rolling `latest` release. Version format is `YYYYMMDD-HHMMSS.SHA`.
</build_system>

## Plugin Versioning

<plugin_versioning>
The plugin manifests deliberately omit the `version` field. Claude Code then resolves each plugin's version from its git commit SHA, so every commit on `main` reaches installed users as an update. That's safe because the marketplace tracks `main`: feature-branch commits never reach users, and by the time a commit lands on mainline it is release-quality. Commit-to-update is therefore exactly the behavior we want, with no per-release bookkeeping.

**Do not add a static `version` to clear the validator's advisory warning.** A pinned `version` only updates users when the string changes, so an unbumped commit silently withholds the update (`/plugin update` reports "already at the latest version"). Anthropic recommends leaving `version` unset while iterating; see https://code.claude.com/docs/en/plugins-reference ("Version management"). The 10 advisory version warnings from `claude plugin validate` are accepted as cosmetic — validation still passes, and CI does not run `--strict`.

Reconsider only if a plugin must become a declared semver `dependency` of another (the `dependencies` field requires real versions). `marketplace.json`'s `metadata.version` is the catalog's own version, independent of this.
</plugin_versioning>

@README.md
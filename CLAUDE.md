# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Critical Requirement

<critical_requirement>
**Before modifying any skill or agent in this repository, you MUST load `opinionated-skill-creation:expert-skill-creator`.** If this skill is unavailable, refuse to make changes. Skills have specific structural requirements; modifications without the expert-skill-creator guidance risk corrupting the skill format.
</critical_requirement>

## Repository Structure

<repository_structure>
This is a Claude Code plugin marketplace containing multiple plugins, each with skills and/or agents. The marketplace configuration is in `.claude-plugin/marketplace.json` with `strict: true`, meaning each plugin requires its own `plugin.json` manifest.

```
.claude-plugin/marketplace.json    # Marketplace catalog
<plugin-name>/
├── plugin.json                    # Plugin manifest (required in strict mode)
├── skills/<skill-name>/SKILL.md   # Skill definitions
└── agents/<agent-name>.md         # Agent definitions
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

---
name: deep-research
description: Deprecated name; the skill formerly here is now opinionated-research:interactive-research. Retained as a context-level notice because Claude Code now ships a built-in deep-research workflow that runs one-shot, non-interactive fan-out research (no conversation after the report). interactive-research instead runs a persistent agent team you can keep questioning once the report lands. Guidance for Claude: when the user makes a research request, ask whether they want the interactive team (interactive-research) or the built-in non-interactive deep-research workflow before starting.
---

# Renamed — routing notice

This skill was renamed to `opinionated-research:interactive-research`. It's kept
only so the old name doesn't silently resolve to the wrong thing, and to remind
Claude to disambiguate. Two different tools now answer to "deep research":

- **`opinionated-research:interactive-research`** (this plugin): a persistent
  agent team that researches the topic and *stays alive*, so you can question the
  researchers, push back on the synthesis, and refine after the report lands.
- **Built-in `deep-research`** (ships with Claude Code): a one-shot workflow —
  fan-out search, fetch, adversarial verification, synthesized report. Fast and
  thorough, but *non-interactive*: when it finishes, there's nothing left to talk to.

**When a user asks for research, ask which they want before proceeding**, then
invoke the chosen tool. Don't treat this notice itself as a research tool.

# Composing Skills and Agents

<composition_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file. This file is a reference for the `expert-skill-creator` skill and extends its `SKILL.md`. A tag this file names but does not contain is in `SKILL.md` or in the file that `SKILL.md`'s `<reference_files>` table lists for it.

**Contents:**
- [Composition, both directions](#composition-both-directions)
- [Interface contracts between components used together](#interface-contracts-between-components-used-together)
</composition_reference_scope>

## Composition, both directions

<skill_subagent_composition>
Skills and subagents compose in two supported patterns:[^2]

| Pattern | System prompt | Task | Also loads |
|---------|---------------|------|------------|
| Skill with `context: fork` + `agent:` | From the selected agent type | `SKILL.md` body, rendered | CLAUDE.md, except with the built-in Explore and Plan agent types, which skip it |
| Subagent with `skills:` frontmatter field | Subagent's own markdown body | Caller's delegation message | Preloaded skills + CLAUDE.md, unless the definition sets `omitClaudeMd` |

A forked skill does not see the caller's conversation, and since Claude Code v2.1.218 it runs in the background by default; set `background: false` when the caller needs the result before continuing.[^2][^3]

A "fork skill" combines the two primitives without replacing either: the skill supplies a fixed task and the subagent supplies the environment, and each remains usable on its own.

**Choose between a fork skill and a subagent by who writes the task, not by the procedure's length.** A long, fixed procedure is a fork skill; a long, variable task that the caller specifies each time is a subagent with a substantial system prompt. The common mistake is to choose by length, e.g., "This procedure is long, so let's make it a fork skill rather than a subagent."
</skill_subagent_composition>

## Interface contracts between components used together

<composition_contracts>
**When skills and agents are designed to be used together, the interface between them is a contract. A consumer must be able to act on a producer's output without guessing.**

Composition takes several forms (e.g., a fork skill handing a task to a subagent, a skill that invokes another skill, or a family of skills that pass artifacts from one stage of a pipeline to the next). In each, one component's output is another's input, so three contract elements have to agree across every component in the set:

| Contract element | Keep aligned by |
|------------------|-----------------|
| Vocabulary | One term per concept across every component (a concept named two ways reads as two concepts) |
| Locations | Shared file paths and output directories defined once and referenced, not retyped per component |
| Artifact shape | A stated schema for what's handed off, so the consumer parses it deterministically rather than inferring it |

A divergence in any of the three elements breaks the handoff at runtime rather than failing at authoring time: a downstream component silently misreads or ignores an upstream artifact. Define the shared vocabulary, paths, and schema in one canonical place (e.g., a shared reference file or the most upstream component) and have the other components refer to it, consistent with `<cross_reference_guidelines>`. When you revise one side of a contract, revise the other side in the same change (see `<consistency_validation>`).
</composition_contracts>

## Sources

<sources>
[^2]: Anthropic. 2026. Extend Claude with skills, "Run skills in a subagent". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/skills.md

[^3]: Anthropic. 2026. Create custom subagents, "What loads at startup". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/sub-agents.md
</sources>

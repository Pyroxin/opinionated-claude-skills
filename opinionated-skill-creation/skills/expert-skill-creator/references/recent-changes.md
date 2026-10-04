# Recent Changes Sections

<recent_changes_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file. This file is a reference for the `expert-skill-creator` skill and extends its `SKILL.md`. A tag this file names but does not contain is in `SKILL.md` or in the file that `SKILL.md`'s `<reference_files>` table lists for it.

**Contents:**
- [Recent Changes Sections](#recent-changes-sections)
</recent_changes_reference_scope>

## Recent Changes Sections

<recent_changes_guidelines>
**Give every skill whose subject moves with releases (e.g., a language, framework, or tool skill) a `## Recent Changes` section, tagged `<recent_changes>`, dated against a stated baseline.**

Assume the models that run the skill were trained through a cutoff date, so everything that changed in the subject after that date is unknown to them unless the skill says it. A section titled "new features" with no date can't serve this purpose: the reader can't tell which entries are new relative to its own knowledge, and the author can't tell when the models' knowledge has come to include an entry.

**Baseline.** Use the oldest *reliable knowledge cutoff* (i.e., Anthropic's term for the date through which a model's knowledge is most extensive and reliable, as distinct from the broader training data cutoff) among the models in the comparison table on Anthropic's models overview page (currently Haiku, Sonnet, Opus, and Fable),[^8] and cite that page. Use the oldest cutoff rather than the newest because the skill can't know which model is running it: an entry that a model with a later cutoff already knows costs a few tokens, while an entry omitted for a model with an earlier cutoff produces stale output. State the baseline date and the versioned model it comes from (e.g., Claude Haiku 4.5, not "Haiku") in the section's first sentence, so a later maintainer can check from that sentence alone whether the baseline is still the oldest.

**Content.** Cover every change after the baseline that is relevant to the guidance the skill gives or to the output the model would produce with it, not only additions; omit a change with no such relevance (for example, an internal compiler improvement). The kinds of change to look for:
- Additions, grouped by release and dated.
- Behavior changes, i.e., existing code that now does something different (for example, an execution-semantics change behind a feature flag).
- Deprecations and removals.
- Community shifts, i.e., practices, libraries, or references the community is moving away from. Trained knowledge treats whatever was idiomatic at the cutoff as still idiomatic, so a shift the release notes never mention (for example, a style guide going dormant, or a package superseding a standard-library type) is the kind of change the model can't know.

Cite each entry to a release announcement, evolution proposal, release note, or other primary source (see `<citation_requirements>`). Where the skill covers a change in depth elsewhere, refer to that section rather than restating it, so each piece of information appears in one place (see `<skill_anatomy>` on progressive disclosure). Keep entries to a sentence or two, and put details in references or in local documentation the skill refers to.

**Maintenance.** Two events change the section: a new release of the subject adds entries, and a change in the model lineup moves the baseline later, after which entries older than the new baseline are removed. The retrofit runbook (`references/retrofitting-existing-skills.md`) checks both.

**Format:**
```markdown
## Recent Changes

<recent_changes>
**Baseline: {month} {year}.** This section assumes trained knowledge of {subject} through that date — the reliable-knowledge cutoff of {model-version}, the oldest among the current Claude models[^claude-models] — and lists what has changed since: additions, behavior changes, deprecations, and what {subject} or its community is moving away from. Treat anything older as known.

**Additions**, by release:
- **{subject} {version}** ({date})[^release]: {one-sentence summaries}

**Behavior changes, deprecations, and things being moved away from:**
- **{change}**: {what changed, what to do now}[^source]
</recent_changes>
```
The footnote labels in the template (`[^claude-models]`, `[^release]`, `[^source]`) are suggested keys, not placeholders; rename them to match the skill's own key scheme.
</recent_changes_guidelines>

## Sources

<sources>
[^8]: Anthropic. 2026. Models overview, "Compare models" table, rows "Reliable knowledge cutoff" and "Training data cutoff." Claude API Documentation. Retrieved September 5, 2026 from https://platform.claude.com/docs/en/models/overview
</sources>

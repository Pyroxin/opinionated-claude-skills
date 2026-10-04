# Retrofitting Existing Skills

<retrofit_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

A staged procedure for bringing an existing skill up to the standards in `expert-skill-creator`. Run it inline (Phase 2 interviews the user, so it cannot run in a forked subagent; see `<content_patterns>`). Run the phases in order; the claims audit precedes the prose passes because rewording sentences the audit will delete is wasted work.

Scope the effort to the findings: a skill whose triage finds few problems needs only the phases that address those problems (see `<proportional_engagement>` in SKILL.md).

When the upgrade follows the release of a new Claude model version, also run `<model_upgrade_checklist>` at the end of this file.

**Contents:** Phase 1, triage and baseline; Phase 2, intent and target models; Phase 3, architecture fit; Phase 4, claims and citation audit; Phase 5, content substance; Phase 6, language and framing; Phase 7, validation and closure; model-upgrade checklist; sources.
</retrofit_scope>

## Phase 1: Triage and baseline

<retrofit_triage>
1. Read the skill end-to-end. Inventory its sections, factual claims, directives, and external references.
2. Decide depth: full retrofit, or targeted fixes to the sections with findings.
3. Capture a baseline of what works today — where the skill triggers correctly and which guidance Claude applies well — so later phases can distinguish improvement from regression. This step applies the characterization test from Michael Feathers' *Working Effectively with Legacy Code*.
</retrofit_triage>

## Phase 2: Intent and target models (user interview)

<retrofit_interview>
1. Ask the user about the skill's intent so the content accurately communicates what they meant. Base the questions on the skill's content, especially its imprecisely written passages. Collect clarifications one at a time as free-form responses; do not present a list of questions to answer all at once.
2. Ask which model lines will run the skill. When the user has no stated preference, assume the Opus and Fable lines; for an agent definition or a skill that sets `model`, target the line that runs it. If the answer spans Fable and Sonnet or Haiku, or every model, explain the trade-off in `<model_targeting>` and ask whether to split the skill by line. Read the reference file for each line the skill targets (`references/prompting-fable.md`, `references/prompting-opus.md`, `references/prompting-sonnet.md`, `references/prompting-haiku.md`) and apply it in Phases 5 and 6.
3. Confirm scope boundaries: what the skill explicitly does not cover.
</retrofit_interview>

## Phase 3: Architecture fit

<retrofit_architecture>
1. Confirm, by the criteria in `<skill_vs_subagent_decision>` and `<content_patterns>`, that a skill is the right primitive and that it uses the right pattern: inline reference or fork task.
2. Apply progressive disclosure: move guidance used at a single step out of SKILL.md into `references/`, with load instructions and ordering per `<content_organization>`; move deterministic operations into `scripts/`; and check the body length against the targets in `<content_assessment>`.
3. If the skill composes with other skills or agents, check both sides of the interface contract (see `<composition_contracts>`).
</retrofit_architecture>

## Phase 4: Claims and citation audit

<retrofit_claims_audit>
1. From the Phase 1 inventory, verify each factual claim with tools (e.g., statistics, attributions, quotes, model behavior, API facts; see `<source_verification>`). Include claims the upgrade leaves unchanged; a claim's presence in the published skill is not evidence that anyone checked it.
2. Assign each claim a disposition: keep (verified), correct (source disagrees), or retire (no source). Check for version-specific claims stated as general facts.
3. Run the plagiarism check (see `<plagiarism_validation>`).
4. If the skill has a `<recent_changes>` section, re-derive its baseline from Anthropic's current models overview page (the oldest reliable knowledge cutoff among the models in its comparison table, currently Haiku, Sonnet, Opus, and Fable); move the baseline if the lineup changed, drop entries older than it, and add releases, behavior changes, deprecations, and community shifts that occurred since the section was last written (see `<recent_changes_guidelines>`).
5. Record claim-by-claim verdicts for the commit message in Phase 7, not in the skill tree.
</retrofit_claims_audit>

## Phase 5: Content substance

<retrofit_content_substance>
1. Cut content Claude already knows from training, condensing it to judgment frameworks. Keep safety guardrails even when they are well known, because condensing is the step in which they get silently deleted (see `<content_depth>`).
2. Convert how-to material into when/why decision frameworks where the judgment, not the procedure, is what makes the material useful (see `<decision_frameworks>`).
3. Reorder each section so the most important guidance comes first (see the guidance on position in `<xml_tag_guidelines>`).
4. Classify each forceful requirement: guidance gets a calm directive; invariants get routed to a deterministic gate (see `<guidance_vs_invariants>`).
5. If the skill's subject moves with releases and the skill has no `<recent_changes>` section, add one; convert an undated "new features" section to that form rather than keeping it (see `<recent_changes_guidelines>`).
</retrofit_content_substance>

## Phase 6: Language and framing

<retrofit_language>
1. Change the tone to the calm register, calibrated to the target model lines from Phase 2 (see `<directive_language>`).
2. Apply open-world framing: mark example lists as non-exhaustive, hedge claims about things that change, and assert only where the skill defines a closed set (see `<open_world_framing>`).
3. Apply the model-targeting rules: name model lines in guidance and version numbers only in evidence; remove instructions that ask the model to put its reasoning in the output, verbatim or in a fixed section or field; and trim over-prescription (see `<model_targeting>`).
4. Apply the XML tagging convention: a `<skill_scope>` opening, 1:1 correspondence between headers and tags, and descriptive `snake_case` names (see `<xml_tag_guidelines>`).
5. Rewrite the frontmatter description for discovery, concisely stating what the skill does, when to use it, and the terms that should trigger it (see `<description_optimization>`).
6. Add or repair cross-references to related skills, with a brief restatement of critical principles in case the referenced skill is not loaded (see `<cross_reference_guidelines>`).
</retrofit_language>

## Phase 7: Validation and closure

<retrofit_validation>
1. Run the full `<content_validation>` checklist, the PII and secret scan over the publish surface (see `<pii_and_secret_scanning>`), the related-skill consistency check (see `<consistency_validation>`), and the per-reference-file review (see `<reference_conformance_review>`).
2. Re-test in a clean context window against the Phase 1 baseline; a changed description changes triggering, so verify the skill still fires when expected (see `<empirical_validation>`). Fix regressions before proceeding.
3. Commit with the claim-by-claim verification ledger from Phase 4 in the commit message body.
</retrofit_validation>

## Model-Upgrade Checklist

<model_upgrade_checklist>
Run this checklist when a new Claude model version is released: first for `expert-skill-creator`'s own model reference files, then for each skill being upgraded. Anthropic publishes each version's prompting page as a set of differences from its predecessor's, and says prompts written for the predecessor should still work, so the work is finding which differences affect the skill, not rewriting it.

1. **Update the model references.** Read the new version's prompting page and its "What's new" page in full. Compare them with the matching `references/prompting-{line}.md` file, where `{line}` is the model line (fable, opus, sonnet, or haiku): add each new finding with its version, a short quote, and its source; mark findings the new page revises; and move superseded claims to the file's retired-claims section with the reason. Update `references/choosing-worker-models.md` and the scope paragraph's version and date in the same change. Check whether the new page changes any rule that `<model_targeting>` in `SKILL.md` states for every model.
2. **Audit the skill for content written for older models.** The following are the patterns current documentation identifies, not a complete list:
   - instructions to put reasoning in the output, verbatim or in a fixed section or field (e.g., `<thinking>` sections, `reasoning` fields);
   - instructions about how much to think (e.g., "think hard", "think carefully");
   - instructions to verify or re-check the model's own work, on lines documented to over-verify;
   - anti-formatting rules, on lines documented to under-format;
   - intensifiers used in place of a condition, and lines such as "If in doubt, use {tool}";
   - instructions that suppress progress narration (e.g., "hold all findings for the final response");
   - long enumerations of cases where a brief instruction would steer the same behavior, on lines documented to generalize from brief instructions;
   - claims or citations naming a model version the skill no longer targets.
3. **Run Claude Code's instruction audit where it reaches the skill.** In Claude Code v2.1.283 or later, `/doctor prompt-audit` checks instruction files for problems such as "instructions written for older models, references to files or commands that don't exist, and files that contradict each other."[^1] Its default scope is `CLAUDE.md`, `CLAUDE.local.md`, and `AGENTS.md` files plus the skills, subagents, rules, commands, and output styles under `.claude/` and `~/.claude/`; a skill kept elsewhere (e.g., in a plugin repository) is outside that scope, so confirm the audit examined the skill before treating its result as covering it (see `<positive_control>`). Resolve or record each finding.
4. **Check the Recent Changes baseline.** If the skill has a Recent Changes section and the model lineup changed, re-derive the baseline (see `<recent_changes_guidelines>`).
5. **Test on each target model.** Re-test the upgraded skill on every model that will run it, including the new version, against the baseline captured in Phase 1 (see `<empirical_validation>`).
</model_upgrade_checklist>

## Sources

<sources>
[^1]: Anthropic. 2026. How Claude remembers your project, "Audit your instruction files". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/memory.md
</sources>

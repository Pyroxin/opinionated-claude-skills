# Retrofitting Existing Skills

<retrofit_scope>
A staged procedure for bringing an existing skill up to the standards in `expert-skill-creator`. Run it inline (Phase 2 interviews the user, so it cannot run in a forked subagent; see `<content_patterns>`). Phases run in order; the claims audit precedes the prose passes because there is no value in polishing sentences the audit will delete.

Scope the effort to the findings: a skill that triages clean needs only the phases where problems surfaced (see `<proportional_engagement>` in SKILL.md).
</retrofit_scope>

## Phase 1: Triage and baseline

<retrofit_triage>
1. Read the skill end-to-end. Inventory its sections, factual claims, directives, and external references.
2. Decide depth: full retrofit, or targeted fixes to the sections with findings.
3. Capture a baseline of what works today — where the skill triggers correctly and which guidance Claude applies well — so later phases can distinguish improvement from regression. This is Michael Feathers' characterization-test move, from *Working Effectively with Legacy Code*.
</retrofit_triage>

## Phase 2: Intent and target models (user interview)

<retrofit_interview>
1. Ask the user about the intent of the skill so the content accurately communicates what they meant. Base questions on the skill's content, especially passages with imprecise writing. Collect clarifications one at a time as free-form responses; do not present a list of questions to answer all at once.
2. Ask which model classes the skill targets. When the user has no stated preference, assume Opus as the primary target with Fable as an opportunistic upgrade — never make the skill depend on Fable availability (see `<model_targeting>`). For Sonnet or Haiku targets, load `references/prompting-sonnet.md` or `references/prompting-haiku.md` and apply their calibration in Phases 5 and 6.
3. Confirm scope boundaries: what the skill explicitly does not cover.
</retrofit_interview>

## Phase 3: Architecture fit

<retrofit_architecture>
1. Confirm a skill is the right primitive, and in the right pattern — inline reference vs. fork task (see `<skill_vs_subagent_decision>` and `<content_patterns>`).
2. Apply progressive disclosure: move detailed reference material out of SKILL.md into `references/`, deterministic operations into `scripts/`, and check length against the targets in `<content_assessment>`.
3. If the skill composes with other skills or agents, check both sides of the interface contract (see `<composition_contracts>`).
</retrofit_architecture>

## Phase 4: Claims and citation audit

<retrofit_claims_audit>
1. From the Phase 1 inventory, verify each factual claim with tools — statistics, attributions, quotes, model behavior, API facts (see `<source_verification>`).
2. Disposition each claim: keep (verified), correct (source disagrees), or retire (no source). Watch for version-specific claims stated as general facts.
3. Run the plagiarism check (see `<plagiarism_validation>`).
4. Record claim-by-claim verdicts for the commit message in Phase 7 — not in the skill tree.
</retrofit_claims_audit>

## Phase 5: Content substance

<retrofit_content_substance>
1. Cut content Claude already knows from training, condensing to judgment frameworks — but keep safety guardrails even when well-known; condensing is how they get silently deleted (see `<content_depth>`).
2. Convert how-to material into when/why decision frameworks where the judgment is the value (see `<decision_frameworks>`).
3. Reorder so the most important guidance leads each section (see the primacy guidance in `<xml_tag_guidelines>`).
4. Classify each forceful requirement: guidance gets a calm directive; invariants get routed to a deterministic gate (see `<guidance_vs_invariants>`).
</retrofit_content_substance>

## Phase 6: Language and framing

<retrofit_language>
1. Correct tone to the calm register, calibrated to the target classes from Phase 2 (see `<directive_language>`).
2. Apply open-world framing: mark example lists non-exhaustive, hedge moving targets, assert only where the skill defines a closed set (see `<open_world_framing>`).
3. Apply model-targeting hygiene: model classes in guidance, version numbers only in evidence; remove instructions that tell the model to reproduce its internal reasoning as response text; trim over-prescription (see `<model_targeting>`).
4. Apply the XML tagging convention: `<skill_scope>` opening, 1:1 header-to-tag correspondence, descriptive `snake_case` names (see `<xml_tag_guidelines>`).
5. Rewrite the frontmatter description for discovery: what, when, and trigger terminology, concise (see `<description_optimization>`).
6. Add or repair cross-references to related skills, with brief insurance restatement of critical principles (see `<cross_reference_guidelines>`).
</retrofit_language>

## Phase 7: Validation and closure

<retrofit_validation>
1. Run the full `<content_validation>` checklist, the PII and secret scan over the publish surface (see `<pii_and_secret_scanning>`), and the related-skill consistency check (see `<consistency_validation>`).
2. Re-test in a clean context window against the Phase 1 baseline; a changed description changes triggering, so verify the skill still fires when expected (see `<empirical_validation>`). Fix regressions before proceeding.
3. Commit with the claim-by-claim verification ledger from Phase 4 in the commit message body.
</retrofit_validation>

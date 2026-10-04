# Validating a Skill

<validation_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file. This file is a reference for the `expert-skill-creator` skill and extends its `SKILL.md`. A tag this file names but does not contain is in `SKILL.md` or in the file that `SKILL.md`'s `<reference_files>` table lists for it.

**Contents:**
- [Validation Phase](#validation-phase)
  - [Content Validation Checklist](#content-validation-checklist)
  - [Positive Control for Every Check](#positive-control-for-every-check)
  - [Empirical Validation](#empirical-validation)
  - [Plagiarism and Citation Validation](#plagiarism-and-citation-validation)
  - [Reference-File Conformance Review](#reference-file-conformance-review)
  - [PII and Secret Scanning](#pii-and-secret-scanning)
  - [Per-Commit Publication Qualification](#per-commit-publication-qualification)
  - [Related Skill Consistency](#related-skill-consistency)
</validation_reference_scope>

## Validation Phase

<validation_phase>
**Validate a skill's content before finalizing it.**

### Content Validation Checklist

<content_validation>
Before completing a skill, verify:

**Structure:**
- [ ] YAML frontmatter has `name` and `description`
- [ ] Description states what the skill does and when to use it (at most 1,024 characters)
- [ ] Opens with `<skill_scope skill="skill-name">` containing related skills
- [ ] Major sections use XML tags with `snake_case` names
- [ ] Cross-references use the exact names of the skills they refer to

**Content Quality:**
- [ ] Focuses on judgment frameworks, not basic mechanics
- [ ] Includes decision tables for context-dependent guidance
- [ ] Has a common mistakes section organized by the practitioner background each mistake comes from (see `<common_mistakes_guidelines>`)
- [ ] If the subject changes with releases: has a `<recent_changes>` section whose baseline is the oldest current reliable knowledge cutoff, with additions, behavior changes, deprecations, and community shifts (see `<recent_changes_guidelines>`)
- [ ] Safety constraints are explicitly stated
- [ ] Directive language uses calm, direct framing (see `<directive_language>`)
- [ ] Instruction prose is literal: no figurative or evaluative language; each term of art is explained at first use or matches the ordinary meaning of the word (see `<literal_language>`)
- [ ] Statements are cast as instructions or assumptions, not bare descriptions (see `<instructional_formulation>`)
- [ ] No instructions to put the model's reasoning in the output, verbatim or in a fixed section or field (a `reasoning_extraction` refusal hazard on current models; see `<model_targeting>`)
- [ ] Guidance that depends on model behavior checked against the reference file for each model line the skill targets (see `<model_targeting>`)
- [ ] The skill targets the fewest model lines it needs; a skill spanning Fable and Sonnet or Haiku records that the user accepted the trade-off (see `<model_targeting>`)
- [ ] A skill that directs changes to code, documents, or configuration has an explicit scope rule (see `<model_targeting>`)
- [ ] One review agent per reference file of `expert-skill-creator` checked the skill against that file, and each finding is resolved or recorded (see `<reference_conformance_review>`)
- [ ] Invariants routed to a deterministic gate, not left as directives (see `<guidance_vs_invariants>`)
- [ ] A skill whose overhead can exceed what a task needs names a lighter alternative and when to use it (see `<proportional_engagement>`)
- [ ] Open-world framing: example lists marked non-exhaustive; closed-world claims only where closure is guaranteed (see `<open_world_framing>`)
- [ ] Resources are machine-readable (e.g., no videos)

**Attribution and Citations:**
- [ ] All third-party content is attributed (i.e., author and source work)
- [ ] Formal ACM citations used where warranted (see `<citation_scope>`)
- [ ] Each citation names the reference it records: the quote, paraphrase, term of art, statistic, or claim drawn from that source (see `<citation_provenance>`)
- [ ] Findings of mere topic overlap were resolved without adding a citation (see `<citation_provenance>`, `<plagiarism_validation>`)
- [ ] Sources verified with tools, not only from memory (see `<source_verification>`)
- [ ] URLs fetched to confirm they exist and contain the claimed content
- [ ] Quotes verified against the original source (not paraphrased from memory)
- [ ] Attributions confirmed (e.g., a statement attributed with "Apple says" comes from Apple)
- [ ] Sources section uses the format in `<citation_format>`
- [ ] No probable plagiarism
- [ ] Incomplete quotes end with ellipses
- [ ] No "Unknown" attributions (verify or remove each one)
- [ ] Quantitative claims have sources (or are qualified)
- [ ] Substantial paraphrasing cites the source

**Consistency:**
- [ ] No conflicts with related skills
- [ ] Cross-references agree with the content of the skills they point to
- [ ] Terminology is consistent throughout
- [ ] For skills used together: shared vocabulary, paths, and artifact schema agree (see `<composition_contracts>`)

**Publication Safety:**
- [ ] No PII or secrets in any tracked (i.e., publishable) file (see `<pii_and_secret_scanning>`)
- [ ] The whole publishable surface read in full, not only pattern-scanned (see `<pii_and_secret_scanning>`)
- [ ] Examples checked for real-scenario context leaks, not only for data-value patterns
- [ ] Every unpushed commit qualifies for publication on its own, not only the state the series ends in (see `<per_commit_publication_gate>`)
- [ ] Each check above reported a finding on a case it should catch before its null result was believed (see `<positive_control>`)
</content_validation>

### Positive Control for Every Check

<positive_control>
**Establish that a check can report a finding before treating a null result from it as evidence, because a check that cannot fail reports success under every condition.** Run the check once against a case it ought to catch: a positive control, i.e., the known-positive sample an experiment includes to show that the instrument responds. Where the check reports nothing on that case, it is not measuring anything, and its null result on the real content carries no information.

A null result has two causes that the result alone cannot distinguish: the content contains nothing the check looks for, or the check did not examine the content. The following table lists ways the second cause occurs; each was observed rather than hypothesized, and the list is not complete:

| How a check reports a null result without examining the content | How it appears | Control that exposes it |
|------------------------------------|--------------------|-------------------------|
| It examines one direction of a two-way relation | A footnote check reports every reference resolved, having never looked for definitions that nothing references | A definition with no reference to it |
| Its pattern cannot match the syntax it scans | A tag check counts an indented or attribute-carrying tag as absent; a footnote check counts an illustration inside a fenced block as a real definition | One indented tag; one fenced illustration |
| The tool errored instead of running | A shell pattern beginning with `-` is read as an option, so the scan never runs and its error text is mistaken for a finding | Any invocation whose exit status goes unread |
| Its path or scope missed the content | A scan of a moved or renamed file matches nothing | A control case inside the scanned scope |

Give the control a positive case for every pattern or rule the check applies, not one case for the check as a whole. A control that exercises two of a scan's ten patterns leaves eight unverified, and their zero counts on the real content carry no information while reading the same as the two counts that do.

Report what a check examined alongside what it found, and give the count rather than a verdict, because otherwise "zero findings across 40 files" and "zero findings because the glob matched no files" are reported with the same word. State the control's result next to the content's, per pattern, so a pattern the control did not exercise is visible rather than hidden among the patterns that respond.

This section extends the warning in `<pii_and_secret_scanning>` that a scan with no findings is not evidence that the surface has no leaks: that entry covers a wrong pathspec, and the same null result follows from every row above. It also applies to `<guidance_vs_invariants>`, which routes an invariant to a gate because only a mechanism observes actual state; a gate that cannot fail observes nothing, whatever it reports.
</positive_control>

### Empirical Validation

<empirical_validation>
**Refine skills iteratively with the user, based on their actual use.** Walk the user through the process of validating a skill.

After creating a skill:
1. Test it in a clean context window
2. Observe whether the skill triggers when expected and does not trigger otherwise
3. Note where Claude struggles, or where the skill's constraints keep Claude from a result it would otherwise reach
4. Refine the skill based on those observations

**Evaluation questions:**
- Does the skill trigger when expected?
- Does Claude apply the guidance correctly?
- Are there gaps where Claude lacks needed information?
- Does any constraint degrade results more than it improves them?
- Which reference files did each run open, and did it read each one in full? A file never opened, or previewed with a partial read, indicates that its load instruction is missing or ineffective (see `<content_organization>`).
- Does the skill behave consistently on every model that will run it (e.g., Opus and Fable, plus any Sonnet or Haiku worker; see `<model_targeting>`)? Anthropic's skill-authoring guide says to test a skill with all the models you plan to use it with.[^1] A directive calibrated for one model line may be followed too literally, expand in scope, or underperform on another (see `<directive_language>`).
</empirical_validation>

### Plagiarism and Citation Validation

<plagiarism_validation>
**For a skill intended for publication, run a plagiarism check on each skill file.**

**Parallel agent validation:** Launch multiple agents in parallel to check each skill file. Each agent should:
1. Read the skill file
2. Identify passages that sound copied (e.g., unusual phrasing, tone shifts)
3. Flag quotes or claims lacking citations
4. Check for specific statistics or unique phrases without sources
5. Separate wording that appears taken from a topic that merely overlaps published material, and report which of the two each finding is
6. Report an assessment: clean / needs-review / likely-plagiarized

**Example prompt for a validation agent:**
```
Read [skill file] and check for potential plagiarism. Look for:
1. Text that sounds copied from external sources
2. Quotes or specific claims lacking citations
3. Statistics or unique phrases without sources
For each finding, say whether specific wording or structure appears taken,
or whether the passage only covers the same subject as known material.
Report: File path, suspicious passages with line numbers, assessment.
```

**Post-validation:** Resolve flagged issues before publication, matching the remedy to the finding. Resolve a finding of taken wording by attributing, rewriting, or removing that wording. Resolve a finding that a passage only covers a well-known subject by leaving the passage as written; adding a citation there would record a reference the content never made (see `<citation_provenance>`). A file assessed "clean" can still have citation improvements identified, for sources the content does reference.
</plagiarism_validation>

### Reference-File Conformance Review

<reference_conformance_review>
**Before reporting a skill complete, run one review agent for each reference file of `expert-skill-creator`, in addition to the other validation agents (e.g., the plagiarism check in `<plagiarism_validation>`), and resolve or record every finding.** Each reference file holds guidance moved out of SKILL.md to keep it short, and an author reads only the reference files whose steps seem to apply, so a file whose guidance applied can go unread. A reviewer for every file checks the skill against all of the guidance, whichever files the author read.

Find the reference files by listing `expert-skill-creator`'s `references/` directory rather than from any list of them, so a file added later gets a reviewer without this section changing; a file present in the directory but missing from `<reference_files>` in SKILL.md is itself a finding. Launch the agents in parallel, each in a fresh context, on a model suited to review (see `references/choosing-worker-models.md`). Give each agent a brief that states:
- the skill under review, by path, and whether it is new or an upgrade (for an upgrade, also the path of the previous version);
- the one reference file to check against, by path, with the instruction to read that file and the skill in full;
- the task: decide whether the file's guidance applies to this skill, and give the reason when it does not (e.g., `prompting-sonnet.md` for a skill no Sonnet model runs); where it applies, report each place the skill departs from it, citing the section of the reference file and the line of the skill;
- that the agent reports findings and does not edit files.

Treat a reviewer's "does not apply" as a claim to check against the skill, not as a pass, because a reviewer that misjudges applicability reports nothing for a file whose guidance the skill needed.
</reference_conformance_review>

### PII and Secret Scanning

<pii_and_secret_scanning>
**Before publishing, review the whole publishable surface (i.e., every tracked file, not only the `SKILL.md` you edited) for personal data, secrets, and real-scenario context leaks. Read each file in full, because a pattern scan alone misses leaks that match no pattern and can silently match nothing.**

Skills are published in places such as GitHub releases, marketplaces, and shared ZIPs. What becomes public is every tracked file (e.g., skill bodies, agents, README, manifests, example snippets, and bundled resources), so review the whole tracked tree, not only the file you edited. Review untracked files that a later commit will include as well, before that commit is made.

The following table lists common leak vectors and how to distinguish a real leak from a false positive. Its patterns are examples to start the scan with, not a closed checklist; add patterns for other data your content may contain (e.g., physical addresses, OAuth client secrets, license keys):

| Vector | Example pattern | Usually benign when… |
|--------|-----------------|----------------------|
| Email addresses | `name@domain.tld` | Placeholder (`your@email.com`) or example domain (`example.com`, `test.`) |
| Home-path username leaks | `/Users/{name}`, `/home/{name}`, `C:\Users\{name}` | Generic placeholder (`/Users/you`, `$HOME`) |
| Credentials | API keys, bearer tokens, `AKIA…`, `-----BEGIN … PRIVATE KEY`, `ghp_…` | Treat every real-looking match as live until proven otherwise |
| Personal identifiers | Author's real name, phone, SSN | Citing a public figure's published work (attribution, not exposure) |
| Internal references | Private hostnames, internal URLs, ticket IDs | Public docs or documented example hosts |
| Context leaks in examples | An example or passage carrying detail from a real scenario, such as a real client, employer, project, person, system, or incident | The example is generic or invented (for example, a placeholder, a public technology, or a hypothetical) |

Most matches are false positives, so evaluate each one: a placeholder email and a citation to a public author are not leaks; a stray `/Users/yourname` path and a real-looking token need to be handled as leaks. When a match is a real secret, rotate it, because removing it from the working tree doesn't remove it from history, for the reason `<per_commit_publication_gate>` gives.

Read every tracked file end to end, because pattern matching alone misses problems such as these. First, a context leak, i.e., an example or passage carrying real-scenario detail without any token a pattern can flag (the last vector in the table), matches no pattern and is found only by reading. Second, a pattern scan can silently match nothing, when a path or pathspec is wrong or when the scanner errors instead of running; so a scan with no findings is not evidence that the surface has no leaks until you have also read the files and shown that the scan reports a case it should catch (see `<positive_control>`). Run both: read each file in full, and run a pattern scan (e.g., `git grep -nIE` for the vectors above) plus, for secrets, an entropy-based scanner (e.g., gitleaks, trufflehog) for the high-entropy strings that patterns miss. Add the scanners to the same validation gate as the other automated checks so they run every time; the full read is a manual step the reviewer is responsible for, and a scan with no findings does not excuse skipping it.
</pii_and_secret_scanning>

### Per-Commit Publication Qualification

<per_commit_publication_gate>
**Qualify every commit for publication before pushing, rather than only the state the series ends in, because a pushed commit stays retrievable by its own identifier whatever later commits do.** Hosting services address each commit directly (e.g., GitHub serves a commit at `/commit/{sha}`), so a reader can reach its content without any branch pointing to it, and a commit that a branch rewrite leaves unreferenced can remain served. A later commit that corrects the content therefore publishes a second version beside the first instead of withdrawing it.

This requirement generalizes the point about history in `<pii_and_secret_scanning>` (a committed secret needs rotating because deleting it doesn't remove it from history) from secrets to everything a publication check covers (e.g., personal data, a context leak from a real scenario, a quotation that doesn't match its source, a claim attributed to a document that doesn't support it).

Two requirements follow from it, with different scopes:

| What must hold | Scope | Why |
|----------------|-------|-----|
| Publication permissibility: nothing present that can't be public | Every commit | Each commit is independently fetchable, so one bad commit is published however clean the tip is |
| Functional validity: declared components resolve, the build runs | Every commit where mainline is the release surface; the tip otherwise | A consumer resolving a version from a commit identifier installs whatever that commit holds |

Two practices follow. First, correct a mistake in the commit that introduced it while that commit is unpushed, by amending it or by recording a fixup and squashing before the push, so no addressable version contains the mistake. Second, keep the series short, because each commit is a separate surface needing its own qualification, so dividing work into many commits multiplies the checking rather than dividing it.

State which scope each of a project's gates covers, so the unchecked region is visible. A gate that runs once before a push (e.g., a `pre-push` hook) qualifies the tip; a gate that runs on each commit (e.g., a `pre-commit` hook) qualifies every commit, to the depth of that gate's checks. Where the per-commit gate checks less than the pre-push gate, the commits between the base and the tip receive only the per-commit gate's narrower checks, which is a second reason to keep the series short.
</per_commit_publication_gate>

### Related Skill Consistency

<consistency_validation>
When creating or updating a skill, check for conflicts with related skills, and for interface-contract drift among skills used together:

1. **Identify related skills**: those with similar guidance, and any used together with this one
2. **Read full sections** rather than only searching for keywords with grep (conflicts may be conceptual)
3. **Check for principle conflicts** (i.e., conceptual contradictions) and, for skills used together, for interface-contract drift, i.e., divergent terminology, paths, or artifact shapes (see `<composition_contracts>`)
4. **Update all affected skills** in the same change when refining a principle or revising either side of a shared contract
</consistency_validation>
</validation_phase>

## Sources

<sources>
[^1]: Anthropic. 2026. Skill authoring best practices, "Test with all models you plan to use". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
</sources>

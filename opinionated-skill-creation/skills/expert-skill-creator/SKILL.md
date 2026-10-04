---
name: expert-skill-creator
description: Expert-level guidance for creating high-quality Claude Code skills. Use alongside Anthropic's skill-creator when creating new skills, improving existing skills, or needing guidance on skill content quality. Complements basic skill mechanics with research-driven content development, XML tag structuring, decision frameworks over mechanics, cross-references between skills, and systematic validation.
---

# Expert Skill Creator

<skill_scope skill="expert-skill-creator">
**Related skills:**
- `skill-creator:skill-creator` (Anthropic) - Basic skill mechanics, directory structure, initialization
- `opinionated-software-engineering:software-engineer` - Design principles that inform skill architecture
- `opinionated-software-engineering:test-driven-development` - Validation methodology parallels

**Load this skill together with Anthropic's `skill-creator:skill-creator` when creating skills.** `skill-creator:skill-creator` covers basic mechanics (e.g., directory structure, initialization scripts, packaging); this skill covers content quality, structure, and validation.

A skill is a modular package that extends Claude's capabilities with specialized knowledge, workflows, and tool integrations. It functions as a *retrieval trigger* that activates and organizes Claude's trained knowledge, not as teaching material that explains concepts from scratch. Because a skill activates existing knowledge, too much detail *constrains* behavior rather than enhancing it: give high-level frameworks that trigger trained knowledge, and reserve detailed content for areas that are novel to the model or where the model makes mistakes.

**Model calibration:** By default, skills written with this skill target the Opus and Fable lines; write an agent or skill that runs on a Sonnet or Haiku model for that line. Target the fewest lines a skill needs (see `<model_targeting>`), and before writing guidance that depends on how a model behaves, read the per-line reference files listed in `<reference_files>`.
</skill_scope>

## When to Use This Skill

<when_to_use>
Use this skill when:
- Creating a new skill from scratch
- Improving or refactoring an existing skill (for the staged procedure, see `references/retrofitting-existing-skills.md`)
- Evaluating skill quality against established guidelines
- Needing guidance on skill architecture, structure, or content depth
- Researching content for a skill using agents
- Validating skill content for accuracy and completeness

Do not use this skill for:
- General prompt engineering (this skill covers skills only)
- Subagent packaging mechanics (e.g., tool lists, model selection, agent frontmatter fields); agent prompt *content* follows similar quality principles (see `<directive_language>`)
- Skill frontmatter syntax beyond `name` and `description`; for fields and features such as `context`, `agent`, `allowed-tools`, `hooks`, argument substitution, and dynamic context injection, see `skill-creator:skill-creator`
- One-off instructions that don't warrant a reusable skill
</when_to_use>

## Reference Files

<reference_files>
Guidance used at specific steps is in `references/`. Read each reference file in full, from its first line to its last, when the step that names it begins. A partial read (e.g., a `head` preview or a limited line range) can miss rules later in the file, and nothing in the part read indicates what was skipped.

| Read this file | When | Sections it holds |
|----------------|------|-------------------|
| `references/creating-skills.md` | Starting a new skill | `<creation_process>` (steps 1-7), `<research_phase>` |
| `references/retrofitting-existing-skills.md` | Upgrading or refactoring an existing skill | The staged retrofit procedure |
| `references/composition.md` | Designing a skill used together with other skills or agents | Composition patterns, `<composition_contracts>` |
| `references/citations.md` | Adding sources, citations, or a Resources section | `<citation_format>`, `<citation_accuracy>`, `<source_verification>`, `<citation_mistakes>`, `<resources_guidelines>` |
| `references/recent-changes.md` | Writing or updating a Recent Changes section | `<recent_changes_guidelines>` |
| `references/validation.md` | Before reporting a skill complete, and before committing | `<validation_phase>`: `<content_validation>`, `<positive_control>`, `<empirical_validation>`, `<plagiarism_validation>`, `<pii_and_secret_scanning>`, `<per_commit_publication_gate>`, `<consistency_validation>` |
| `references/prompting-fable.md`, `references/prompting-opus.md`, `references/prompting-sonnet.md`, `references/prompting-haiku.md` | Before writing guidance that depends on how a model behaves, for each model line the skill will run on | Documented behavior of that line, by version, with retired claims |
| `references/choosing-worker-models.md` | Designing a skill or agent that spawns subagents | How a worker's model is set; what each model line is good and bad for |

A tag named in this skill but not found in the file being read is in the file this table lists for it.

This SKILL.md body is longer than the soft target in `<content_organization>` because its writing rules (e.g., `<directive_language>`, `<literal_language>`, `<model_targeting>`) apply to every instruction an author writes, so they stay in the body rather than in a reference file read at one step.
</reference_files>

## Skill vs. Subagent Decision

<skill_vs_subagent_decision>
**Before designing a skill, use the table below to confirm that the task calls for a skill and not a subagent.** Skills and subagents can do overlapping work but differ in who writes the task and in whether the work runs in the main conversation or in an isolated context, and converting one into the other later costs more than choosing correctly at the start.

### The core discriminator: who writes the task?

<task_author_discriminator>
| Primitive | Task text from | Reach for it when |
|-----------|----------------|-------------------|
| Subagent | The caller (main agent's delegation message or user's `@mention`) | Task content varies arbitrarily per invocation; value is "handle anything in domain X"; multiple skills or workflows might want it as a worker |
| Skill (inline) | The skill file itself; small parameterization via `$ARGUMENTS` | You have a repeatable procedure; steps are stable; you want `/slash-command` access; material benefits from the main context (e.g., conventions, reference, checklists) |
| Skill with `context: fork` | The skill file, sent as the subagent's task prompt | Skill-shaped procedure *and* one of: it would pollute main context; it needs a specialized environment (e.g., read-only tools, different model, restricted permissions); you want to pin it to a specific subagent type |

**Heuristics:**
- If you describe the task afresh every time you invoke the capability, it's a subagent
- If the task is fixed and only small inputs change, it's a skill
- If it's a fixed task *and* it either pollutes main context or needs a specialized environment, it's a skill with `context: fork`

When the skill will be used together with other skills or agents (e.g., a skill with `context: fork`, a subagent that preloads skills, or skills that pass artifacts down a pipeline), read `references/composition.md` in full before designing it.

Once you've chosen a skill, use `<content_patterns>` to choose between Reference (inline) and Task (fork) content.
</task_author_discriminator>
</skill_vs_subagent_decision>

## Skill Architecture

<skill_anatomy>
### Directory Structure

<directory_structure>
```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (required)
│   │   ├── name: lowercase-hyphenated (max 64 chars)
│   │   └── description: what + when (max 1024 chars)
│   └── Markdown body with XML-tagged sections
├── scripts/          - Executable code (deterministic operations)
├── references/       - Documentation loaded on-demand
└── assets/           - Files used in output (e.g., templates, icons)
```
</directory_structure>

### Progressive Disclosure

<progressive_disclosure>
Skills load in three levels, so each part of a skill enters the context only when needed:

| Level | Content | When Loaded | Size Target |
|-------|---------|-------------|-------------|
| 1. Metadata | name + description | Always in context | ~100 tokens |
| 2. SKILL.md body | Instructions, frameworks | When skill triggers | Under 5k tokens |
| 3. Bundled resources | Scripts, references, assets | As needed by Claude | Unlimited |

The size targets are Anthropic's.[^7] Measure a body in words, which a word count gives directly. As a rough estimate of this skill's own, not a measured figure, English prose runs about 1.3 to 1.7 tokens per word, and Markdown tables and code cost more per word, so the 5k-token target is about 3,000 words. The range is wide because tokenizers differ between models; for example, Anthropic says Sonnet 5 "uses a new tokenizer that produces approximately 30% more tokens for the same text" than Sonnet 4.6.[^10] For an exact count, use a token-counting tool for the target model.

**Design implication:** Keep SKILL.md short by moving detailed reference material, schemas, and examples to `references/` files, following `<content_organization>`. Put each piece of information in SKILL.md or in a reference file, never both.
</progressive_disclosure>

### Organizing Content Across Files

<content_organization>
**Split content between SKILL.md and reference files by when the reader needs it, not by topic.** Keep in SKILL.md the guidance the reader applies throughout the work (e.g., rules that shape every instruction the reader writes), and move to `references/` the guidance used at a step that signals when to read it (e.g., a validation checklist used before committing, a template used when adding one section). Treat about 3,000 words as a soft target for the body; a body may exceed it when the extra content is needed throughout the work and the skill states why (as this skill does in `<reference_files>`).

**Refer to each reference file with an instruction at the step that needs it.**
- Link every reference file directly from SKILL.md. Anthropic's skill-authoring guide says Claude "may partially read files when they're referenced from other referenced files", previewing them with commands such as `head -100`.[^14]
- State each load as an action tied to its step (e.g., "Before committing, read `references/validation.md` in full and run its checklist"), not as a bare pointer such as "see validation.md", which leaves the action implicit (see `<instructional_formulation>`).
- Instruct the reader to read reference files in full, from first line to last, once near the top of SKILL.md and again as the first line of each reference file. In any reference file longer than about 100 lines, follow that line with a table of contents, so a partial read still shows everything the file contains.[^14]
- List the reference files in one table that names each file, when to read it, and the sections it contains (as this skill's `<reference_files>` does), so the reader can find any section from one place.

**Order SKILL.md by how long each part must stay in effect.** Put first the guidance needed throughout a session, including the reference-file table and the read-in-full instruction. Two mechanisms favor the start of a file: after Claude Code compacts a conversation, it re-attaches an invoked skill keeping only "the first 5,000 tokens of each",[^15] and a partial read of a reference file sees only its beginning.[^14] Within each section, lead with the guidance the reader acts on (see `<xml_tag_guidelines>`).

**Test navigation.** When testing a skill, record which reference files each run opened and whether it read each one in full (see `<empirical_validation>`). Anthropic's guide lists missed connections and ignored files among the things to watch for.[^14]
</content_organization>

### Content Patterns

<content_patterns>
**Choose the pattern by what the skill does: a Reference skill adds to Claude's knowledge, and a Task skill orchestrates an independent workflow.** The two patterns are written differently:

| Pattern | Frontmatter | Content style | Example |
|---------|-------------|---------------|---------|
| **Reference** (inline) | Default | Knowledge, conventions, decision frameworks Claude applies alongside conversation context | Style guides, API conventions, language idioms |
| **Task** (fork) | `context: fork` | Self-contained task prompt with explicit steps; runs in an isolated subagent with no conversation history | Deployment workflows, research orchestration, batch operations |

**Reference skills** provide context Claude applies in its responses. Write them as frameworks and principles (as throughout this skill). They run inline with full conversation access.

**Task skills** are complete prompts sent to a subagent as its task. They need explicit instructions because the subagent has no conversation context. Use `context: fork`, and optionally `agent:` to select the execution environment (e.g., `Explore` for read-only, `general-purpose` for full tool access). Task skills can launch further agents through the Agent tool, enabling fan-out patterns such as parallel research or batch code changes.
</content_patterns>
</skill_anatomy>

## Quality Guidelines

<quality_guidelines>
These guidelines come from creating 15 or more skills and observing how they performed in clean context windows.

### XML Tag Structure

<xml_tag_guidelines>
**A skill is a prompt, so apply the XML-tagging practices in Anthropic's prompting guide.[^1]**

**Reasons to tag sections:**
- Clarity: Separate different parts of the skill
- Accuracy: Prevent Claude from mixing instructions with examples
- Flexibility: Make sections easy to find, add, remove, or modify
- Parseability: Enable structured reasoning about skill content

**Tag naming conventions:**
- Use descriptive `snake_case` names (e.g., `<dependency_update_checklist>`, `<error_handling_patterns>`, `<api_versioning_strategy>`)
- Avoid generic names such as `<remember>` or `<notes>`, which don't say what to remember or what the notes contain; prefer names such as `<migration_safety_constraints>` or `<version_compatibility_matrix>`
- Use the same tag name for the same concept throughout the skill
- Wrap each conceptually coherent unit of content that could be referenced on its own
- Nest tags for hierarchical content (e.g., `<platform_differences><macos_specifics>...</macos_specifics></platform_differences>`)

**Standard tags:**
- `<skill_scope skill="skill-name">`: Use for the skill's introductory section (e.g., overview, purpose, related skills). The `skill` attribute tells apart same-named tags from different skills when several are loaded at once (e.g., two skills that each open with `<skill_scope>`). Begin every skill with this tag, directly after the title.

**Explicit tag references:** Refer to a section by its tag name when discussing its content, so the reader sees which sections are connected and can find related guidance.

- Prefer: "Apply the guidelines in `<release_checklist>` before publishing"
- Less effective: "Apply the release checklist guidelines before publishing"
- Prefer: "Validate inputs at system boundaries (see `<input_validation_rules>` for requirements)"

**Tag attributes:**
- Use attributes for metadata distinct from content (e.g., `<example type="good">`, `<quote source="SICP">`)
- Use them sparingly, and keep behavioral guidance in tag content, because content inside tags receives more attention than attributes
- Suitable uses include source attribution, example classification, and conditional context markers

**Position:** Order sections, and the guidance within each section, for a reader who may stop early or read only the start of a file (see `<content_organization>`); within each section, put the guidance the reader must act on first:
- Lead with constraints whose violation makes the result wrong or unsafe, and follow with elaboration
- In a list ordered by priority, put the highest-priority items first

Anthropic's measurement concerns the document level and does not extend to ordering within a section: placing long documents and inputs (20k+ tokens) above the query and instructions "can improve response quality by up to 30 percent in tests, especially with complex, multidocument inputs."[^3]

**Tag granularity:**
- Wrap the content under every Markdown heading in an XML tag, which gives a 1:1 correspondence between visual structure (headings) and semantic structure (tags)
- Size each tag to roughly 10-100 lines of conceptually unified content (about one heading's worth)
- A tag is too coarse when it wraps several unrelated concepts under different headings, and too fine when it wraps individual sentences or single list items

**Combine XML with other techniques:**
- Multishot prompting: `<examples><example>...</example><example>...</example></examples>`
- Not a section or field for the model's reasoning: a `<thinking>` or `<reasoning>` section in the output, a once-common chain-of-thought pattern, can trigger a `reasoning_extraction` refusal on current models (see `<model_targeting>`)
- Conditional sections: `<if_typescript>...</if_typescript>`

**Example structure:**
```markdown
## Section Title

<section_name>
Most important guidance first...

<subsection_name>
Nested content...
</subsection_name>

Elaboration and details follow...
</section_name>
```
</xml_tag_guidelines>

### Content Depth and Philosophy

<content_depth>
**Write the judgment an experienced practitioner applies, not the step-by-step checklists a beginner needs.**

**Include:**
- Philosophical foundations (i.e., the "why" behind practices)
- High-judgment principles experienced practitioners recognize
- Trade-offs, context-sensitivity, and when rules should be broken
- Distinctions less experienced practitioners miss
- Systems thinking, emergent behavior, second-order effects

**Avoid:**
- Basic syntax Claude knows from training
- Step-by-step tutorials on fundamental concepts
- Low-level implementation details unless they affect judgment
- Overly granular instructions that constrain rather than guide

**Exception: include safety guardrails even when Claude already "knows" them.** They constrain behavior *toward* safety, not away from good behavior. Condense teaching content; keep safety guardrails.
</content_depth>

### Directive Language

<directive_language>
**Write directives calmly and directly, stating the scope, condition, or threshold an intensifier would otherwise stand in for.** "CRITICAL: You MUST use this tool" tells the reader nothing that "Use this tool when {condition}" does not, and leaves the condition unstated. This rule is this skill's convention, resting on that argument rather than on a measured effect on current models: Anthropic attributes over-triggering on emphatic language to Claude Opus 4.5 and Opus 4.6, and the same guide's own sample prompts still use "MUST" and "NEVER".[^3] Route a requirement that must hold without exception to a deterministic gate (see `<guidance_vs_invariants>`) rather than raising the emphasis. The following table gives examples of the substitution; it is not a complete list:

| Instead of | Write |
|------------|-------|
| "CRITICAL: You MUST..." | "Use {tool} when..." |
| "ALWAYS check..." | "Check {condition} before..." |
| "If in doubt, use {tool}"[^3] | "Use {tool} when it would improve your understanding of the problem" |

**Choose between describing the desired behavior and naming the behavior to avoid by what the instruction is for.**
- To set a style or format, describe or show it. Anthropic's general guide says "Tell Claude what to do instead of what not to do" (e.g., "Your response should be composed of smoothly flowing prose paragraphs" rather than "Do not use markdown in your response"), and its Opus 5 and Sonnet 5 pages report that positive examples of a communication style work better than instructions about what not to do.[^3][^4][^10]
- To suppress a specific behavior, name it, whether it is a default the model falls back on or a behavior known to be undesirable in the skill's domain (e.g., a common coding antipattern, or a practice that contradicts what the skill teaches; see `<common_mistakes_guidelines>`). Anthropic documents the first case for Opus 5.5: a general prohibition such as "avoid a generic AI look" "mostly swaps one default for another", while instructions naming specific patterns work.[^9] Extending that finding to known antipatterns is this skill's judgment: a named antipattern gives the reader a criterion it can check, and a general prohibition does not.

**State the scope of each instruction.** Documented instruction following differs by model line: Sonnet 5 reads instructions literally, especially at lower effort, and "does not silently generalize an instruction from one item to another"; Opus 5 follows a review filter such as "only report high-severity issues" literally while expanding the scope of other tasks; Fable 5 generalizes from a brief instruction.[^10][^4][^5] An instruction that states its scope, conditions, and thresholds reads the same way under all three behaviors, so use that form in any skill more than one line may run, including when the scope is broad (e.g., Anthropic's example "Apply this formatting to every section, not just the first one"[^10]). The per-line reference files give the details (see `<model_targeting>`).

**Include 3-5 few-shot examples** when a skill needs to demonstrate output format, tone, or reasoning patterns,[^3] wrapped in `<examples><example>...</example></examples>` tags. Vary them enough that the model does not copy features you did not intend; relevance to the skill's actual use and variety matter more than the number of examples. This recommendation covers every current model, Haiku 4.5 included. To fix one precise behavior, Anthropic documents one complete example (the request, the response, and a sentence explaining why the response is correct) for Fable 5.1's quotation marking[^16] (see `references/prompting-fable.md`).

This rule connects to the retrieval-trigger view in `<skill_scope>`: if skills activate existing knowledge, emphasis adds nothing the stated condition does not supply, and heavy prescription constrains behavior rather than activating capability. Use the minimum intensity that reliably produces the behavior, and confirm it on the target models.
</directive_language>

### Literal Language

<literal_language>
**Write skill instructions that can be interpreted correctly without knowledge that may be unavailable when the skill is read. Avoid figurative language (e.g., metaphor, idiom, or analogy used as instruction) and evaluative language (e.g., "elegant", "powerful", or a vague quality term such as "important"; see `<directive_language>`), and state conditions, thresholds, and actions directly.**

Assume the context available while you author a skill will be unavailable when it is read (see `<skill_anatomy>` on progressive disclosure, and `<instructional_formulation>` on phrasing this as a directive). Figurative and evaluative language depends on that context: a metaphor needs the authoring discussion to interpret, and a term such as "the right approach" needs a shared standard the reader lacks. State conditions and actions literally so they remain clear without it.

The rule targets a vague quality term the reader must apply as a criterion to decide what to do, where an undefined threshold produces miscalibrated behavior (see `<directive_language>` on stating thresholds explicitly). It does not target a quality term that marks a default tendency for the reader to weigh in context, provided you hedge it and supply the concrete basis for the judgment: the hedge signals a default rather than a rule, and the reader decides from the basis, not from the vague word. For example, "usually useful as a persistent teammate: it retains its context across idle periods, so it can handle follow-ups" is acceptable, because "usually" marks the default and the reason after the colon supplies the basis; "Use the most useful agent for the job" is not, because "useful" is the criterion and nothing grounds it. Use a hedged, grounded quality term deliberately, to invite judgment, and not in place of a criterion you could state concretely.

Terms of art are acceptable, and often useful, when explained at first use or when their meaning matches the word's ordinary meaning. A term that needs special knowledge the skill does not supply has the same defect as a metaphor: define it on first use or replace it. Introduce the terms of art the reader needs in order to use the skill's knowledge effectively.

Mark every example and reformulation explicitly, including example tables and sets, so they are not read as a closed or complete specification (see `<open_world_framing>`). The following table gives examples of the substitution; it is not a complete list:

| Figurative or evaluative (avoid) | Literal (prefer) |
|----------------------------------|------------------|
| "This step is a pre-flight check." | "This step verifies preconditions before proceeding." |
| "Spin up an elegant, powerful research team." | "Spawn a research team when {stated condition} holds." |
| "The task list is the team's coordination substrate." | "Teammates coordinate through the shared task list." |

This rule governs the skill's instruction text, not user-facing output the skill produces (e.g., a report for a human audience), where figurative or evaluative language may be appropriate.
</literal_language>

### Placeholder Notation

<placeholder_notation>
**Write a placeholder, i.e., a token the reader replaces with a value, in braces (e.g., `{project-root}`, `{your-name}`, `{timestamp}`). Reserve angle brackets for XML tags, covering both tag definitions and the `` `<tag_name>` `` references described in `<xml_tag_guidelines>`.**

A skill body uses angle brackets as structure, so a placeholder written as `<project-root>` uses the same notation as a section tag, and the reader can't tell from the token alone whether it marks a slot to fill or names a section. Braces carry no structural meaning in a skill body, so a braced token reads as a slot and nothing else.

The ambiguity causes the most errors in a prompt template that a skill tells the model to send to another agent, because the placeholder then arrives in a second context that also reads angle brackets as structure. Placeholders also cluster in paths and command templates.

Keep one notation throughout a skill. The common failure is mixing both inside a single expression; for example, `<project-root>/notes/{timestamp}/` asks the reader to resolve two notations for the same kind of token in one path. The following table gives examples of the substitution; it is not a complete list:

| Ambiguous (avoid) | Unambiguous (prefer) |
|-------------------|----------------------|
| `<project-root>/notes/{timestamp}/` | `{project-root}/notes/{timestamp}/` |
| `Report to the lead ('<lead-name>')` | `Report to the lead ('{lead-name}')` |
| `/Users/<name>` | `/Users/{name}` |

Braces here denote a value the reader supplies while following the instruction. Runtime argument substitution, where the harness replaces a token before the skill is read, is a separate mechanism with its own syntax; see `skill-creator:skill-creator`, as noted in `<when_to_use>`.

This rule governs the skill's instruction text and any template it carries. Inside content that reproduces another notation, that notation's meaning holds in both directions: angle brackets stay as they are in a CLI usage synopsis (`init_skill.py <skill_name>`), a generic type (`List<String>`), an HTML or XML example, or a shell redirect; braces stay as they are in shell expansion (`mkdir -p dir/{a,b}`). Such content usually appears in fenced code, and the fence signals the change of notation.
</placeholder_notation>

### Instructional Formulation

<instructional_formulation>
**When a statement's purpose is to drive behavior, cast it as an instruction the reader can act on. A fact stated as a bare description, with its intended action left implicit, may not produce that action; state the action, or the assumption to adopt, directly.**

The reader of a skill is a model executing it. "A skill loads into a fresh context window" leaves implicit what to do about it; "Assume the context available while you write the skill will not be available when it is read" states the action. The following table gives more examples; it is not a complete list:

| Bare description (action left implicit) | Instructional (prefer) |
|------------------------------------|------------------------|
| "A skill loads into a fresh context window without the context that produced it." | "Assume the context available while you write the skill will not be available when it is read." |
| "Specialists go idle between turns." | "Expect specialists to be idle between turns; do not treat idleness as a failure." |
| "The task list records ownership and status." | "Record ownership and status on the task list as work is claimed and completed." |

This rule targets bare description, not the descriptive content a judgment framework needs. A decision table, a trade-off analysis, or a "when to use what" comparison is itself an instruction: it tells the model how to judge, and the model needs its criteria and context to do so. Keep that content (see `<decision_frameworks>` and `<content_depth>`) rather than reducing it to imperatives. A principle is well cast as an assumption the model adopts rather than as an imperative; for example, `decision-analysis`'s "treat stated option value as hypothetical until grounded in the situation" is descriptive in subject but instructional in effect, and the model reasons from it. State the criteria, invoke them with an action ("assign a value using this table"), and keep the rationale that lets the model generalize.

This guideline complements `<directive_language>` (how forcefully to phrase a directive) and `<literal_language>` (keeping the directive plain); it governs whether a statement that should drive behavior is phrased to do so.
</instructional_formulation>

### Model Targeting

<model_targeting>
**Target the fewest model lines a skill needs, and write for those lines specifically.** Guidance does not transfer between lines by default; Anthropic's general guide says "Where a technique names a specific model, treat it as measured on that model and re-check it against your own evals before applying it to another."[^3] Some documented differences are opposed: Fable generalizes from a brief instruction and is degraded by prescription carried over from older skills, while Sonnet reads instructions literally and does not generalize them from one item to another.[^5][^10] A skill serving both lines must compromise between those behaviors, and this skill's position, which no published evaluation has tested, is that the compromise degrades the skill on both. The Opus and Fable lines show no documented opposition of that kind, so one skill can serve both. Apply the position as follows:
- Write a skill for the Opus and Fable lines together, or for a single line.
- When a user commissions a skill to run on Fable and on Sonnet or Haiku, or on every model, explain this trade-off before writing it and ask which lines it must serve; where more than one is needed, prefer one skill or agent per line.
- Write an agent definition, or a skill that sets `model`, for the line that runs it.

For a skill used across models, Anthropic's skill-authoring guide advises to "aim for instructions that work well with all of them";[^13] that advice applies once a skill spans lines, which the rules above aim to avoid.

Before writing guidance that depends on how a model behaves, read the reference file for each targeted line: `references/prompting-fable.md`, `references/prompting-opus.md`, `references/prompting-sonnet.md`, and `references/prompting-haiku.md`. For a skill that spawns agents, also read `references/choosing-worker-models.md`.

Apply the following rules in every skill, because they hold for every current model:
- **Ask for work products, not a transcript of reasoning.** On Fable 5.1, Fable 5, Opus 5.5, Opus 5, and Sonnet 5.5, a prompt, skill, or tool description that asks the model to put its reasoning in the output, "either verbatim or in a fixed format", may be declined with the `reasoning_extraction` refusal category; Anthropic's examples include a `<thinking>`, `<reasoning>`, or scratchpad section and a `reasoning`, `thinking`, or `trace` field in JSON output or a tool input.[^12] Ask instead for "a short explanation, the evidence behind a result, or a summary of the actions it took", which the same page says remain available. The trigger is sensitive to wording, so test a replacement field name (e.g., `rationale`) on the target models before a schema depends on it.
- **Leave the amount of thinking to the effort setting.** On Opus 5.5, "Lowering effort reduces thinking ... more reliably than prompt instructions do", and on Sonnet 5.5, asking for less thinking "doesn't reliably reduce its thinking".[^9][^11] Omit instructions such as "think hard" or "think carefully" from skill prose, and set the `effort` frontmatter field where a skill or subagent needs a level other than the session's.
- **Separate instructions to check the model's own work from instructions to run an external check.** Anthropic's general guide recommends asking the model to verify its answer against stated criteria, with Opus 5 as "the exception", where such instructions cause over-verification and should be removed.[^3][^4] Skills keep instructions to run an external check (e.g., a test suite, a linter, a validator script), which are a different instruction. Fable 5's page recommends fresh-context verifier subagents over self-critique, so which self-check instruction to write depends on the target line (see the per-line files).[^5]
- **State when delegation is warranted.** The Fable and Opus lines delegate to subagents readily; Anthropic recommends explicit criteria for when delegation is warranted, or deterministic caps on how many agents can be launched.[^4][^5] State the criteria in task skills that orchestrate agents (see `<content_patterns>`).
- **State the scope of changes.** Fable 5.1 and Sonnet 5.5 add work nobody asked for (e.g., nearby fixes, tests, documentation), and Opus 5 expands a task's scope;[^16][^11][^4] each line's page gives a scope instruction (see the per-line files). Give an explicit scope rule to every skill that directs changes to code, documents, or configuration, including a reference skill that tells the reader how to edit files (e.g., a shell skill that covers editing configuration files).

In skills you author, name model lines in guidance and versions in evidence (e.g., citations, provenance notes, dated status facts), so the guidance stays readable after a version changes and the evidence shows which version was measured.
</model_targeting>

### Guidance vs. Invariants

<guidance_vs_invariants>
**A directive is guidance the model can decline to follow. If a behavior must hold, enforce it with a mechanism, not a sentence.**

Skill content changes how likely a behavior is; it does not control execution. More forceful phrasing (e.g., "CRITICAL", "NEVER", "NO EXCEPTIONS") may raise the odds of compliance but does not guarantee it, and on some model lines it backfires (see `<directive_language>`). Before writing a requirement, classify it:

| Kind | Definition | How to encode it |
|------|------------|------------------|
| Guidance | The model should usually do X; an occasional miss is tolerable | A calm, positively-framed directive |
| Invariant | X must hold for the skill to be correct or safe; a single miss is a defect | A deterministic gate the skill runs (e.g., a script, validator, test, or hook), with the directive as a backstop rather than the sole guard |

**Treat escalating directive intensity as a design smell, i.e., a sign of a problem that wording cannot fix.** The urge to write "you MUST never mark this done unless tests pass" signals an invariant the prose cannot enforce; the fix is a gate (e.g., run the tests and read the result), not more forceful wording. A model can report following an unenforceable rule without having followed it; only a mechanism observes the actual state.

**Keep the guidance-versus-invariant judgment in your authoring, not in the prompt.** When no mechanism is available and a requirement stays guidance, state it as a plain positive instruction. Do not tell the model that the requirement is unenforced or that nothing stops it from skipping: the model reads "not enforced" as "optional," so the statement permits skipping and undercuts the directive. If a later step can check the behavior, have the model produce the inspectable state that step reads (e.g., a record a subsequent gate consults). Whether the check is enforced at runtime is your judgment as author, not content for the prompt.

This skill's own `<pii_and_secret_scanning>` applies this principle: it wires the scan "into the same validation gate ... enforced rather than remembered." In general, when a skill defines work that must happen (e.g., a precondition, a format, a check), prefer wiring it into a gate the skill executes over trusting the model to remember.

When the invariant is "the code does what the spec says," the gate is a test; see `opinionated-software-engineering:test-driven-development` (tests as contracts). For the broader principle of pushing correctness into mechanisms rather than convention, see `opinionated-software-engineering:software-engineer`.

This section covers *when* to use a gate and *what kind* to use; it does not yet cover *how to build one*. Concrete implementation patterns (e.g., wiring a hook, structuring a validator script, embedding a test the skill runs) are an open area not yet developed here.
</guidance_vs_invariants>

### Open-World Framing

<open_world_framing>
**Write skill instructions for an open world. The domains skills describe (e.g., tools, APIs, options, the model's own capabilities) keep changing, and any one skill covers only part of them.**

A list that reads as complete becomes wrong once the world adds a case it didn't enumerate, and it can suppress the model's trained knowledge of the omitted cases, the opposite of the retrieval-trigger goal in `<skill_scope>`. Default to phrasing that stays true as the world changes and as present unknowns become known.

Practices for open-world phrasing:
- Mark example lists as non-exhaustive: "e.g.,", "for example", "such as", "including but not limited to". Reserve "i.e.," for restating the same thing a different way, not for examples; the two markers mean different things.
- Hedge claims about things that change: "currently", "as of {date}", "tends to", "in most cases". Date-stamp facts that will age.
- Prefer describing the condition to closing the set (e.g., "use a feature flag when shipping incomplete work" rather than "always use a feature flag"); this practice reinforces the positive framing in `<directive_language>`.
- Lead parenthetical example lists with a marker such as "e.g.," or "for example,". A bare parenthetical such as "(JSON, YAML, TOML)" reads as the complete set or as an "i.e.," restatement; "(for example, JSON, YAML, TOML)" marks it as open.
- Mark example tables and multi-row example sets the same way, introducing them with a phrase such as "The following are examples, not a complete list." An unmarked example table can be read as a closed specification of the only acceptable cases.
- Mark reformulations with "that is", "i.e.,", or "in other words". An unmarked restatement can be read as a separate, independent claim rather than a different wording of the prior one.

Closure is sometimes correct, and over-hedging is a failure of its own. Assert plainly when the set is finite and the skill defines it (e.g., an enum the skill itself specifies), when an invariant holds, or for safety constraints, where closing *toward* safety is intentional (see `<content_depth>`). The discriminator is the skill's relation to the set: hedge where you describe an open domain, and assert where you define a closed one.

The following table gives examples of the rewrite; it is not a complete list:

| Closed-world phrasing | Open-world rewrite |
|-----------------------|--------------------|
| "The three valid options are X, Y, Z." (when more may arise) | "Options such as X, Y, and Z." |
| "This is the list of supported platforms." | "Supported platforms include …; check current docs for additions." |
| "X always causes Y." | "X usually causes Y; the outcome can depend on {factors}." |
</open_world_framing>

### Decision Frameworks

<decision_frameworks>
**Focus on when and why, not what and how.** Help the reader identify when to use a pattern, rather than teaching how to write basic syntax. Include content such as:
- Decision trees and trade-off analyses
- "When to use what" tables
- Context-dependent guidance
- Judgment frameworks for ambiguous situations

**Example format:**
```markdown
| Context | Approach | Why |
|---------|----------|-----|
| Short-lived, personal branch | Rebase | Linear history |
| Shared/public branch | Merge | Preserve collaboration |
| Audit requirements | Merge | Full history trail |
```
</decision_frameworks>

### Proportional Engagement

<proportional_engagement>
**When a skill's overhead exceeds what the task needs, say so and point to a lighter alternative.**

A skill that runs its full process on every invocation adds cost to small tasks the process was never needed for. Where a skill carries substantial overhead (e.g., multi-step workflows, heavy upfront planning, or multi-agent orchestration), state the conditions under which a lighter alternative, such as a simpler sibling skill, the model's native capabilities, or doing the task directly, is the better choice. This guideline extends the "do not use for" list in `<when_to_use>` from a fixed boundary to a judgment made during the work: when to stop partway, as well as when not to start. Scope the effort to the task; the goal is the result, not completing the full process for its own sake.
</proportional_engagement>

### Common Mistakes Sections

<common_mistakes_guidelines>
**Include common mistakes in every skill, organized by the practitioner's background**, because different backgrounds create different blind spots: a Java programmer learning Clojure makes different mistakes than a Python programmer learning Clojure.

Group the mistakes by the background practitioners come from, for example:
- `<from_java>` - Mistakes Java programmers make
- `<from_python>` - Mistakes Python programmers make
- `<from_bash>` - Mistakes bash users make
- `<general_anti_patterns>` - Universal mistakes

**Format:**
```markdown
### Common Mistakes

<common_mistakes>
#### From Java Users

<from_java>
- **Using class hierarchies**: Clojure prefers composition via protocols
- **Expecting mutable state**: Atoms/refs for coordinated state changes
</from_java>

#### From Python Users

<from_python>
- **Using None for missing values**: Use nil, but prefer explicit optionality
- **Imperative loops**: Use sequence operations (e.g., map, filter, reduce)
</from_python>
</common_mistakes>
```
</common_mistakes_guidelines>

### Recent Changes Sections

<recent_changes_requirement>
Give every skill whose subject moves with releases (e.g., a language, framework, or tool skill) a `## Recent Changes` section, tagged `<recent_changes>`, dated against a stated baseline. Before writing or updating one, read `references/recent-changes.md` in full; it defines the baseline, the content to include, maintenance, and a template.
</recent_changes_requirement>

### Cross-References

<cross_reference_guidelines>
**Reference authoritative skills, and briefly restate the principles essential to this skill's domain.**

**Strategy:**
1. **Primary reference**: Point to the authoritative skill for detailed guidance
   - For example, "See `opinionated-software-engineering:test-driven-development` skill for general testing philosophy"
2. **Insurance duplication**: Restate essential principles briefly (1-2 sentences)
   - Restate the core philosophy, in case the referenced skill is not loaded
   - Repeat safety-relevant "avoid X" rules
3. **Balance**: Give enough context for the skill to work standalone, but not so much that the skills become redundant

**When to reference vs. duplicate:**
- Reference when: Detailed guidance, examples, multiple subsections
- Brief restatement when: Core principle is critical to this skill's domain
- Full duplication when: Never (it indicates an architectural problem)

**Example:**
```markdown
## Testing

**For general testing philosophy, see the `opinionated-software-engineering:test-driven-development` skill.**
Core principle (restated): Tests are contracts—fix implementation, not tests.

This section covers language-specific practices...
```
</cross_reference_guidelines>

### Description Field Optimization

<description_optimization>
**The `description` field in YAML frontmatter determines whether and when Claude invokes the skill.** Include:
- WHAT the skill does
- WHEN Claude should use it
- Trigger terminology users would mention

**Example to follow (states what, when, and trigger terms):**
```yaml
description: Fish shell scripting judgment frameworks and critical idioms. Use when writing Fish scripts or shell automation. Focuses on when to use Fish vs bash, macOS/Fedora compatibility requirements, and Fish-specific patterns that prevent bugs.
```

**Example to avoid (states only the topic):**
```yaml
description: Fish shell scripting.
```

**Max length:** 1024 characters per description; `name` is capped at 64.[^7] Descriptions also share a collective budget: in Claude Code, the listing text per skill (combined `description` and `when_to_use`) is truncated at 1,536 characters (configurable with the `skillListingMaxDescChars` setting[^17]), and all listings share a budget defaulting to 1% of the model's context window (raisable via the `skillListingBudgetFraction` setting or the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable).[^6] On overflow, every skill name stays listed, but Claude Code drops descriptions starting with the least-invoked skills, removing the keywords discovery depends on. Description length is therefore a shared resource: a verbose 900-character description uses budget that other skills' discovery text needs.
</description_optimization>

### Content Assessment

<content_assessment>
**Set the level of detail for each topic by what Claude already knows about it:**

| Knowledge State | Treatment |
|-----------------|-----------|
| Well-known from training | Condense to principles and frameworks |
| After training cutoff | Include detail, examples, patterns |
| Known problem area | Justify expanded coverage |

**Example assessment (Swift skill):**
- Swift 6 concurrency (~470 lines): After cutoff, known problem → detailed coverage justified
- Protocol syntax (~30 lines): Known well → condensed to judgment framework
- Basic value types (~20 lines): Known well → brief guidance only

**Target lengths:** about 3,000 words for the SKILL.md body (see `<content_organization>` for the basis and when to exceed it). Reference files have no fixed limit; give any reference file longer than about 100 lines a table of contents. Count words rather than lines, because line length in a skill varies from a few words to a whole paragraph.
</content_assessment>

### Prose on Upgrade

<prose_on_upgrade>
**When asked to upgrade or update a skill, improve its prose opportunistically, but do not change what it means.** A new model generation often prompts an upgrade, and the upgrade is an occasion to make the existing guidance communicate more clearly: remove words that carry nothing, replace figurative or evaluative language with literal phrasing (see `<literal_language>`), mark examples (see `<open_world_framing>`), and remove content that does not help the reader act. Keep the skill's intent and substantive content fixed; change how it reads, not what it instructs.

**Add a behavioral rule during an upgrade only where the target model lines' documented behavior calls for one** (e.g., a scope rule under `<model_targeting>`), and list each added rule in the commit message. A rule that would improve the skill but changes what it asks of the reader is a change of intent: propose it to the user instead of adding it.

Cut carefully. A skill or agent is usually built gradually: adjustments accumulate during and after repeated use, and a clause that looks redundant often encodes a distinction someone added to fix a real failure, so removing it can reintroduce that failure. Cut content that carries no information (e.g., filler, bare restatement, or empty preamble), and preserve content that carries nuance even when it looks verbose (e.g., edge cases, conditions, exceptions, and the rationale a reader needs to generalize). When unsure whether a passage is filler or nuance the skill needs, keep it or ask rather than cut it. Over-cutting is a regression, not a cleanup. For the staged procedure, see `references/retrofitting-existing-skills.md`.
</prose_on_upgrade>
</quality_guidelines>

## Citation Requirements

<citation_requirements>
**Attribute all third-party content, and use a formal ACM citation when the source adds value (see `<citation_scope>` for the cases).**

### What Requires Attribution

<citation_scope>
**Distinguish attribution from formal citation:**
- **Attribution**: Acknowledging the source (always required for third-party content)
- **Formal ACM citation**: Full bibliographic reference with footnote (sometimes required)

**Must attribute** (each of these describes content that referenced a source; see `<citation_provenance>`):
- Direct quotes from any source
- Specific claims attributed to sources
- Statistics, benchmarks, or empirical findings
- Code patterns adapted from specific sources
- Well-known concepts with identifiable originators, where the skill draws on the concept as such

**Informal attribution is sufficient for:**
- Short quotes (single sentences); use `"quote" — Author, Source Work`
- Well-known aphorisms where the author is the key information
- Cases where the source work is widely known (e.g., SICP, "Simple Made Easy")

**Use a formal ACM citation when:**
- The source would be useful for Claude to look up (e.g., URLs, documentation)
- Fair-use concerns exist (substantial portions, not just short quotes)
- Content substantially paraphrases a source (cite the source being paraphrased)
- Statistics or empirical claims need verification
- Code or patterns are adapted from a specific source

**Does not require attribution:**
- General programming knowledge without an identifiable originator (e.g., "functions should do one thing")
- Claude's own analysis and synthesis
- Content the skill author created

**Judgment call:** When you used a source and are unsure whether its attribution should be formal or informal, attribute. Uncertainty about the *form* of attribution resolves toward attributing; uncertainty about whether you used a source at all resolves by checking what you actually drew on (see `<citation_provenance>`), not by citing.
</citation_scope>

### Citation Provenance

<citation_provenance>
**A citation records a reference. Cite a source when the skill's content actually referenced it, and not otherwise.**

Overlap is not a reference. Content that resembles published material but was derived from your own reasoning or from the user's problem referenced nothing, so it has nothing to cite. This conclusion follows from the definition, not from a judgment call: skills cover familiar subjects, so two parties reasoning about the same problem are expected to reach similar conclusions, and noticing the resemblance afterward does not turn independently derived content into third-party content.

Citing an unreferenced source is a failure distinct from the two covered elsewhere, i.e., inventing bibliographic details (see `<citation_accuracy>`) and taking details from memory without checking them (see `<source_verification>`), and it passes both of their checks. A real source, verified to say what you claim and correctly formatted, still misstates where the content came from when attached to content that never referenced it, and neither verification nor formatting can detect that misstatement.

**Name the reference before citing it.** Identify what the content took from the source: a quote, a paraphrase, a term of art, a statistic, a code pattern, or a claim you relied on the source to support. If you can name it, cite it; if you cannot, there is no reference and therefore no citation. One operational check: ask whether the citation would be present had no reviewer, linter, or reader remarked on the resemblance; if not, the content did not reference that source.

**Leave the text as written rather than giving a citation something to attach to.** Introducing a source's named concept into a passage so a footnote has an anchor creates the reference the footnote then records; before the edit, the passage named and cited nothing. Where a passage does not already reference a source, adding that source's vocabulary in order to cite it makes the skill less accurate about its own origins.

**Before citing an authority, check that its position agrees with the skill.** A named source brings its surrounding position on the topic into the skill, and a reader may apply that position where the skill does not intend it; a citation that contradicts nearby guidance undercuts that guidance. Where the substance is sound but the source's position conflicts, state the substance directly and cite nothing.

**When a review flags resemblance to known material,** confirm whether wording, structure, or terminology was actually taken. Where something was, attribute it. Where nothing was, leave the text as written and record the finding as resolved; a resemblance report is not by itself a citation gap (see `<plagiarism_validation>`).
</citation_provenance>

For citation format, citation accuracy, source verification, and common citation mistakes, read `references/citations.md` in full before adding or checking citations.

</citation_requirements>

## Skill Tiers and Relationships

<skill_tiers>
**Skills form a hierarchy with fallback behavior:**

| Tier | Purpose | Example |
|------|---------|---------|
| Meta-skill | Universal principles | `opinionated-software-engineering:software-engineer` |
| Paradigm skills | Fallback for language families | `functional-programmer`, `object-oriented-programmer` |
| Language skills | Specific language guidance | `java-programmer`, `clojure-programmer` |
| Process skills | Situation-specific | `opinionated-software-engineering:test-driven-development`, `opinionated-software-engineering:git-version-control` |

**Invocation behavior:**
- Language-specific skills supersede paradigm skills (no redundant loading)
- The meta-skill (`opinionated-software-engineering:software-engineer`) is invoked for all coding tasks
- Process skills are invoked based on activity (e.g., testing, committing)

**Content placement:**
- System-level patterns (e.g., hexagonal architecture) → `opinionated-software-engineering:software-engineer`
- Paradigm-specific patterns (e.g., FP composition) → paradigm skills
- Language-specific syntax/tooling → language skills
- Universal processes (e.g., TDD, Git) → process skills
</skill_tiers>

## Anti-Patterns

<anti_patterns>
The following patterns reduce skill effectiveness, grouped by where they occur.

### Content Anti-Patterns

<content_anti_patterns>
- **Teaching basics**: Explaining concepts (e.g., map/filter/reduce) when Claude knows them from training
- **Aggressive directives**: Using "CRITICAL", "MUST", "ALWAYS" in place of the condition or threshold the reader needs (see `<directive_language>`)
- **Over-constraining**: Including so much detail that Claude can't apply judgment
- **Duplicate content**: Putting the same information in multiple skills
- **Missing safety**: Omitting safety guardrails because "Claude knows" (see `<content_depth>`)
</content_anti_patterns>

### Structure Anti-Patterns

<structure_anti_patterns>
- **No XML tags**: Unstructured content that's hard to navigate
- **Flat organization**: No hierarchy or progressive disclosure
- **Missing cross-references**: Skills with no connection to the rest of the ecosystem
- **Vague description**: A description that doesn't enable discovery
</structure_anti_patterns>

### Process Anti-Patterns

<process_anti_patterns>
- **No research**: Creating skills for unfamiliar domains without investigation
- **No validation**: Shipping skills without verification
- **No iteration**: Treating skills as write-once artifacts
- **No citations**: Including third-party content without attribution
- **Memory as verification**: Treating training data memories as verified facts; citing URLs, quotes, or attributions without using tools to confirm accuracy
</process_anti_patterns>
</anti_patterns>

## Resources

<resources>
**Official documentation:**
- Claude Code Skills: https://code.claude.com/docs/en/skills.md
- Claude Code Subagents: https://code.claude.com/docs/en/sub-agents.md
- Prompting Best Practices (including XML tags): https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Per-model prompting pages (Fable, Opus, and Sonnet lines), linked from the best-practices page's model-specific guidance table and cited in the per-line reference files
- Skill Authoring Best Practices: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Agent Skills Overview: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- Refusals and Fallback: https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
- Model Migration Guides: https://platform.claude.com/docs/en/about-claude/models/migration-guide

**Bundled references:** see `<reference_files>` for each file and when to read it.

**Related skills:**
- `opinionated-software-engineering:software-engineer` - Design principles informing skill architecture
</resources>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting best practices, "Structure prompts with XML tags". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices (the former standalone page on XML tags now redirects here)

[^3]: Anthropic. 2026. Prompting best practices. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^4]: Anthropic. 2026. Prompting Claude Opus 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5

[^5]: Anthropic. 2026. Prompting Claude Fable 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

[^6]: Anthropic. 2026. Extend Claude with skills, "Frontmatter reference" and "Skill descriptions are cut short". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/skills.md

[^7]: Anthropic. 2026. Agent Skills, "How Skills work". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview

[^9]: Anthropic. 2026. Prompting Claude Opus 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5

[^10]: Anthropic. 2026. Prompting Claude Sonnet 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5

[^11]: Anthropic. 2026. Prompting Claude Sonnet 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5

[^12]: Anthropic. 2026. Refusals and fallback, "Keep reasoning in thinking blocks". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback

[^13]: Anthropic. 2026. Skill authoring best practices, "Test with all models you plan to use". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

[^14]: Anthropic. 2026. Skill authoring best practices, "Avoid deeply nested references", "Structure longer reference files with table of contents", and "Observe how Claude navigates Skills". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

[^15]: Anthropic. 2026. Extend Claude with skills, "Skill content lifecycle". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/skills.md

[^16]: Anthropic. 2026. Prompting Claude Fable 5.1. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1

[^17]: Anthropic. 2026. All settings, "`skillListingMaxDescChars`". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/settings-reference.md
</sources>

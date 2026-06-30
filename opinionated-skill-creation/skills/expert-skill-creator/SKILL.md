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

**This skill complements Anthropic's `skill-creator:skill-creator` skill.** Load both when creating skills: `skill-creator:skill-creator` provides basic mechanics (e.g., directory structure, initialization scripts, packaging), while this skill provides expert-level guidance on content quality, structure, and validation.

Skills are modular packages that extend Claude's capabilities by providing specialized knowledge, workflows, and tool integrations. They function as **retrieval triggers** that activate and organize Claude's trained knowledge, not as teaching material that explains concepts from scratch.

**Critical insight**: For LLMs, skills activate existing knowledge rather than teaching new content. The risk is that too much detail *constrains* behavior rather than enhancing it. Skills should provide high-level frameworks that trigger trained knowledge, with detailed content reserved for genuinely novel or problematic areas.

**Model calibration:** This skill assumes Opus as the authoring model and targets created skills primarily at Opus and Fable. Fable 5 is new and capacity-limited as of June 2026; treat it as an upgrade path rather than a dependency (see `<model_targeting>`). For skills targeting Sonnet or Haiku tiers, see `references/prompting-sonnet.md` and `references/prompting-haiku.md`.
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
- General prompt engineering (this is skill-specific)
- Subagent packaging mechanics (e.g., tool lists, model selection, agent frontmatter fields) — though agent prompt *content* follows similar quality principles; see `<directive_language>`
- Skill frontmatter syntax beyond `name` and `description` — see `skill-creator:skill-creator` for fields like `context`, `agent`, `allowed-tools`, `hooks`, argument substitution, and dynamic context injection
- One-off instructions that don't warrant a reusable skill
</when_to_use>

## Skill vs. Subagent Decision

<skill_vs_subagent_decision>
**Before designing a skill, verify that a skill is the right primitive.** Skills and subagents solve overlapping problems at different layers. A skill that should have been a subagent (or vice versa) is harder to fix later than getting the choice right up front.

### The core discriminator: who writes the task?

| Primitive | Task text from | Reach for it when |
|-----------|----------------|-------------------|
| Subagent | The caller (main agent's delegation message or user's `@mention`) | Task content varies arbitrarily per invocation; value is "handle anything in domain X"; multiple skills or workflows might want it as a worker |
| Skill (inline) | The skill file itself; small parameterization via `$ARGUMENTS` | You have a repeatable procedure; steps are stable; you want `/slash-command` access; material benefits from the main context (e.g., conventions, reference, checklists) |
| Skill with `context: fork` | The skill file, sent as the subagent's task prompt | Skill-shaped procedure *and* one of: it would pollute main context; it needs a specialized environment (e.g., read-only tools, different model, restricted permissions); you want to pin it to a specific subagent type |

**Heuristics:**
- If you describe the task afresh every time you invoke the capability, it's a subagent
- If the task is fixed and only small inputs change, it's a skill
- If it's a fixed task *and* it either pollutes main context or needs a specialized environment, it's a skill with `context: fork`

### Composition, both directions

Skills and subagents compose in two supported patterns[^2]:

| Pattern | System prompt | Task | Also loads |
|---------|---------------|------|------------|
| Skill with `context: fork` + `agent:` | From the selected agent type | `SKILL.md` body, rendered | CLAUDE.md |
| Subagent with `skills:` frontmatter field | Subagent's own markdown body | Caller's delegation message | Preloaded skills + CLAUDE.md |

A "fork skill" composes the two primitives rather than replacing either: the skill supplies a fixed task, the subagent supplies the environment. Both remain independently usable on their own.

**Common confusion to avoid:** "This procedure is long, so let's make it a fork skill rather than a subagent." The procedure's length isn't the discriminator — who writes the task is. A long, fixed procedure is a fork skill. A long, variable task that the caller specifies each time is a subagent with a substantial system prompt.

### Interface contracts between components used together

<composition_contracts>
**When skills and agents are designed to be used together, the interface between them is a contract. A consumer must be able to act on a producer's output without guessing.**

Composition takes several shapes (e.g., a fork skill handing a task to a subagent, a skill that invokes another skill, or a family of skills that pass artifacts down a pipeline). In each, one component's output is another's input, so three things have to agree across the set:

| Contract element | Keep aligned by |
|------------------|-----------------|
| Vocabulary | One term per concept across every component (a concept named two ways reads as two concepts) |
| Locations | Shared file paths and output directories defined once and referenced, not retyped per component |
| Artifact shape | A stated schema for what's handed off, so the consumer parses it deterministically rather than inferring it |

Drift in any of these breaks the handoff at runtime — a downstream component silently misreads or ignores an upstream artifact — rather than failing at authoring time. Define the shared vocabulary, paths, and schema in one canonical place (e.g., a shared reference file or the most upstream component) and have the others point to it, consistent with `<cross_reference_guidelines>`. When you revise one side of a contract, revise the other side in the same change (see `<consistency_validation>`).
</composition_contracts>

Once you've decided a skill is the right primitive, see `<content_patterns>` for choosing between Reference (inline) and Task (fork) content.
</skill_vs_subagent_decision>

## Skill Architecture

<skill_anatomy>
### Directory Structure

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

### Progressive Disclosure

Skills use three-level loading to manage context efficiently:

| Level | Content | When Loaded | Size Target |
|-------|---------|-------------|-------------|
| 1. Metadata | name + description | Always in context | ~100 words |
| 2. SKILL.md body | Instructions, frameworks | When skill triggers | <5k words |
| 3. Bundled resources | Scripts, references, assets | As needed by Claude | Unlimited |

**Design implication**: Keep SKILL.md lean. Move detailed reference material, schemas, and examples to `references/` files. Information should live in either SKILL.md or references, never both.

### Content Patterns

<content_patterns>
Skills fall into two architectural patterns that require different content approaches:

| Pattern | Frontmatter | Content style | Example |
|---------|-------------|---------------|---------|
| **Reference** (inline) | Default | Knowledge, conventions, decision frameworks Claude applies alongside conversation context | Style guides, API conventions, language idioms |
| **Task** (fork) | `context: fork` | Self-contained task prompt with explicit steps; runs in an isolated subagent with no conversation history | Deployment workflows, research orchestration, batch operations |

**Reference skills** provide context Claude weaves into its responses. Write them as frameworks and principles (as throughout this skill). They run inline with full conversation access.

**Task skills** are complete prompts that drive a subagent. They need explicit instructions because the subagent has no conversation context. Use `context: fork` and optionally `agent:` to select the execution environment (e.g., `Explore` for read-only, `general-purpose` for full tool access). Task skills can launch further agents via the Agent tool, enabling fan-out patterns like parallel research or batch code changes.

Choose the pattern based on whether the skill augments Claude's knowledge (reference) or orchestrates an independent workflow (task).
</content_patterns>
</skill_anatomy>

## Quality Guidelines

<quality_guidelines>
These guidelines emerged from creating 15+ skills and observing their performance in clean context windows.

### XML Tag Structure

<xml_tag_guidelines>
**Skills are prompts—apply XML tagging best practices.[^1]**

**Why XML tags matter:**
- Clarity: Separate different parts of the skill
- Accuracy: Prevent Claude from mixing instructions with examples
- Flexibility: Easy to find, add, remove, or modify sections
- Parseability: Enable structured reasoning about skill content

**Tag naming conventions:**
- Use descriptive `snake_case` names: `<dependency_update_checklist>`, `<error_handling_patterns>`, `<api_versioning_strategy>`
- Avoid generic names—`<remember>` or `<notes>` don't describe what to remember or what the notes contain; prefer names like `<migration_safety_constraints>` or `<version_compatibility_matrix>`
- Maintain consistent names throughout—same concept, same tag name
- Wrap coherent conceptual chunks that could be referenced independently
- Nest tags for hierarchical content: `<platform_differences><macos_specifics>...</macos_specifics></platform_differences>`

**Standard tags:**
- `<skill_scope skill="skill-name">` — Use for the skill's introductory section (e.g., overview, purpose, related skills). The `skill` attribute prevents collision when multiple skills are loaded. Every skill should begin with this tag after the title.

**Explicit tag references:**
Reference tags by name when discussing their content. This reinforces connections between sections and helps readers navigate related guidance.

- Good: "Apply the guidelines in `<release_checklist>` before publishing"
- Weak: "Apply the release checklist guidelines before publishing"
- Good: "Validate inputs at system boundaries (see `<input_validation_rules>` for requirements)"

**Tag attributes:**
- Attributes carry metadata distinct from content: `<example type="good">`, `<quote source="SICP">`
- Use sparingly; content inside tags receives more attention than attributes
- Keep behavioral guidance in tag content rather than attributes; attribute content receives less attention
- Good uses: source attribution, example classification, conditional context markers

**Position matters (primacy bias):**
Content earlier in a tag receives more attention than content later. At the document level, placing long reference material at the top with instructions and queries at the bottom can improve response quality by up to 30% in tests on multi-document inputs.[^3] Within sections, structure accordingly:
- Put the guidance the reader must act on first within each section
- Lead with critical constraints, follow with elaboration
- If ordering a list by priority, highest priority items should come first

**Tag granularity:**
- Every markdown header's content should be wrapped in an XML tag
- This creates 1:1 correspondence between visual structure (headers) and semantic structure (tags)
- Too coarse: One tag wrapping multiple unrelated concepts under different headers
- Too fine: Tagging individual sentences or single list items
- Right-sized: Roughly 10-100 lines of conceptually unified content (approximately one header's worth)

**Combine XML with other techniques:**
- Multishot prompting: `<examples><example>...</example><example>...</example></examples>`
- Chain-of-thought as a manual fallback when API thinking is off: `<thinking>...</thinking><answer>...</answer>`[^3] — avoid in skills that may run on Fable-class models, where instructing the model to reproduce its reasoning as response text can trigger a `reasoning_extraction` refusal (see `<model_targeting>`)
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
**Staff-level insights over junior-level checklists.**

**Include:**
- Philosophical foundations (the "why" behind practices)
- High-judgment principles experienced practitioners recognize
- Trade-offs, context-sensitivity, and when rules should be broken
- Distinctions less experienced practitioners miss
- Systems thinking, emergent behavior, second-order effects

**Avoid:**
- Basic syntax Claude knows from training
- Step-by-step tutorials on fundamental concepts
- Low-level implementation details unless they affect judgment
- Overly granular instructions that constrain rather than guide

**Exception—Safety constraints are valuable even for well-known content:**
Safety guardrails should be included even if Claude "knows" them. These constrain *toward* safety, not away from good behavior. Distinguish "teaching content" (condense) from "safety guardrails" (keep).
</content_depth>

### Directive Language

<directive_language>
**Skills are prompts. Directive intensity directly affects model behavior, and the effect is version-specific — calibrate against the models the skill targets.**

Current documented behavior by model class:

| Class | Documented behavior | Implication for skill prose |
|-------|---------------------|-----------------------------|
| Opus (documented for Opus 4.8) | Takes instructions at face value and applies them only to their stated scope; leans on reasoning before reaching for tools[^4] | State scope and thresholds explicitly — a vague bar like "only report important issues" is followed faithfully, suppressing output you wanted |
| Fable (documented for Fable 5) | A brief instruction steers most behaviors; heavy prescription carried over from older skills can hurt output[^5] | Prefer one condition-framed sentence over enumerating behaviors (see `<model_targeting>`) |

Rows are class defaults. When targeting a newer release, check the model-specific prompting pages rather than trusting parametric recall — class behavior has reversed between adjacent versions before.

Write skill content clearly and directly; assume a capable reader, and avoid all-caps or forceful intensifiers.[^3] More forceful writing does not increase the reader's understanding.

| Instead of | Write |
|------------|-------|
| "CRITICAL: You MUST..." | "Use [tool] when..." |
| "ALWAYS check..." | "Check [condition] before..." |
| "NEVER do X" | Describe the desired behavior instead |
| "If in doubt, use [tool]" | "Use [tool] when it would improve your understanding" |

**Prefer positive framing.** Tell the model what to do instead of what not to do: "Your response should be composed of smoothly flowing prose paragraphs" rather than "Do not use markdown in your response".[^3] Showing examples of the desired behavior tends to work better than prohibiting the undesired one.[^4] This applies at every level of skill content — from high-level behavioral guidance to specific output formatting instructions.

**Include 3-5 few-shot examples** when a skill needs to demonstrate output format, tone, or reasoning patterns.[^3] Wrap them in `<examples><example>...</example></examples>` tags. Choose diverse examples that cover edge cases; quality and variety matter more than quantity. This recommendation currently applies across tiers, Haiku included (see `references/prompting-haiku.md`).

This connects to the "retrieval trigger" philosophy in `<skill_scope>`: if skills activate existing knowledge, aggressive directives are counterproductive. They constrain behavior rather than activating capability. The right prompt intensity is the minimum needed to reliably activate the desired behavior.
</directive_language>

### Literal Language

<literal_language>
**Write skill instructions so that interpreting them correctly does not require knowledge that may be unavailable when the skill is read. Avoid figurative language (for example, metaphor, idiom, or analogy used as instruction) and evaluative language (for example, "elegant", "powerful", or a vague quality term such as "important"), and state conditions, thresholds, and actions directly; on vague quality terms see `<directive_language>`.**

Assume the context available while you author a skill will not be available when it is read (see `<skill_anatomy>` on progressive disclosure, and `<instructional_formulation>` on phrasing this as a directive). Figurative and evaluative language depends on that absent context: a metaphor needs the authoring discussion to interpret, and a term such as "the right approach" needs a shared standard the reader does not have. State conditions and actions literally so the text remains clear without that context.

The rule targets a vague quality term that the reader must apply as a criterion to decide what to do; there, an undefined bar produces miscalibrated behavior (see `<directive_language>` on stating thresholds explicitly). It does not target a quality term that marks a default tendency for the reader to weigh in context, provided you hedge it and supply the concrete basis for the judgment. The hedge signals a default rather than a rule, and the concrete basis carries the decision, so the reader judges from the basis, not from the vague word. For example, "usually useful as a persistent teammate: it retains its context across idle periods, so it can handle follow-ups" is acceptable; "usually" marks the default and the reason after the colon does the work. "Use the most useful agent for the job" is not; "useful" is the criterion and nothing grounds it. Reach for a qualified quality term deliberately, to invite judgment — not as a substitute for a criterion you could state concretely.

Terms of art are acceptable, and often useful, when the term is explained where it is first used or when its meaning matches the ordinary meaning of the word. A term that needs special knowledge to interpret, and that the skill does not supply, has the same defect as a metaphor; define it on first use or replace it. However, don't avoid introducing terms of art when knowing them is necessary for effective use of the knowledge in the skill.

Mark every example and reformulation explicitly, including example tables and sets, so they are not read as a closed or complete specification (see `<open_world_framing>`). The following table gives examples of the substitution; it is not a complete list:

| Figurative or evaluative (avoid) | Literal (prefer) |
|----------------------------------|------------------|
| "This step is a pre-flight check." | "This step verifies preconditions before proceeding." |
| "Spin up an elegant, powerful research team." | "Spawn a research team when [stated condition] holds." |
| "The task list is the team's coordination substrate." | "Teammates coordinate through the shared task list." |

This rule governs the skill's instruction text, not user-facing output the skill produces (for example, a report for a human audience), where figurative or evaluative language may be appropriate.
</literal_language>

### Instructional Formulation

<instructional_formulation>
**When a statement's purpose is to drive behavior, cast it as an instruction the reader can act on. A fact stated as a bare description, with its intended action left implicit, may not produce that action; state the action, or the assumption to adopt, directly.**

The reader of a skill is a model executing it. "A skill loads into a fresh context window" leaves implicit what to do about it; "Assume the context available while you write the skill will not be available when it is read" states the action. The following table gives more examples; it is not a complete list:

| Bare description (action left implicit) | Instructional (prefer) |
|------------------------------------|------------------------|
| "A skill loads into a fresh context window without the context that produced it." | "Assume the context available while you write the skill will not be available when it is read." |
| "Specialists go idle between turns." | "Expect specialists to be idle between turns; do not treat idleness as a failure." |
| "The task list records ownership and status." | "Record ownership and status on the task list as work is claimed and completed." |

This targets bare description, not the descriptive content a judgment framework needs. A decision table, a trade-off analysis, or a "when to use what" comparison is itself an instruction: it tells the model how to judge, and the model needs the stated criteria and context to do so. Keep that content (see `<decision_frameworks>` and `<content_depth>`); do not reduce it to imperatives. A principle is well cast as an assumption the model adopts rather than an imperative — for example, `decision-analysis`'s "treat stated option value as hypothetical until grounded in the situation" is descriptive in subject but instructional in effect, and the model reasons from it. State the criteria, invoke them with an action ("assign a value using this table"), and keep the rationale that lets the model generalize.

This complements `<directive_language>` (how forcefully to phrase a directive) and `<literal_language>` (keeping the directive plain); this guideline is about whether a statement that should drive behavior is phrased to do so.
</instructional_formulation>

### Model Targeting

<model_targeting>
**Author for Opus as the baseline; treat Fable as an upgrade path, not a dependency.**

This section synthesizes and paraphrases Anthropic's model-specific prompting pages.[^4][^5] Fable's safety classifiers can return a `refusal` stop reason with automatic fallback to Opus 4.8,[^5] and this skill assumes Fable access can't be banked on while it's new (an authoring assumption, not a documented limit). A skill that behaves well only on Fable therefore has no guaranteed runtime. Write skills that are correct on Opus; Fable's stronger instruction-following then needs less of the skill's prose, not different prose.

Cautions for skills that may run on Fable-class models:
- Ask for work products (e.g., findings, analysis, recommendations), not a transcript of reasoning. Instructions that have the model restate its internal reasoning as response text can trigger the `reasoning_extraction` refusal category and force fallback; applications needing reasoning visibility should read structured thinking output from the API instead.[^5]
- Trim prescription. Skills inherited from earlier models tend to over-specify for Fable, which can hurt output quality; re-test with instructions removed before assuming they're needed.[^5]
- For task skills that orchestrate agents (see `<content_patterns>`), state the conditions under which delegation is appropriate — Fable reaches for parallel subagents more readily than earlier models did.[^5]

In skills you author, do the same: model classes in guidance, version numbers in evidence (citations, provenance notes, dated status facts).

Skills targeting Sonnet or Haiku (e.g., as subagent workers in multi-tier systems) follow the same general principles; tier-specific calibration lives in `references/prompting-sonnet.md` and `references/prompting-haiku.md`. Anthropic currently publishes model-specific prompting pages only for its top tiers (currently, Fable 5 and Opus 4.8); Sonnet and Haiku guidance comes from the general best-practices page and migration guides, which those references synthesize.
</model_targeting>

### Guidance vs. Invariants

<guidance_vs_invariants>
**A directive is guidance the model can decline to follow. If a behavior must hold, route it to a mechanism, not a sentence.**

Skill content shapes probability, not control flow. Phrasing a requirement more forcefully (e.g., "CRITICAL", "NEVER", "NO EXCEPTIONS") may raise the odds of compliance; it does not guarantee it, and on some tiers it backfires (see `<directive_language>`). So before writing a requirement, classify it:

| Kind | Definition | How to encode it |
|------|------------|------------------|
| Guidance | The model should usually do X; an occasional miss is tolerable | A calm, positively-framed directive |
| Invariant | X must hold for the skill to be correct or safe; a single miss is a defect | A deterministic gate the skill runs (e.g., a script, validator, test, or hook), with the directive as a backstop rather than the sole guard |

**Treat escalating directive intensity as a design smell — a surface symptom of a deeper problem.** The urge to write "you MUST never mark this done unless tests pass" is a signal that the requirement is an invariant the prose cannot enforce; the fix is a gate (for example, run the tests and read the result), not more forceful wording. A model can narrate that it followed an unenforceable rule while not having followed it — only a mechanism observes the actual state.

This skill's own `<pii_and_secret_scanning>` applies this: it wires the scan "into the same validation gate ... enforced rather than remembered." Generalize it — when a skill defines work that must happen (e.g., a precondition, a format, a check), prefer wiring it into a gate the skill executes over trusting the model to remember.

When the invariant is "the code does what the spec says," the gate is a test; see `opinionated-software-engineering:test-driven-development` (tests as contracts). For the broader principle of pushing correctness into mechanisms rather than convention, see `opinionated-software-engineering:software-engineer`.

This section covers *when* to reach for a gate and *what kind* to reach for; it does not yet cover *how to build one*. Concrete implementation patterns — wiring a hook, structuring a validator script, embedding a test the skill runs — are an open area not yet developed here.
</guidance_vs_invariants>

### Open-World Framing

<open_world_framing>
**Write skill instructions for an open world. The domains skills describe — tools, APIs, options, the model's own capabilities, among others — keep changing, and any one skill sees only part of them.**

A list that reads as complete becomes wrong the moment the world adds a case it didn't enumerate, and it can suppress the model's trained knowledge of cases the list omits (the opposite of the retrieval-trigger goal in `<skill_scope>`). Default to phrasing that stays true as the world changes and as present unknowns surface.

Practices:
- Mark example lists as non-exhaustive: "e.g.,", "for example", "such as", "including but not limited to". Reserve "i.e.," for restating the same thing a different way, not for examples — the two carry different meanings.
- Hedge claims that ride a moving target: "currently", "as of <date>", "tends to", "in most cases". Date-stamp facts that will age.
- Prefer describing the condition over closing the set — "use a feature flag when shipping incomplete work" rather than "always use a feature flag" (this reinforces the positive framing in `<directive_language>`).
- Lead parenthetical example lists with a marker like "e.g.," or "for example,". A bare parenthetical such as "(JSON, YAML, TOML)" reads as the complete set or an "i.e.," restatement; writing it as "(for example, JSON, YAML, TOML)" marks it as open.
- Apply the same marking to example tables and multi-row example sets, not only inline lists. Introduce them with a phrase such as "The following are examples, not a complete list." An unmarked example table can be read as a closed specification of the only acceptable cases.
- Mark reformulations as reformulations, with "that is", "i.e.,", or "in other words". An unmarked restatement can be read as a separate, independent claim rather than a different wording of the prior one.

Closure is sometimes right, and over-hedging is its own failure mode. Assert plainly when the set is genuinely finite and the skill defines it (e.g., an enum the skill itself specifies), when an invariant truly holds, or for safety constraints, where closing *toward* safety is intentional (see `<content_depth>`). The skill is the discriminator: hedge where you describe an open domain, assert where you define a closed one.

| Closed-world phrasing | Open-world rewrite |
|-----------------------|--------------------|
| "The three valid options are X, Y, Z." (when more may arise) | "Options such as X, Y, and Z." |
| "This is the list of supported platforms." | "Supported platforms include …; check current docs for additions." |
| "X always causes Y." | "X usually causes Y; the outcome can depend on <factors>." |
</open_world_framing>

### Decision Frameworks

<decision_frameworks>
**Focus on WHEN/WHY, not WHAT/HOW.**

Skills should help identify when to use patterns, not teach how to write basic syntax. Include:
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

A skill that runs its full process on every invocation adds friction to the small cases it never needed to touch. Where a skill carries real overhead (for example, multi-step workflows, heavy upfront planning, or multi-agent orchestration), state the conditions under which a lighter alternative — a simpler sibling skill, the model's native capabilities, or doing the task directly — is the better choice. This extends `<when_to_use>`'s "do not use for" from a fixed boundary into in-flight judgment: not only when not to start, but when to stop partway. Scope the effort to the task; the goal is the result, not completing the full process for its own sake.
</proportional_engagement>

### Common Mistakes Sections

<common_mistakes_guidelines>
**Every skill should include common mistakes organized by background.**

Structure mistakes by where practitioners are coming from:
- `<from_java>` - Mistakes Java programmers make
- `<from_python>` - Mistakes Python programmers make
- `<from_bash>` - Mistakes bash users make
- `<general_anti_patterns>` - Universal mistakes

**Why background matters:** Different backgrounds create different blind spots. A Java programmer learning Clojure makes different mistakes than a Python programmer learning Clojure.

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

### Cross-References

<cross_reference_guidelines>
**Reference authoritative skills; briefly restate the principles essential to this skill's domain.**

**Strategy:**
1. **Primary reference**: Point to authoritative skill for detailed guidance
   - For example, "See `opinionated-software-engineering:test-driven-development` skill for general testing philosophy"
2. **Insurance duplication**: Restate essential principles briefly (1-2 sentences)
   - Core philosophy can be restated in case referenced skill not loaded
   - Safety-relevant "avoid X" rules worth repeating
3. **Balance**: Enough context to work standalone, not so much that skills become redundant

**When to reference vs. duplicate:**
- Reference when: Detailed guidance, examples, multiple subsections
- Brief restatement when: Core principle is critical to this skill's domain
- Full duplication when: Never (indicates architectural problem)

**Example:**
```markdown
## Testing

**For general testing philosophy, see the `opinionated-software-engineering:test-driven-development` skill.**
Core principle (restated): Tests are contracts—fix implementation, not tests.

This section covers language-specific practices...
```
</cross_reference_guidelines>

### Resources Section

<resources_guidelines>
**Resources serve two purposes: pointing Claude to content it can read at runtime, and naming works that activate trained knowledge.** Both are valuable; distinguish them clearly.

**Fetchable resources** — Claude can read these at runtime:
- Written documentation (e.g., HTML, Markdown, PDF)
- API references and generated docs
- GitHub repositories (especially with .md files)
- Local file paths (e.g., Xcode docs, language references)
- Style guides and written tutorials

**Training-data resources** — Claude can't fetch these, but naming them activates parametric knowledge of their content. This aligns with the retrieval-trigger philosophy in `<skill_scope>`: a book title in a Resources section is a retrieval trigger, not a URL to fetch. Include seminal books, classic papers, and foundational works when Claude's training plausibly covers them. Mark these clearly so users understand Claude is drawing on trained knowledge, not a retrieved source.

**Never include:**
- Video resources (WWDC, YouTube, etc.) — Claude cannot watch videos
- Paywalled or recent content that is neither fetchable nor likely in training data
- Resources requiring authentication
- Quotes or paraphrases from content that don't explicitly allow reuse or wouldn't clearly be fair-use

**Local documentation is especially valuable:**
- Can be read without network calls
- Available in air-gapped environments
- Often more stable than web URLs
- Usually faster to access

**Format:**
```markdown
## Resources

<resources>
**Official:**
- [Language Documentation](https://docs.example.com/)
- [Style Guide](https://github.com/example/style-guide)

**Local:**
- `/path/to/local/docs/`
- Man pages: `/usr/share/man/man1/tool*.1`

**Foundational (training-data):**
- Author. Year. *Title*. Publisher. — Brief note on why this activates relevant knowledge
</resources>
```
</resources_guidelines>

### Description Field Optimization

<description_optimization>
**The description field determines whether Claude invokes the skill.**

The `description` in YAML frontmatter determines when Claude invokes the skill. Include:
- WHAT the skill does
- WHEN Claude should use it
- Trigger terminology users would mention

**Good example:**
```yaml
description: Fish shell scripting judgment frameworks and critical idioms. Use when writing Fish scripts or shell automation. Focuses on when to use Fish vs bash, macOS/Fedora compatibility requirements, and Fish-specific patterns that prevent bugs.
```

**Bad example:**
```yaml
description: Fish shell scripting.
```

**Max length:** 1024 characters per description; `name` is capped at 64.[^7] There's also a collective budget: in Claude Code, the listing text per skill (combined `description` and `when_to_use`) is truncated at 1,536 characters, and all listings share a budget defaulting to 1% of the model's context window (raisable via the `skillListingBudgetFraction` setting or the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable).[^6] On overflow, skill names stay listed but the descriptions of least-invoked skills are shortened or dropped first — stripping the keywords discovery depends on. Concise descriptions aren't just good practice — they're a shared resource. A verbose 900-character description crowds out other skills' discovery text.
</description_optimization>

### Content Assessment

<content_assessment>
**Assess what Claude knows vs. what needs detail.**

| Knowledge State | Treatment |
|-----------------|-----------|
| Well-known from training | Condense to principles and frameworks |
| After training cutoff | Include detail, examples, patterns |
| Known problem area | Justify expanded coverage |

**Example assessment (Swift skill):**
- Swift 6 concurrency (~470 lines): After cutoff, known problem → detailed coverage justified
- Protocol syntax (~30 lines): Known well → condensed to judgment framework
- Basic value types (~20 lines): Known well → brief guidance only

**Target lengths:**
- Comprehensive language skill: ~400-700 lines
- Process/standard skill: ~150-300 lines
- If exceeding 1000 lines, reconsider what can be condensed
</content_assessment>

### Prose on Upgrade

<prose_on_upgrade>
**When asked to upgrade or update a skill, improve its prose opportunistically, but do not change what it means.** An upgrade is often prompted by a new model generation, and it is an occasion to make the existing guidance communicate more clearly: tighten wording, replace figurative or evaluative language with literal phrasing (see `<literal_language>`), mark examples (see `<open_world_framing>`), and remove content that does not help the reader act. Keep the skill's intent and substantive content fixed; change how it reads, not what it instructs.

Prune carefully. A skill or agent is usually built gradually — adjustments accumulate during and after repeated use, and a clause that looks redundant often encodes a distinction someone added to fix a real failure, so removing it can reintroduce that failure. Cut content that carries no information (for example, filler, bare restatement, or empty preamble), and preserve content that carries nuance even when it looks verbose (for example, edge cases, conditions, exceptions, and the rationale a reader needs to generalize). When unsure whether a passage is filler or nuance the skill needs, keep it or ask rather than cut it. Over-cutting is a regression, not a cleanup. For the staged procedure, see `references/retrofitting-existing-skills.md`.
</prose_on_upgrade>
</quality_guidelines>

## Research Phase

<research_phase>
**Use agents to research skill content before writing.**

### When to Research

Research is warranted when:
- Creating a skill for a domain you're not expert in
- Covering content after training cutoff
- Including tool/library documentation that may have changed
- Wanting to cite authoritative sources

### Research Process

<research_process>
1. **Scope the research**: Define specific questions the skill must answer
2. **Delegate to a research agent**: Use `subagent_type='opinionated-research:research-investigator'` for methodical evidence-gathering (the typical case for skill research, where you want sources you can cite) or `subagent_type='opinionated-research:research-analyst'` when the skill design itself requires cross-source synthesis judgments
3. **Specify output requirements**: Request structured findings with URLs for citation
4. **Synthesize results**: Integrate research into skill content with proper citations

**Example research prompt:**
```
Research the current best practices for [topic]. Specifically:
1. What are the official documentation sources?
2. What tooling is recommended by the community?
3. What are common mistakes practitioners make?
4. What has changed since [date]?

Return findings with URLs for each source so I can create proper citations.
```
</research_process>

### Research Agent Configuration

For skill research, the `opinionated-research:research-investigator` agent is the usual fit (methodical, evidence-trail, citations per claim):
- **Tools available**: WebSearch, WebFetch, Exa (web + code), Kagi (private search + summarizer), AWS documentation MCP servers
- **Privacy note**: Use Kagi for sensitive topics; Exa does not keep queries confidential for non-enterprise customers
- **Output format**: Structured report with inline `[CITED]`/`[TRAINING DATA]`/etc. provenance labels and ACM-format citations per `[CITED]` claim
</research_phase>

## Citation Requirements

<citation_requirements>
**All third-party content must be attributed. Use formal ACM citations when the source adds value.**

### What Requires Attribution

<citation_scope>
**Distinguish attribution from formal citation:**
- **Attribution**: Acknowledging the source (always required for third-party content)
- **Formal ACM citation**: Full bibliographic reference with footnote (sometimes required)

**Must attribute:**
- Direct quotes from any source
- Specific claims attributed to sources
- Statistics, benchmarks, or empirical findings
- Code patterns adapted from specific sources
- Well-known concepts with identifiable originators

**Informal attribution is sufficient for:**
- Short quotes (single sentences) — use `"quote" — Author, Source Work`
- Well-known aphorisms where author is the key information
- Cases where the source work is widely known (e.g., SICP, "Simple Made Easy")

**Formal ACM citations are warranted when:**
- The source would be useful for Claude to look up (e.g., URLs, documentation)
- Fair-use concerns exist (substantial portions, not just short quotes)
- Content substantially paraphrases a source (cite the source being paraphrased)
- Statistics or empirical claims need verification
- Code or patterns are adapted from a specific source

**Does not require attribution:**
- General programming knowledge without an identifiable originator (e.g., "functions should do one thing")
- Claude's own analysis and synthesis
- Content the skill author created

**Judgment call:** When in doubt, attribute. Formal citation when the source adds value.
</citation_scope>

### Formal Citation Format

<citation_format>
**When formal citations are warranted, use ACM style with Markdown footnote syntax.**

**In-text citation:** Use Markdown footnote references: `[^1]`, `[^2]`

**Reference list format:**
```markdown
## Sources

<sources>
[^1]: Author Name. Year. Title. Publication venue. URL or DOI

[^2]: Organization. Year. Document Title. Retrieved [Date] from URL
</sources>
```

**Example citations:**
```markdown
Rich Hickey's "Simple Made Easy" talk[^1] distinguishes simplicity from ease...

## Sources

<sources>
[^1]: Rich Hickey. 2011. Simple Made Easy. Strange Loop Conference. Retrieved November 24, 2025 from https://www.infoq.com/presentations/Simple-Made-Easy/

[^2]: ACM. 2023. Reference Formatting. Retrieved November 24, 2025 from https://www.acm.org/publications/authors/reference-formatting
</sources>
```

**Why Markdown footnotes:** Footnote syntax (`[^1]`) renders properly in Markdown viewers, creates clickable links to sources, and distinguishes citations from array indexing or other bracket uses in technical content.
</citation_format>

### Citation Accuracy

<citation_accuracy>
**Never fabricate bibliographic details.**

- Verify DOIs resolve correctly before including
- Use actual access dates, not invented dates (when adding citations retroactively, use the date content was originally retrieved, not the current date)
- If uncertain about any field, omit it rather than guess
- Mark uncertain information as `[unverified]`
- Prefer incomplete but accurate over complete but fabricated
</citation_accuracy>

### Source Verification

<source_verification>
**Training data is not verification. Use tools to confirm sources before citing.**

Memories from training are hypotheses, not facts. Before adding any citation:

1. **Verify URLs exist** — Fetch the URL to confirm it resolves and contains relevant content
2. **Verify quotes are accurate** — Search for the exact quote; paraphrased memories often drift from originals
3. **Verify attributions** — Confirm who actually said something; community interpretations often get misattributed to authoritative sources (e.g., "Apple says..." when it's actually a blog post)
4. **Verify content matches claim** — Read the source to confirm it supports what you're citing it for

**When verification tools are available (e.g., WebFetch, WebSearch, Kagi, Exa), use them.** The cost of a few tool calls is trivial compared to publishing incorrect citations.

**Common verification failures:**
- Attributing secondary interpretations to primary sources (e.g., a blogger's synthesis cited as official documentation)
- URLs constructed from memory that return 404 or redirect elsewhere
- Quotes that are paraphrases or composites of what was actually said
- Version-specific claims stated as fact without verification

**Verification workflow:**
1. Draft citations based on memory
2. Before finalizing, verify each citation with appropriate tools
3. Correct or remove citations that don't verify
4. Note in commit message that sources were verified
</source_verification>

### Common Citation Mistakes

<citation_mistakes>
**Lessons learned from skill validation:**

- **"Unknown" attributions** — Verify before accepting. Quotes attributed to "Unknown" often have identifiable sources (e.g., "Time is a device..." is Ray Cummings, 1922)
- **Incomplete quotes without ellipses** — If quoting a sentence fragment, end with `...` to indicate incompleteness
- **Unsourced statistics** — Specific numbers (e.g., "58% adoption", "100x slower") require sources. If no source exists, either find one, remove the claim, or qualify it (e.g., "significant performance issues" instead of "100x slower")
- **Informal documentation references** — "From the X documentation" is insufficient. Cite formally: `[^1]: Author. Title. URL`
- **Paraphrased official guidance without disclosure** — If a skill substantially paraphrases official documentation (like style guides), add upfront disclosure: "This skill synthesizes and paraphrases the official X guidelines."
- **Assuming well-known means no attribution needed** — Named concepts (e.g., Liskov Substitution Principle, Test Pyramid) should acknowledge their originators. Informal attribution is fine when the name itself attributes (e.g., "Liskov Substitution Principle" names Liskov); formal citation when the source would be useful to look up.
</citation_mistakes>
</citation_requirements>

## Validation Phase

<validation_phase>
**Validate skill content before finalizing.**

### Content Validation Checklist

<content_validation>
Before completing a skill, verify:

**Structure:**
- [ ] YAML frontmatter has `name` and `description`
- [ ] Description includes WHAT and WHEN (max 1024 chars)
- [ ] Opens with `<skill_scope skill="skill-name">` containing related skills
- [ ] Major sections use XML tags with `snake_case` names
- [ ] Cross-references point to correct skill names

**Content Quality:**
- [ ] Focuses on judgment frameworks, not basic mechanics
- [ ] Includes decision tables for context-dependent guidance
- [ ] Has common mistakes section organized by background
- [ ] Safety constraints are explicitly stated
- [ ] Directive language uses calm, direct framing (see `<directive_language>`)
- [ ] Instruction prose is literal: figurative and evaluative language avoided; terms of art explained or self-evident (see `<literal_language>`)
- [ ] Statements are cast as instructions or assumptions, not bare descriptions (see `<instructional_formulation>`)
- [ ] No instructions to reproduce internal reasoning as response text (Fable-class refusal hazard; see `<model_targeting>`)
- [ ] Invariants routed to a deterministic gate, not left as directives (see `<guidance_vs_invariants>`)
- [ ] Skills with real overhead name a lighter alternative and when to use it (see `<proportional_engagement>`)
- [ ] Open-world framing: example lists marked non-exhaustive; closed-world claims only where closure is guaranteed (see `<open_world_framing>`)
- [ ] Resources are machine-readable (no videos)

**Attribution and Citations:**
- [ ] All third-party content is attributed (author + source work)
- [ ] Formal ACM citations used where warranted (see `<citation_scope>`)
- [ ] Sources verified with tools, not just memory (see `<source_verification>`)
- [ ] URLs fetched to confirm they exist and contain claimed content
- [ ] Quotes verified against original source (not paraphrased from memory)
- [ ] Attributions confirmed (e.g., "Apple says" actually comes from Apple)
- [ ] Sources section uses proper format
- [ ] No probable plagiarism
- [ ] Incomplete quotes end with ellipses
- [ ] No "Unknown" attributions (verify or remove)
- [ ] Quantitative claims have sources (or are qualified)
- [ ] Substantial paraphrasing cites the source

**Consistency:**
- [ ] No conflicts with related skills
- [ ] Cross-references align with target skill content
- [ ] Terminology is consistent throughout
- [ ] For skills used together: shared vocabulary, paths, and artifact schema agree (see `<composition_contracts>`)

**Publication Safety:**
- [ ] No PII or secrets in any tracked (publishable) file — see `<pii_and_secret_scanning>`
- [ ] Read the whole publish surface in full, not just pattern-scanned it (see `<pii_and_secret_scanning>`)
- [ ] Checked examples for real-scenario context leaks, not only data-value patterns
</content_validation>

### Empirical Validation

<empirical_validation>
**Skills are iteratively refined based on actual usage.** Walk the user through the process of validating a skill.

After creating a skill:
1. Test in a clean context window
2. Observe whether the skill triggers appropriately
3. Note where Claude struggles or over-constrains
4. Refine based on observations

**Evaluation questions:**
- Does the skill trigger when expected?
- Does Claude apply the guidance correctly?
- Are there gaps where Claude lacks needed information?
- Are there constraints that hurt more than help?
- Does the skill behave consistently across the model versions it targets (primarily Opus and Fable; see `<model_targeting>`)? A directive calibrated for one version may overtrigger, be followed too literally, or underperform on another (see `<directive_language>`).
</empirical_validation>

### Plagiarism and Citation Validation

<plagiarism_validation>
**For skills intended for publication, run systematic plagiarism checks.**

**Parallel agent validation:** Launch multiple agents simultaneously to check each skill file. Each agent should:
1. Read the skill file
2. Identify passages that sound copied (e.g., unusual phrasing, tone shifts)
3. Flag quotes or claims lacking citations
4. Check for specific statistics or unique phrases without sources
5. Report assessment: clean / needs-review / likely-plagiarized

**Example prompt for validation agent:**
```
Read [skill file] and check for potential plagiarism. Look for:
1. Text that sounds copied from external sources
2. Quotes or specific claims lacking citations
3. Statistics or unique phrases without sources
Report: File path, suspicious passages with line numbers, assessment.
```

**Post-validation:** Address all flagged issues before publication. Even "clean" files may have minor citation improvements identified.
</plagiarism_validation>

### PII and Secret Scanning

<pii_and_secret_scanning>
**Before publishing, review the whole publishable surface — every tracked file, not just the `SKILL.md` you edited — for personal data, secrets, and real-scenario context leaks. Read each file in full; a pattern scan alone is not enough.**

Skills get published in places such as GitHub releases, marketplaces, and shared ZIPs. What goes public is every tracked file — for example, skill bodies, agents, README, manifests, example snippets, and bundled resources — so review the whole tracked tree, not the single file you touched. Untracked files headed for a later commit count too; review them before they land.

Common leak vectors and how to tell signal from noise. The patterns below are examples to seed the scan, not a closed checklist — add others your content invites (e.g., physical addresses, OAuth client secrets, license keys):

| Vector | Example pattern | Usually benign when… |
|--------|-----------------|----------------------|
| Email addresses | `name@domain.tld` | Placeholder (`your@email.com`) or example domain (`example.com`, `test.`) |
| Home-path username leaks | `/Users/<name>`, `/home/<name>`, `C:\Users\<name>` | Generic placeholder (`/Users/you`, `$HOME`) |
| Credentials | API keys, bearer tokens, `AKIA…`, `-----BEGIN … PRIVATE KEY`, `ghp_…` | Treat every real-looking match as live until proven otherwise |
| Personal identifiers | Author's real name, phone, SSN | Citing a public figure's published work (attribution, not exposure) |
| Internal references | Private hostnames, internal URLs, ticket IDs | Public docs or documented example hosts |
| Context leaks in examples | An example or passage carrying detail from a real scenario, such as a real client, employer, project, person, system, or incident | The example is generic or invented (for example, a placeholder, a public technology, or a hypothetical) |

Most hits are false positives, so judge each one: a placeholder email and a citation to a public author are clean; a stray `/Users/yourname` path or a real-looking token are not. When a match is genuinely a secret, rotate it — removing it from the working tree doesn't remove it from history.

Read every tracked file end to end; pattern matching alone is not enough. A context leak — an example or passage carrying real-scenario detail without any flaggable token (the last vector above) — matches no pattern and surfaces only on a read. A pattern scan can also silently match nothing when a path or pathspec is wrong, so a clean scan is not evidence of a clean surface until you have read the files too. So run both: read each file in full, and run a pattern scan (e.g., `git grep -nIE` for the vectors above) plus, for secrets, an entropy-based scanner (e.g., gitleaks, trufflehog) for the high-entropy strings patterns miss. Wire the scanners into the same validation gate as the other automated checks so they run every time; the full read is a manual step the reviewer owns, and a clean scan does not excuse skipping it.
</pii_and_secret_scanning>

### Related Skill Consistency

<consistency_validation>
When creating or updating a skill, check for conflicts with related skills, and for contract drift among skills used together:

1. **Identify related skills** — those with similar guidance, and any used together with this one
2. **Read full sections**, not just grep for keywords (conflicts may be conceptual)
3. **Check for principle conflicts** (conceptual contradictions); and, for skills used together, for interface-contract drift — divergent terminology, paths, or artifact shapes (see `<composition_contracts>`)
4. **Update all affected skills** in the same change when refining a principle or revising either side of a shared contract
</consistency_validation>
</validation_phase>

## Skill Creation Process

<creation_process>
Follow this process in order, skipping steps only with clear justification.

### Step 1: Understand the Skill Purpose

<step_understand>
**Goal:** Clearly define what the skill does and when it should be used.

**Activities:**
1. Identify concrete examples of how the skill will be used
2. Determine what triggers should invoke this skill
3. Clarify what related skills exist and how this differs
4. Establish the skill's scope boundaries

**Questions to answer:**
- What problem does this skill solve?
- What would a user say that should trigger this skill?
- What existing skills are related, and how does this differ?
- What is explicitly OUT of scope?

**Complete when:** Clear purpose statement and scope boundaries established.
</step_understand>

### Step 2: Research Content

<step_research>
**Goal:** Gather authoritative information for skill content.

**Activities:**
1. Identify what content requires research (vs. existing knowledge)
2. Use `opinionated-research:research-investigator` for unfamiliar domains (or `opinionated-research:research-analyst` when the skill design itself requires cross-source synthesis judgments)
3. Collect URLs and sources for citation
4. Document research findings for future reference

**Skip when:** Creating a skill for a domain you're already expert in, with no post-cutoff content.

**Complete when:** All necessary information gathered with source attribution.
</step_research>

### Step 3: Plan Skill Architecture

<step_plan>
**Goal:** Design the skill's structure and identify reusable components.

**Activities:**
1. Outline major sections with XML tag names
2. Identify what belongs in SKILL.md vs. references/
3. Determine if scripts or assets are needed
4. Plan cross-references to related skills

**Architectural questions:**
- What decision frameworks are needed?
- What common mistakes should be documented?
- Which safety constraints must the skill enforce?
- What content can Claude retrieve from training vs. needs explicit inclusion?

**Complete when:** Clear outline with section structure and resource allocation.
</step_plan>

### Step 4: Initialize the Skill

<step_initialize>
**Goal:** Create the skill directory structure.

**For new skills**, use the init script in Anthropic's `skill-creator:skill-creator` skill if available:
```bash
scripts/init_skill.py <skill_name> --path <output_directory>
```

**Manual initialization:**
```bash
mkdir -p skill-name/{scripts,references,assets}
touch skill-name/SKILL.md
```

**Skip when:** Iterating on an existing skill.

**Complete when:** Directory structure exists with SKILL.md template.
</step_initialize>

### Step 5: Write the Skill

<step_write>
**Goal:** Create the skill content following quality guidelines.

**Writing principles:**
- Use imperative/infinitive form ("To accomplish X, do Y")
- Apply XML tags to major sections
- Focus on judgment frameworks over mechanics
- Include decision tables for context-dependent guidance
- Organize common mistakes by background
- Add cross-references with brief principle restatement

**Order of writing:**
1. YAML frontmatter (name, description)
2. `<skill_scope skill="skill-name">` with related skills and purpose
3. When to use section
4. Core content sections with XML tags
5. Common mistakes section
6. Resources section
7. Sources section (citations)

**Complete when:** All content written with proper structure.
</step_write>

### Step 6: Validate the Skill

<step_validate>
**Goal:** Ensure skill meets quality standards.

**Activities:**
1. Run through content validation checklist
2. Verify all citations
3. Check for conflicts with related skills
4. Test in clean context window if possible

**Complete when:** All validation checks pass.
</step_validate>

### Step 7: Iterate Based on Usage

<step_iterate>
**Goal:** Refine skill based on actual performance.

**Iteration triggers:**
- Skill doesn't trigger when expected
- Claude applies guidance incorrectly
- Gaps where Claude lacks information
- Over-constraints that hurt performance

**Iteration process:**
1. Observe skill in use
2. Identify specific problems
3. Determine root cause (content, structure, or description)
4. Make targeted changes
5. Re-validate

**Note:** Skill refinement is ongoing. Document observations for future improvements.
</step_iterate>
</creation_process>

## Skill Tiers and Relationships

<skill_tiers>
**Skills exist in a hierarchy with fallback behavior.**

| Tier | Purpose | Example |
|------|---------|---------|
| Meta-skill | Universal principles | `opinionated-software-engineering:software-engineer` |
| Paradigm skills | Fallback for language families | `functional-programmer`, `object-oriented-programmer` |
| Language skills | Specific language guidance | `java-programmer`, `clojure-programmer` |
| Process skills | Situation-specific | `opinionated-software-engineering:test-driven-development`, `opinionated-software-engineering:git-version-control` |

**Invocation behavior:**
- Language-specific skills supersede paradigm skills (no redundant loading)
- Meta-skill (`opinionated-software-engineering:software-engineer`) invoked for all coding tasks
- Process skills invoked based on activity (testing, committing, etc.)

**Content placement:**
- System-level patterns (hexagonal architecture) → `opinionated-software-engineering:software-engineer`
- Paradigm-specific patterns (FP composition) → paradigm skills
- Language-specific syntax/tooling → language skills
- Universal processes (e.g., TDD, Git) → process skills
</skill_tiers>

## Anti-Patterns

<anti_patterns>
**Patterns that reduce skill effectiveness:**

### Content Anti-Patterns

- **Teaching basics**: Explaining concepts (e.g., map/filter/reduce) when Claude knows them from training
- **Aggressive directives**: Using "CRITICAL", "MUST", "ALWAYS" to force behaviors is counterproductive on Opus and Fable, which follow calm instructions precisely (see `<directive_language>`)
- **Over-constraining**: So much detail that Claude can't apply judgment
- **Duplicate content**: Same information in multiple skills
- **Missing safety**: Not including critical guardrails because "Claude knows"

### Structure Anti-Patterns

- **No XML tags**: Unstructured content that's hard to navigate
- **Flat organization**: No hierarchy or progressive disclosure
- **Missing cross-references**: Island skills with no connection to ecosystem
- **Vague description**: Description that doesn't enable discovery

### Process Anti-Patterns

- **No research**: Creating skills for unfamiliar domains without investigation
- **No validation**: Shipping skills without verification
- **No iteration**: Treating skills as write-once artifacts
- **No citations**: Including third-party content without attribution
- **Memory as verification**: Treating training data memories as verified facts; citing URLs, quotes, or attributions without using tools to confirm accuracy
</anti_patterns>

## Resources

<resources>
**Official documentation:**
- Claude Code Skills: https://code.claude.com/docs/en/skills.md
- Claude Code Subagents: https://code.claude.com/docs/en/sub-agents.md
- Prompting Best Practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Prompting Claude Opus 4.8: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8
- Prompting Claude Fable 5: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
- Agent Skills Overview: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- Model Migration Guide: https://platform.claude.com/docs/en/about-claude/models/migration-guide
- XML Tagging Best Practices: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/use-xml-tags

**Bundled references:**
- `references/prompting-sonnet.md` - Sonnet-tier calibration for skill authors
- `references/prompting-haiku.md` - Haiku-tier calibration for skill authors
- `references/retrofitting-existing-skills.md` - Staged runbook for bringing existing skills up to these standards

**Related skills:**
- `opinionated-software-engineering:software-engineer` - Design principles informing skill architecture
</resources>

## Sources

<sources>
[^1]: Anthropic. 2025. Use XML tags to structure your prompts. Retrieved November 24, 2025 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/use-xml-tags.md

[^2]: Anthropic. 2025. Skills Documentation. Claude Code. Retrieved November 24, 2025 from https://code.claude.com/docs/en/skills.md

[^3]: Anthropic. 2026. Prompting best practices. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^4]: Anthropic. 2026. Prompting Claude Opus 4.8. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8

[^5]: Anthropic. 2026. Prompting Claude Fable 5. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

[^6]: Anthropic. 2026. Extend Claude with skills. Claude Code Documentation. Retrieved June 10, 2026 from https://code.claude.com/docs/en/skills.md

[^7]: Anthropic. 2026. Agent Skills. Claude API Documentation. Retrieved June 10, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
</sources>

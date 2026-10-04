# Creating a Skill

<creating_skills_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file. This file is a reference for the `expert-skill-creator` skill and extends its `SKILL.md`. A tag this file names but does not contain is in `SKILL.md` or in the file that `SKILL.md`'s `<reference_files>` table lists for it.

**Contents:**
- [Skill Creation Process](#skill-creation-process)
  - [Step 1: Understand the Skill Purpose](#step-1-understand-the-skill-purpose)
  - [Step 2: Research Content](#step-2-research-content)
  - [Step 3: Plan Skill Architecture](#step-3-plan-skill-architecture)
  - [Step 4: Initialize the Skill](#step-4-initialize-the-skill)
  - [Step 5: Write the Skill](#step-5-write-the-skill)
  - [Step 6: Validate the Skill](#step-6-validate-the-skill)
  - [Step 7: Iterate Based on Usage](#step-7-iterate-based-on-usage)
- [Research Phase](#research-phase)
  - [When to Research](#when-to-research)
  - [Research Process](#research-process)
  - [Research Agent Configuration](#research-agent-configuration)
</creating_skills_reference_scope>

## Skill Creation Process

<creation_process>
Follow these steps in order, skipping a step only when you can state why skipping it is justified (e.g., the step's **Skip when:** condition holds).

### Step 1: Understand the Skill Purpose

<step_understand>
**Goal:** Define what the skill does and when it should be used.

**Activities:**
1. Identify concrete examples of how the skill will be used
2. Determine what triggers should invoke this skill
3. Identify the related skills that exist and how this skill differs from them
4. Establish the skill's scope boundaries

**Questions to answer:**
- What problem does this skill solve?
- What would a user say that should trigger this skill?
- What existing skills are related, and how does this skill differ from them?
- What is explicitly out of scope?

**Complete when:** An unambiguous purpose statement and the scope boundaries are established.
</step_understand>

### Step 2: Research Content

<step_research>
**Goal:** Gather authoritative information for the skill's content.

**Activities:**
1. Identify what content requires research (as opposed to content covered by existing knowledge)
2. Use `opinionated-research:research-investigator` for unfamiliar domains (or `opinionated-research:research-analyst` when the skill design itself requires cross-source synthesis judgments)
3. Collect URLs and sources for citation
4. Document research findings for future reference

**Skip when:** Creating a skill for a domain you're already expert in, with no post-cutoff content.

**Complete when:** All the information the skill needs is gathered, with source attribution.
</step_research>

### Step 3: Plan Skill Architecture

<step_plan>
**Goal:** Design the skill's structure and identify reusable components.

**Activities:**
1. Outline the major sections with their XML tag names
2. Identify what belongs in `SKILL.md` and what belongs in `references/`
3. Determine whether scripts or assets are needed
4. Plan cross-references to related skills

**Architectural questions:**
- What decision frameworks are needed?
- What common mistakes should be documented?
- Which safety constraints must the skill enforce?
- What content can Claude retrieve from training, and what content needs explicit inclusion?

**Complete when:** An outline names each section and its XML tag, and allocates content among SKILL.md, `references/`, `scripts/`, and `assets/`.
</step_plan>

### Step 4: Initialize the Skill

<step_initialize>
**Goal:** Create the skill directory structure.

**For new skills**, use the init script in Anthropic's `skill-creator:skill-creator` skill if it is available:
```bash
scripts/init_skill.py <skill_name> --path <output_directory>
```

**Manual initialization:**
```bash
mkdir -p skill-name/{scripts,references,assets}
touch skill-name/SKILL.md
```

**Skip when:** Iterating on an existing skill.

**Complete when:** The directory structure exists, with a `SKILL.md` template.
</step_initialize>

### Step 5: Write the Skill

<step_write>
**Goal:** Write the skill content following the quality guidelines.

**Writing principles:**
- Use the imperative or infinitive form (e.g., "To accomplish X, do Y")
- Apply XML tags to major sections
- Focus on judgment frameworks over mechanics
- Include decision tables for context-dependent guidance
- Organize common mistakes by background
- Add cross-references that briefly restate the principle they point to

**Order of writing:**
1. YAML frontmatter (name, description)
2. `<skill_scope skill="skill-name">` with related skills and purpose
3. When-to-use section
4. Core content sections with XML tags
5. Common mistakes section
6. Recent changes section, when the subject changes with releases (see `<recent_changes_guidelines>`)
7. Resources section
8. Sources section (citations)

**Complete when:** All content is written, structured as the writing principles above describe, with sections in the order listed.
</step_write>

### Step 6: Validate the Skill

<step_validate>
**Goal:** Confirm that the skill meets the quality standards.

**Activities:**
1. Run through the content validation checklist
2. Verify all citations
3. Check for conflicts with related skills
4. Test in a clean context window if possible
5. Run one review agent per reference file of `expert-skill-creator` (see `<reference_conformance_review>`)

**Complete when:** All validation checks pass.
</step_validate>

### Step 7: Iterate Based on Usage

<step_iterate>
**Goal:** Refine the skill based on its actual performance.

**Iteration triggers:**
- The skill doesn't trigger when expected
- Claude applies guidance incorrectly
- Gaps where Claude lacks information
- Constraints that degrade performance

**Iteration process:**
1. Observe the skill in use
2. Identify specific problems
3. Determine the root cause (e.g., content, structure, or description)
4. Make targeted changes
5. Re-validate

**Note:** Skill refinement continues after release; record observations for future improvements.
</step_iterate>
</creation_process>

## Research Phase

<research_phase>
**Use agents to research skill content before writing it.**

### When to Research

<when_to_research>
Research is justified in these cases:
- Creating a skill for a domain you're not expert in
- Covering content from after the training cutoff
- Including tool or library documentation that may have changed
- Wanting to cite authoritative sources
</when_to_research>

### Research Process

<research_process>
1. **Scope the research**: Define the specific questions the skill must answer
2. **Delegate to a research agent**: Use `subagent_type='opinionated-research:research-investigator'` for methodical evidence-gathering (the usual case for skill research, where you want sources you can cite) or `subagent_type='opinionated-research:research-analyst'` when the skill design itself requires cross-source synthesis judgments
3. **Specify output requirements**: Request structured findings with URLs for citation
4. **Synthesize results**: Integrate the research into the skill content, with citations in the format `<citation_format>` gives

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

<research_agent_configuration>
For skill research, use the `opinionated-research:research-investigator` agent in most cases, because it is methodical, keeps an evidence trail, and cites each claim:
- **Tools available**: WebSearch, WebFetch, Exa (web + code), Kagi (private search + summarizer), AWS documentation MCP servers
- **Privacy note**: Use Kagi for sensitive topics; Exa does not keep queries confidential for non-enterprise customers
- **Output format**: A structured report with inline provenance labels (e.g., `[CITED]`, `[TRAINING DATA]`) and an ACM-format citation for each `[CITED]` claim
</research_agent_configuration>
</research_phase>

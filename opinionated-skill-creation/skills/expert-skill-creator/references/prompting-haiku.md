# Prompting Haiku-Line Models: Notes for Skill Authors

<haiku_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

This file records what Anthropic documents about how Haiku-line models respond to instructions, for authors of skills and agent prompts those models will run, most often as fast subagent workers. As of October 7, 2026, the current version is Claude Haiku 5.5 (`claude-haiku-5-5`), released that day.[^3] Its reliable knowledge cutoff is June 2026, the same as the other models in the models overview's comparison table.[^14] This file labels every finding with the version it was documented for.

Treat each finding as measured on the version it names, and re-check it before applying it to another model line. Where this file disagrees with the current documentation, the documentation is correct and this file is out of date. The current documentation for this line is Anthropic's page Prompting Claude Haiku 5.5 (https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5); for a later version, find its page in the "Model-specific guidance" table of Prompting best practices (https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices), which links the prompting page of each current model. When a new Haiku version ships, compare its prompting page against this file using the model-upgrade checklist in `references/retrofitting-existing-skills.md`.

**Contents:** role and comparisons; instruction following; scope, stopping, and verification; tools and search; thinking and effort; harness interactions; refusals; documentation gaps; retired claims; sources.
</haiku_reference_scope>

## Role and Comparisons

<haiku_role>
- **Intended role (Haiku 5.5).** Anthropic describes Haiku 5.5 as "built for high-volume, latency-sensitive work such as classification, routing, extraction, and subagent tasks",[^2] and as "best suited to more narrowly scoped tasks", naming compaction, summarization, and subagent work; "Sonnet 5.5 and Opus 5.5 remain better choices for complex agentic coding tasks".[^3]
- **Checkable outputs (Haiku 5.5).** On GPQA Diamond, Haiku 5.5 scored 85%, "compared with 91% for Opus 5.5 run the same way", and Anthropic concludes that "It suits high-volume and latency-sensitive work with checkable outputs."[^4]
- **Behavior audits (Haiku 5.5).** The system card places Haiku 5.5 on instruction-following failures "similar to or slightly worse than Claude Sonnet 5.5, and worse than Claude Opus 5.5", and reports that it "hallucinated more than other recent models"; Opus 5.5, Sonnet 5.5, and Mythos 5.1 "were all strictly better on input hallucination, important omissions, and false completion claims".[^5] For choosing a worker's model from these findings, see `references/choosing-worker-models.md`.
</haiku_role>

## Instruction Following

<haiku_instruction_following>
- **More guidance than the larger models need (Haiku line).** Anthropic's skill-authoring guide asks, for Haiku, "Does the Skill provide enough guidance?", and says "What works perfectly for Opus might need more detail for Haiku."[^6] When a skill will run on Haiku, test it there; where Haiku misses an instruction that Opus follows, make the instruction more explicit rather than adding a Haiku-only version.
- **Effort for strict instruction following (Haiku 5.5).** The prompting page recommends `high` effort for "strict instruction following", and for a chatbot that must keep to its system prompt: "When instruction following matters most, also use `high` effort."[^1] In a task skill or agent that runs on Haiku 5.5 and has constraints the worker must not drop, set `effort: high` in the frontmatter.
- **Few-shot examples (all models).** Anthropic's general recommendation is "Include 3–5 examples for best results", with no tier-specific variation.[^7]
</haiku_instruction_following>

## Scope, Stopping, and Verification

<haiku_scope_and_stopping>
- **Early stopping (Haiku 5.5).** "With a long coding-agent system prompt at `low` effort, it sometimes stops early and hands the task back to the user." In Anthropic's testing, moving from `low` to `medium` "roughly halved early stopping" and "more than doubled the output tokens for each attempt"; the page also supplies a paragraph that begins "Keep working until everything the user asked for is done", and whose second part rules out unrequested features, documentation, and refactoring.[^1] Run a task skill or agent whose prompt is long at `medium` effort or above on Haiku 5.5, or include that paragraph.
- **Reporting work done without checking it (Haiku 5.5).** "At `low` and `medium` effort, Claude Haiku 5.5 sometimes reports a code change as done without running a check." The page supplies a verification paragraph that begins "When you change code that can be run, built, or type-checked, run a real check that exercises the change before reporting it done".[^1] This concerns running an external check (e.g., tests or a build), which `<model_targeting>` in `SKILL.md` distinguishes from asking the model to check its own work; keep instructions to run an external check in skills that a Haiku 5.5 worker runs.
- **Following through on an investigation (Haiku 5.5, one independent benchmark).** On Plotly's 43-question data-analysis exam, Haiku 5.5 passed 37, but on three of five hidden patterns it "got partway but didn't follow through"; in one, "it listed the right cause as a hypothesis to test later, instead of testing it."[^8] When a Haiku worker's task includes testing a hypothesis, say so in the brief.
</haiku_scope_and_stopping>

## Tools and Search

<haiku_tools_and_search>
- **Search (Haiku 5.5).** Give a Haiku 5.5 worker that has a search tool the current date; the model "sometimes needs an extra nudge to search", especially at `low` effort or under a long system prompt, and the page supplies a paragraph that names the kinds of facts to search for. It warns against blanket instructions such as "search for any present-day factual question, regardless of how confident you are"; in Anthropic's testing, that instruction caused searches on half the prompts that needed none and did not improve accuracy.[^1] State which facts need a search as conditions, not as a blanket rule (see `<directive_language>` in `SKILL.md`).
- **Tool calls with JSON output (Haiku 5.5).** "With thinking off, Claude Haiku 5.5 might skip a tool call it needs when you also request JSON output with structured outputs."[^1] This concerns API callers that turn thinking off; Claude Code does not let thinking be turned off on Haiku 5.5.[^9]
</haiku_tools_and_search>

## Thinking and Effort

<haiku_thinking_and_effort>
- **Effort (Haiku 5.5).** Haiku 5.5 is "the first Haiku model with effort levels" and supports all five, with `medium` as the default in both the Claude API and Claude Code.[^1][^10] The effort page's recommendations: `low` for "chat, short tool tasks, and simple, high-volume requests"; `medium` "for most work, including agentic coding"; `high` "for knowledge work, longer agent tasks, and strict instruction following"; `xhigh` or `max` "only where your evals show a quality gain", compared against Sonnet 5.5.[^10] Set effort through the `effort` frontmatter field, not prose.
- **Prompts do not reduce thinking (Haiku 5.5).** "In Anthropic's testing, telling the model in the prompt to answer directly didn't stop it from thinking."[^1] Lower effort instead.
- **Empty replies at `xhigh` (Haiku 5.5).** "At `xhigh` effort in multi-turn chats, the model sometimes writes its whole answer in its thinking and ends the turn with no visible text."[^1]
- **Reasoning in user-facing text (Haiku 5.5).** "Claude Haiku 5.5 sometimes writes reasoning-like text in the reply that users see", especially at `low` effort or with thinking off; the page's fix is adaptive thinking at `medium`.[^1] Do not add instructions that ask for reasoning in the output (see `<model_targeting>` in `SKILL.md`).
</haiku_thinking_and_effort>

## Harness Interactions

<haiku_harness_interactions>
These findings concern how a harness or a task skill passes text to the model.
- **User text in tool results (Haiku 5.5).** The model "is trained to resist prompt injection through tool results" and can ignore user text delivered inside a `tool_result` block, or in a system message the harness inserts directly after a tool result; "Never put user text inside a `tool_result` block." The page also says to keep harness notices (e.g., reminders) in a system message separate from the user's words.[^1]
- **No context awareness (Haiku 5.5).** Haiku 5.5 does not receive the injected tags that report remaining context.[^11] Do not assume a Haiku 5.5 worker knows how much context remains.
- **No prefill (Haiku 5.5).** Haiku 5.5 rejects an assistant prefill "with a 400 error, even with thinking turned off."[^12]
</haiku_harness_interactions>

## Refusals

<haiku_refusals>
- **Classifiers (Haiku 5.5).** Haiku 5.5 has safety classifiers that may decline requests in the `cyber`, `frontier_llm`, `bio`, and `general_harms` categories.[^1] The prompting page does not list `reasoning_extraction`; the refusals page lists Haiku 5.5 among the models that run classifiers and lists `reasoning_extraction` among the categories, without saying which categories apply to which model.[^13] Write skills without requests for reasoning in the output regardless, because the same skill may run on a model that has it.
- **No fallback (Haiku 5.5).** Haiku 5.5 "has no server-side fallback", and "Sending the same request to Claude Haiku 5.5 again usually returns another refusal."[^1][^13] The refusals page still describes sending the request to another Claude model as the way to get an answer.[^13]
- **Over-refusal (Haiku 5.5).** In Anthropic's automated behavioral audit, Haiku 5.5 "over-refused more than any other model we tested".[^5] Its cybersecurity safeguards "permit a wider range of defensive tasks than our safeguards for Sonnet 5.5, but they still block penetration testing".[^3]
</haiku_refusals>

## Documentation Gaps

<haiku_documentation_gaps>
The documentation does not say whether Haiku 5.5 reads instructions literally, as Sonnet 5 does, or generalizes from brief instructions, as Fable 5 does, and gives no guidance on how much detail it needs beyond the skill-authoring guide's general note. The only measurements are the system card's instruction-following comparison and the prompting page's testing of system-prompt adherence. The absence of documentation is a gap, not evidence of either behavior, so test Haiku-targeted skills on Haiku (see `<empirical_validation>`) rather than assuming parity or deficiency.
</haiku_documentation_gaps>

## Retired Claims

<haiku_retired_claims>
Earlier versions of this file or of `expert-skill-creator` made these claims; do not reintroduce them without a current source.
- "Anthropic publishes no Haiku-specific prompting page." Anthropic now publishes Prompting Claude Haiku 5.5.[^1]
- Haiku described as not supporting effort, as using manual extended thinking, as accepting prefill, or as receiving context-awareness tags, without a version. None of these holds for Haiku 5.5.[^1][^11][^12]
- Haiku described as having no safety classifiers. Haiku 5.5 has them.[^1]
- "For skills targeting Haiku in multi-tier systems, scaling to 10 examples can close the performance gap with higher tiers." No source was found; the official recommendation is 3–5 examples with no tier-based scaling.[^7]
</haiku_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting Claude Haiku 5.5. Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5

[^2]: Anthropic. 2026. What's new in Claude Haiku 5.5, introduction. Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5

[^3]: Anthropic. 2026. Introducing Claude Haiku 5.5, page header (release date), "Safety", and "Further updates". Retrieved October 7, 2026 from https://www.anthropic.com/claude-haiku-5-5

[^4]: Anthropic. 2026. Optimizing for cost and intelligence, "Compare models on cost per task". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence

[^5]: Anthropic. 2026. System Card: Claude Haiku 5.5, §6.1.2, §6.2.2, and §6.2.3. Retrieved October 7, 2026 from https://www.anthropic.com/claude-haiku-5-5-system-card

[^6]: Anthropic. 2026. Skill authoring best practices, "Test with all models you plan to use". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

[^7]: Anthropic. 2026. Prompting best practices, "Use examples effectively". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^8]: Plotly. 2026. Claude Haiku 5.5 Data Analytics Benchmark Results. Retrieved October 7, 2026 from https://plotly.com/blog/claude-haiku-5-5-plotly-data-analytics-bench/

[^9]: Anthropic. 2026. Model configuration, "Extended thinking". Claude Code Docs. Retrieved October 7, 2026 from https://code.claude.com/docs/en/model-config.md

[^10]: Anthropic. 2026. Effort, "Recommended effort levels for Claude Haiku 5.5". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/build-with-claude/effort

[^11]: Anthropic. 2026. Context windows, "Context awareness". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/build-with-claude/context-windows

[^12]: Anthropic. 2026. Claude Haiku 5.5 migration guide, "Replace assistant prefill". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide

[^13]: Anthropic. 2026. Refusals and fallback, introduction and "Server-side fallback". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback

[^14]: Anthropic. 2026. Models overview, "Compare models", row "Reliable knowledge cutoff". Claude Platform Docs. Retrieved October 7, 2026 from https://platform.claude.com/docs/en/models/overview
</sources>

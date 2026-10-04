# Prompting Haiku-Line Models: Notes for Skill Authors

<haiku_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

This file records what Anthropic documents about how Haiku-line models respond to instructions, for authors of skills and agent prompts those models will run, most often as fast subagent workers. As of October 3, 2026, the current version is Claude Haiku 4.5 (`claude-haiku-4-5-20251001`), one generation behind the Fable, Opus, and Sonnet 5.x models. Anthropic has announced that "Claude Haiku 5.5, built for high-volume and cost-sensitive applications, will join the Claude 5.5 family in the coming weeks",[^1] and lists Haiku 4.5's retirement as "Not sooner than October 15, 2026".[^2] Expect this file to need a full revision when Haiku 5.5 ships; use the model-upgrade checklist in `references/retrofitting-existing-skills.md`.

Anthropic publishes no Haiku-specific prompting page; the prompting best-practices page covers Haiku 4.5 through its general scope statement.[^3] Where this file disagrees with the current documentation, the documentation is correct and this file is out of date.

**Contents:** what is documented; how Haiku 4.5 differs from the 5.x models; documentation gaps; retired claims; sources.
</haiku_reference_scope>

## What Is Documented

<haiku_documented_behavior>
- **More guidance than the larger models need.** Anthropic's skill-authoring guide asks, for Haiku, "Does the Skill provide enough guidance?", and says "What works perfectly for Opus might need more detail for Haiku. If you plan to use your Skill across multiple models, aim for instructions that work well with all of them."[^4] When a skill will run on Haiku, test it there; where Haiku misses an instruction that Opus follows, make the instruction more explicit rather than adding a Haiku-only version.
- **Intended role.** The model-selection guide lists "sub-agent tasks" among Haiku 4.5's uses, alongside "Real-time applications" and "high-volume intelligent processing".[^5] Anthropic's launch post describes Sonnet 4.5 breaking down "a complex problem into multi-step plans, then orchestrate a team of multiple Haiku 4.5s to complete subtasks in parallel."[^6]
- **Few-shot examples.** The general recommendation of 3-5 relevant, diverse examples covers Haiku 4.5 with no tier-specific variation.[^3]
- **Context awareness.** Haiku 4.5 receives injected tags reporting its remaining context window; long-running Haiku workers can therefore be prompted about wrap-up behavior.[^7]
</haiku_documented_behavior>

## How Haiku 4.5 Differs from the 5.x Models

<haiku_differences>
A skill that runs on several models has to work within these differences, because guidance written for the 5.x models does not all apply to Haiku 4.5:
- **Thinking.** Haiku 4.5 uses manual extended thinking (`budget_tokens`), not adaptive thinking, and does not support interleaved thinking.[^2][^7][^8]
- **Effort.** Haiku 4.5 does not support the `effort` parameter; the models overview lists its default effort as "Not supported".[^2] An `effort` field in a skill or subagent that runs on Haiku has nothing to control.
- **Prefill.** No page addresses Haiku by name, but the best-practices page says prefill was removed "Starting with Claude 4.6 models" and that "Earlier models continue to support prefills", which includes Haiku 4.5; prefill is still incompatible with thinking.[^3][^8] This is an inference from those two passages.
- **Refusal classifiers.** The refusals page lists its safety classifiers, including `reasoning_extraction`, for Fable 5.1, Fable 5, Opus 5.5, Opus 5, and Sonnet 5.5, not for Haiku 4.5.[^9] Write skills without reasoning sections anyway, because the same skill may run on a 5.x model.
- **Knowledge cutoff.** Haiku 4.5's reliable knowledge cutoff is February 2025, the oldest among current models, so it sets the baseline for Recent Changes sections (see `references/recent-changes.md`).[^2]
</haiku_differences>

## Documentation Gaps

<haiku_documentation_gaps>
The documentation does not say whether Haiku differs from Sonnet or Opus in instruction-following precision, sensitivity to prompt phrasing, or tool-triggering thresholds, beyond the skill-authoring guide's general note that Haiku may need more detail. The absence of documentation is a gap, not evidence of equivalence, so test Haiku-targeted skills on Haiku (see `<empirical_validation>`) rather than assuming either parity or deficiency.
</haiku_documentation_gaps>

## Retired Claims

<haiku_retired_claims>
Earlier versions of this file or of `expert-skill-creator` made these claims; do not reintroduce them without a current source.
- "For skills targeting Haiku in multi-tier systems, scaling to 10 examples can close the performance gap with higher tiers." A search of Anthropic's documentation, cookbook, and engineering blog found no source; the official recommendation is 3-5 examples with no tier-based scaling.[^3]
- The phrase "a leap forward for agentic coding, particularly for sub-agent orchestration and computer use tasks" attributed to Anthropic's launch announcement. It appears on that page in a customer testimonial from Warp's founder, not in Anthropic's own text.[^6]
</haiku_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Introducing Claude Sonnet 5.5. Retrieved October 3, 2026 from https://www.anthropic.com/claude-sonnet-5-5

[^2]: Anthropic. 2026. Models overview, "Compare models". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/models/overview

[^3]: Anthropic. 2026. Prompting best practices, introduction, "Use examples effectively", and "Migrating away from prefilled responses". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^4]: Anthropic. 2026. Skill authoring best practices, "Test with all models you plan to use". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

[^5]: Anthropic. 2026. Choosing a model, "Model selection matrix". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/about-claude/models/choosing-a-model

[^6]: Anthropic. 2025. Introducing Claude Haiku 4.5. Retrieved October 3, 2026 from https://www.anthropic.com/news/claude-haiku-4-5

[^7]: Anthropic. 2026. Context windows, "Context awareness" and the section on thinking with tool use. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/context-windows

[^8]: Anthropic. 2026. Thinking, "Configuring thinking" and "Response prefill and forced tool use". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/thinking

[^9]: Anthropic. 2026. Refusals and fallback, introduction. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
</sources>

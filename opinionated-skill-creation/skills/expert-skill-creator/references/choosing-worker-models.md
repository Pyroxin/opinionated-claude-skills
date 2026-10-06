# Choosing Worker Models

<worker_models_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

This file is for authors of task skills and agents that spawn subagents, and for the agents that choose a subagent's model at runtime. It describes what each Claude model line is good and bad for, from Anthropic's documentation, independent evaluations, and the author's own unmeasured observations, each labeled as such. The observations were made on Fable 5.1, Opus 5.5, Sonnet 5.5, and Haiku 4.5 as of October 3, 2026, unless an entry names an earlier version, and may not hold for later versions; when a new version ships, update this file along with the matching `references/prompting-*.md` file, using the model-upgrade checklist in `references/retrofitting-existing-skills.md`.

**Contents:** how a worker's model is set; what each model is good and bad for; notes that apply to every model; sources.
</worker_models_reference_scope>

## How a Worker's Model Is Set

<worker_model_mechanics>
In Claude Code, a subagent's model comes from, in order of precedence: the `model` parameter the orchestrating agent passes when it spawns the subagent; the `model` field in the subagent's definition (`inherit` selects the main conversation's model); the `CLAUDE_CODE_SUBAGENT_MODEL` environment variable; and the main conversation's model.[^1] A skill with `context: fork` can also set `model` and `effort` in its frontmatter.[^2] Values include the aliases `fable`, `opus`, `sonnet`, and `haiku`, which select the newest model in that line (or the main conversation's own model when the conversation runs that line), and full model IDs.[^1]

Give an agent definition, or a fork skill whose prompt is written in advance, a `model`, and write its prompt for that model's line (see `<model_targeting>` in `SKILL.md`). When the orchestrating agent writes a subagent's brief at runtime (e.g., for a general-purpose subagent), it chooses the model by weighing the subtask against the table below, and writes the brief for that model's line.
</worker_model_mechanics>

## What Each Model Is Good and Bad For

<worker_model_table>
Ability on decisions without a fixed criterion (e.g., planning, design choices, diagnosis, code review) rises with tier in the author's observation (not measured): `fable` is strongest and `opus` is also suitable. Use `fable` or `opus` for planning, not `sonnet` or `haiku`. The table describes tendencies to weigh against the subtask, not a complete list of cases.

| Model | Good for | Bad for |
| --- | --- | --- |
| `fable` | Planning and other decisions without a fixed criterion, more so than `opus` (author's observation); work in which many details must be considered together, where it outperforms `opus` (author's observation); functional correctness on coding tasks (one benchmark of 179 tasks in real projects: 87% against 69% for `opus`, scored with solutions recalled from training removed; counting them, `opus` scored 94.4%)[^3]; tasks given as a brief instruction, since it generalizes from a brief instruction to related behavior (documented for Fable 5)[^4]. | Staying in scope ("may fix nearby code, extend behavior the task didn't mention, or commit more test files than the change warrants")[^5]; small edits (more likely to rewrite an entire file)[^5]; exact quotation (more likely than Fable 5 to "reproduce passages of the source text without marking them as quotations"[^5]; on one task, 5 of 27 checkable quotes were not in the source[^6]); numeric limits (exceeded a word cap and a quote count in one evaluation)[^6]; turnaround time (slowest tier)[^7]; defensive-security content (its cyber safeguards are "likelier to trigger than Opus 5's", from a deliberately wider safety margin)[^8]. |
| `opus` | Planning and other decisions without a fixed criterion (author's observation); code changes that finish in few steps (one benchmark: about 17 tool calls per task, against 42 for `fable`)[^3]; stating figures and citing sources accurately (Anthropic's testing)[^9]. | Running unattended to completion (some turns end with a progress report instead of a tool call)[^9]; staying in scope (adds steps that weren't requested; documented for Opus 5)[^10]; problems resembling well-known ones (one benchmark found 51 fixes recalled from training rather than derived)[^3]; explicit verification instructions (over-verifies; documented for Opus 5)[^10]; cybersecurity tasks (most are rerouted to an older Opus)[^11]. |
| `sonnet` | Fast turnaround on work whose steps and output format are already specified (faster than `opus` and `fable`)[^7]; following instructions literally, especially at lower effort (documented for Sonnet 5)[^12]. | Planning and other decisions without a fixed criterion (author's observation); work spanning many steps or files (Anthropic: "For the hardest long-horizon work, an Opus model is the better choice.")[^13]; time-sensitive facts ("sometimes answers from its training knowledge when a web search would catch details that have changed")[^13]; staying in scope (adds "tests, documentation, and small supporting files" at every effort level)[^13]; finishing agentic coding tasks at `low` and `medium` effort ("sometimes checks in before the work is done")[^13]; benign cybersecurity tasks (more refusals)[^14]. |
| `haiku` | Fast lookups whose results can be checked (fastest tier[^7]; e.g., locating files, symbols, or definitions). | Planning and other decisions without a fixed criterion (author's observation); code changes; combining findings from several sources into one conclusion (e.g., reconciling conflicting documentation, comparing approaches across papers). |

No evaluation of a 5.x Haiku exists yet; apart from the planning entry, the `haiku` row reflects its position as the smallest tier and Anthropic's note that a skill may "need more detail for Haiku",[^15] not a measurement. The current Haiku, Haiku 4.5, does not support the `effort` parameter.[^7]
</worker_model_table>

## Notes That Apply to Every Model

<worker_model_notes>
- **Reviews.** When asking any model for a review, ask it to report every finding with a confidence level and an estimated severity, and filter afterward. A severity filter in the request (e.g., "only report high-severity issues") is followed literally and lowers recall (documented for Opus 5 and Sonnet 5).[^10][^12]
- **Refusals.** Fable 5.1, Opus 5.5, and Sonnet 5.5 all run safety classifiers that can decline a request.[^16] Anthropic documents retrying a refused request on another model as the remedy for a refusal, including automatic retry on a fallback model it recommends for the refusal category.[^16] Do not rephrase, split, or disguise a refused request so that it asks for the same thing in a form the classifier passes. Changing what the request asks for is different: for a `reasoning_extraction` decline, which has no recommended fallback model, Anthropic says to "change the prompt rather than retry the request" (e.g., by removing an instruction to put reasoning in the output).[^16] When neither route is available, or the retry also refuses, report the refusal.
- **Briefs.** A subagent starts without the orchestrator's conversation, so its prompt has to carry the task, the output format, and the boundaries it needs (see `references/composition.md`).
</worker_model_notes>

## Sources

<sources>
[^1]: Anthropic. 2026. Create custom subagents, "Choose a model". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/sub-agents.md

[^2]: Anthropic. 2026. Extend Claude with skills, "Frontmatter reference". Claude Code Docs. Retrieved October 3, 2026 from https://code.claude.com/docs/en/skills.md

[^3]: Luca Compagna. 2026. Opus 5.5: 6x cheaper and 2x faster than Fable 5.1, but only 33.5% of code is secure. Endor Labs. Retrieved October 3, 2026 from https://www.endorlabs.com/learn/opus-5-5-6x-cheaper-and-2x-faster-than-fable-5-1-but-memorization-keeps-it-off-the-top-spot

[^4]: Anthropic. 2026. Prompting Claude Fable 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

[^5]: Anthropic. 2026. Prompting Claude Fable 5.1. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1

[^6]: Katie Parrott and Dan Shipper. 2026. Vibe Check: Fable 5.1—Anthropic Is So Back (Again). Every. Retrieved October 3, 2026 from https://every.to/vibe-check/fable-5-1-vibe-check

[^7]: Anthropic. 2026. Models overview, "Compare models". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/models/overview

[^8]: Anthropic. 2026. System Card: Claude Fable 5.1 & Claude Mythos 5.1, §3.4. Retrieved October 3, 2026 from https://www.anthropic.com/claude-fable-5-1-mythos-5-1-system-card

[^9]: Anthropic. 2026. Prompting Claude Opus 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5

[^10]: Anthropic. 2026. Prompting Claude Opus 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5

[^11]: Anthropic. 2026. Introducing Claude Opus 5.5. Retrieved October 3, 2026 from https://www.anthropic.com/claude-opus-5-5

[^12]: Anthropic. 2026. Prompting Claude Sonnet 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5

[^13]: Anthropic. 2026. Prompting Claude Sonnet 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5

[^14]: Anthropic. 2026. System Card: Claude Sonnet 5.5, §3.3. Retrieved October 3, 2026 from https://www.anthropic.com/claude-sonnet-5-5-system-card

[^15]: Anthropic. 2026. Skill authoring best practices, "Test with all models you plan to use". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

[^16]: Anthropic. 2026. Refusals and fallback. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
</sources>

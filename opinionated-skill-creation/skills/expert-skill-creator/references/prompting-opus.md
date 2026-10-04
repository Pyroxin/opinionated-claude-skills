# Prompting Opus-Line Models: Notes for Skill Authors

<opus_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

This file records what Anthropic documents about how Opus-line models respond to instructions, for authors of skills, agent prompts, and other instructions those models will run. As of October 3, 2026, the current version is Claude Opus 5.5 (`claude-opus-5-5`). Anthropic writes each version's prompting page as a set of differences from its predecessor's; the Opus 5.5 page says "Existing Claude Opus 5 prompts should perform well without changes, and the patterns in Prompting Claude Opus 5 remain a reasonable starting point."[^1] This file therefore keeps the Opus 5 findings that the Opus 5.5 page does not revise, and labels every finding with the version it was documented for.

Treat each finding as measured on the version it names, and re-check it before applying it to another model line.[^4] Where this file disagrees with the current documentation, the documentation is correct and this file is out of date. When a new Opus version ships, compare its prompting page against this file using the model-upgrade checklist in `references/retrofitting-existing-skills.md`.

**Contents:** instruction following and scope; verification and self-correction; delegation and multi-agent work; finishing and reporting; wording that names patterns; thinking, effort, and refusals; changes from Opus 5 to Opus 5.5; retired claims; sources.
</opus_reference_scope>

## Instruction Following and Scope

<opus_instruction_following>
- **Opus 5 and 5.5 are not documented as literal instruction followers.** The Opus 5 page uses "literal" only about review filters: "If your review prompt says "only report high-severity issues" or "be conservative," the model may follow that instruction literally and report less; ask it to report everything and filter in a separate pass instead."[^2] In a skill that asks for a review, ask for every finding with a confidence level and a severity, and filter in a later step.
- **Scope expansion (Opus 5).** "Claude Opus 5 can also expand the scope of a task, adding steps that weren't requested or applying its own judgment about what the task should be. For narrow tasks, constrain scope explicitly". The page's scope instruction begins "Deliver what was asked, at the scope intended." and has the model state a disagreement in a sentence and continue "rather than quietly narrowing, widening, or transforming it."[^2] Give a skill with a narrow task an explicit scope rule.
- **Getting to work quickly (Opus 5.5).** The model "tends to get to work quickly, and on loosely specified tasks it helps to tell the model to look through the relevant sources before acting." The page's "explore broadly" instruction costs "slightly more tool calls and tokens", and the page advises keeping untrusted content out of the records it searches.[^1]
</opus_instruction_following>

## Verification and Self-Correction

<opus_verification>
- **Remove verification instructions (Opus 5).** "Claude Opus 5 verifies its own work without being told to. If your prompt contains explicit verification instructions ("include a final verification step for any non-trivial task," "use a subagent to verify"), remove them: instructions like these cause over-verification on Claude Opus 5, and removing them reduces wasted tokens with no loss in quality."[^2] The general guide recommends self-check instructions for other models and names Opus 5 as "the exception".[^4] This finding concerns instructions to check the model's own work; an instruction to run an external check (e.g., a test suite, a linter, a validator script) is a different instruction, and the page does not address it.
- **Re-check instructions (Opus 5).** "Avoid instructing re-checks it already performs ("double-check your answer," "re-verify before responding")".[^2]
- **Re-examining earlier answers (Opus 5.5).** In chat, the model "sometimes goes back over an earlier answer while it thinks about a new message"; the page gives a two-sentence instruction that stops this, and warns it "may also make the model less likely to point out a mistake in an earlier answer on its own". Leave it out of skills for long analyses or for agentic work in which a later step can reveal an earlier mistake.[^1]
</opus_verification>

## Delegation and Multi-Agent Work

<opus_delegation>
- **Delegates readily (Opus 5).** "Claude Opus 5 delegates to subagents more readily than prior models. Delegation pays off on genuinely independent, sizeable tracks of work, but it multiplies cost and time when applied to small tasks." The page recommends "explicit guidance on which scenarios warrant delegation, or ... deterministic caps on how many agents can be launched"; its example instruction includes "do not use subagents to verify or double-check your own work."[^2] In a task skill that spawns agents, state when delegation is warranted. Claude Code adds its own delegation instruction on Opus 5 only with its `claude_code` system-prompt preset.[^2]
- **Elapsed-time signals (Opus 5.5).** The model "pays close attention to information about elapsed time"; a harness that appends a budget such as `elapsed 340s / 1200s` gets work finished inside it. The budget "is advisory", so keep a hard timeout, and "under time pressure the model might search and verify a little less."[^1]
</opus_delegation>

## Finishing and Reporting

<opus_finishing>
- **Turns that end in a progress report (Opus 5.5).** On long multi-part tasks, "some of those updates end the turn with text rather than a tool call", and "An unattended agent loop that treats such a turn as the end of the task stops running there." The page's guidance is to "Treat a text-only end of turn as a report rather than as proof the task is done."[^1] For skills that run unattended, the page offers a standing instruction that names four kinds of early stop. It must be present from the first request, it is for agents that run "fully unattended", it does not replace confirmation for risky or irreversible actions, and the page says to expect "somewhat more tool calls and output tokens per task". Name the stops you want avoided and the stops you want kept; the page says the model "is responsive to instructions that name the specific kinds of early stop you want it to avoid".[^1]
- **Response length (Opus 5).** "Claude Opus 5's default user-facing responses run longer than prior Opus models'"; lowering effort does not reliably shorten them, so "To control response length, prompt for it explicitly."[^2] The Opus 5.5 page says it "tends to finish the same task with fewer tokens" and does not repeat the Opus 5 length guidance.[^1]
- **Progress updates (Opus 5 and 5.5).** Opus 5.5 is responsive to instructions asking for "a one-line statement of intent before the first tool call and a short recap at the end", which "helps most in human-in-the-loop work."[^1]
</opus_finishing>

## Wording That Names Patterns

<opus_naming_patterns>
The two Opus pages describe different situations, so neither finding revises the other:
- **Suppressing a known default (Opus 5.5).** "a general instruction such as "avoid a generic AI look" mostly swaps one default for another. It responds well to instructions that name specific patterns to avoid".[^1] When a skill corrects a specific output default, name the patterns.
- **Setting a communication style (Opus 5).** "Positive examples of the communication style you want tend to be more effective than instructions about what not to do."[^2] When a skill sets a style, show examples of it.
</opus_naming_patterns>

## Thinking, Effort, and Refusals

<opus_thinking_and_refusals>
- **"Think carefully" lines (Opus 5.5).** "if your system prompt contains instructions that tell Claude to think carefully before answering, consider removing them for Claude Opus 5.5. The model decides for itself how much to think, and effort is the main control."[^1]
- **Reducing thinking (Opus 5.5).** "Lowering effort reduces thinking, and with it cost and latency, more reliably than prompt instructions do."[^1] Leave thinking-amount instructions out of skill prose; set the `effort` frontmatter field where a skill or subagent needs a level other than the session's.
- **Effort default (Opus 5.5).** `medium` is the default on Opus 5.5; Opus 5 defaulted to `high`. "Effort level names don't correspond to the same amount of thinking across models", and the page says to "Reserve `xhigh` and `max` for work where you've measured a quality gain."[^1]
- **Reasoning extraction (Opus 5 and 5.5).** "Prompts, skills, and tool descriptions that ask Claude Opus 5 to write out its thinking or reasoning, verbatim or in a fixed format, may be declined with the `reasoning_extraction` refusal category. Ask for a short explanation of the answer or a summary of the actions taken instead".[^2] Opus 5.5 keeps this category.[^1]
- **Tool triggering (Opus 5.5).** Forced tool use is not supported; "To make the model call a tool rather than reply in text, say in the prompt when the tool applies."[^3]
- **Cyber safeguards (Opus 5.5).** "Finding vulnerabilities in source code is allowed. High-risk dual-use cybersecurity activities are not."[^1]
</opus_thinking_and_refusals>

## Changes from Opus 5 to Opus 5.5

<opus_version_changes>
Per the Opus 5.5 pages, the changes relevant to instructions are: the default effort is `medium` instead of `high`, with more thinking per turn at a given level; thinking cannot be disabled; text between tool calls arrives as progress-update thinking blocks; some progress updates end the turn as text; the model re-examines earlier answers in chat, gets to work quickly, attends to elapsed time, and falls back on default styles in frontend work; it is "much less likely to state an incorrect figure or cite the wrong source"; and a biology classifier joins the cyber and reasoning-extraction classifiers.[^1][^3]
</opus_version_changes>

## Retired Claims

<opus_retired_claims>
Earlier versions of `expert-skill-creator` made these claims about Opus; do not reintroduce them without a current source.
- "Takes instructions at face value and applies them only to their stated scope", cited to the Opus 4.8 page. That page still says "Claude Opus 4.8 interprets prompts literally and explicitly, particularly at lower effort levels", but no Opus 5 or 5.5 page says so, and the Opus 5 page documents scope expansion instead.[^2][^5]
- Opus as the authoring baseline with Fable as an upgrade path. The current guidance targets both lines; see `<model_targeting>` in `SKILL.md`.
- "Aggressive directives ... counterproductive on Opus and Fable". The current source for over-triggering on emphatic language attributes it to Opus 4.5 and 4.6; see `<directive_language>` in `SKILL.md`.
</opus_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting Claude Opus 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5

[^2]: Anthropic. 2026. Prompting Claude Opus 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5

[^3]: Anthropic. 2026. What's new in Claude Opus 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5

[^4]: Anthropic. 2026. Prompting best practices, "General principles" and "Leverage thinking & interleaved thinking capabilities". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^5]: Anthropic. 2026. Prompting Claude Opus 4.8, "More literal instruction following". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8
</sources>

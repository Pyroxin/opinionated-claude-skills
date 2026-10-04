# Prompting Fable-Line Models: Notes for Skill Authors

<fable_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

This file records what Anthropic documents about how Fable-line models respond to instructions, for authors of skills, agent prompts, and other instructions those models will run. As of October 3, 2026, the current version is Claude Fable 5.1 (`claude-fable-5-1`); Claude Mythos 5.1 shares its prompting page. Anthropic writes each version's prompting page as a set of differences from its predecessor's and states that "Your existing Claude Fable 5 prompts should perform well on Claude Fable 5.1 without changes",[^1] so this file keeps the Fable 5 findings that the Fable 5.1 page does not revise, and labels every finding with the version it was documented for.

Treat each finding as measured on the version it names. Anthropic's general guide says: "Where a technique names a specific model, treat it as measured on that model and re-check it against your own evals before applying it to another."[^4] Where this file disagrees with the current documentation, the documentation is correct and this file is out of date. When a new Fable version ships, compare its prompting page against this file using the model-upgrade checklist in `references/retrofitting-existing-skills.md`.

**Contents:** instruction following; scope and autonomy; writing and formatting; verification, delegation, and memory; thinking, effort, and refusals; changes from Fable 5 to Fable 5.1; retired claims; sources.
</fable_reference_scope>

## Instruction Following

<fable_instruction_following>
- **A brief instruction steers a whole class of behavior (Fable 5).** The page says "you can steer most behaviors with a brief instruction rather than enumerating each behavior by name" and "A short brevity instruction is as effective as listing each pattern".[^2] Where an older skill enumerates cases, write one condition-framed sentence instead and test whether the enumeration still adds anything.
- **Skills written for earlier models are often over-prescriptive (Fable 5).** "Skills developed for prior models are often too prescriptive for Claude Fable 5 and can degrade output quality."[^2] Before keeping an instruction from an older skill, test the skill with it removed, and keep it only if output gets worse without it.
- **State the purpose of a request (Fable 5).** The model "tends to perform better when it understands the intent behind a request"; the page's template names the larger task, who it is for, and what the output enables.[^2] Give each instruction its reason.
</fable_instruction_following>

## Scope and Autonomy

<fable_scope_and_autonomy>
- **Unrequested additions (Fable 5.1).** The model "may fix nearby code, extend behavior the task didn't mention, or commit more test files than the change warrants." Anthropic's scope instruction has the model report pre-existing problems as follow-ups instead of fixing them, implement the reading of an ambiguous task that its wording most directly supports and state that assumption, and commit tests only where the task or the repository calls for them; with it, "unrequested additions and committed test code drop substantially with no measurable change in task success".[^1] Give a skill that changes code or documents an explicit scope rule; the page has the full wording.
- **Stopping before the work is done (Fable 5.1).** The model sometimes "describes what it would do next instead of doing it" or "stops to ask permission".[^1] For skills that run unattended, the page gives two system-prompt blocks; the first begins "You are operating autonomously." and tells the model the user is not watching, which the page says accounts for much of the effect. The block "can also make the model less likely to ask about ambiguous requests", so leave it out of skills in which a person answers questions during the work.
- **Questions are not change requests (Fable 5).** The Fable 5 page's boundaries block reads: "When the user is describing a problem, asking a question, or thinking out loud rather than requesting a change, the deliverable is your assessment." Its checkpoint rule pauses only for "a destructive or irreversible action, a real scope change, or input that only they can provide."[^2]
- **Whole-file rewrites (Fable 5.1).** The model "is more likely than Claude Fable 5 to rewrite an entire text file rather than make a targeted edit"; the page's instruction asks it to "surgically edit a file rather than rewrite the entire thing" when doing so does not change the result.[^1]
</fable_scope_and_autonomy>

## Writing and Formatting

<fable_writing_and_formatting>
- **Mannered prose (Fable 5.1).** Fable 5.1 writes denser prose than Fable 5 in places. The page defines mannered prose as prose that "substitutes metaphor and flourish for direct statement" and gives an instruction to remove it; the short form "Please remove all mannered prose." "also tends to work". Place it in "a user message (preferred) or the system prompt".[^1]
- **Less formatting (Fable 5.1).** The model "uses bold less and is less likely to reach for headers, lists, or quotation marks". Remove anti-formatting language from skills, or "replace it with a rule that says when specific formatting is appropriate"; the general guide says a minimize-markdown block "can suppress structure the content needs" on this model.[^1][^4]
- **Unmarked quotation (Fable 5.1).** When summarizing, the model is more likely than Fable 5 to reproduce source passages without marking them as quotations. The fix is to "add one complete example of a correct response to the system prompt: the user's request, the response, and a sentence explaining why the response is correct."[^1] A skill that has the model summarize or cite sources needs that example or an equivalent quotation rule.
- **Brevity (Fable 5).** The Fable 5 brevity instruction opens "Lead with the outcome." and keeps output short by being selective about content, "not to compress the writing into fragments, abbreviations, arrow chains like A → B → fails, or jargon."[^2]
- **Progress updates (Fable 5.1).** The model writes fewer user-facing updates during long tool-calling turns than Fable 5. Remove older lines that suppress narration, such as "hold all findings for the final response", "before adding anything".[^1]
</fable_writing_and_formatting>

## Verification, Delegation, and Memory

<fable_verification_and_delegation>
- **Verification (Fable 5).** "Separate, fresh-context verifier subagents tend to outperform self-critique." Separately, an instruction to audit each progress claim against a tool result from the session "nearly eliminated fabricated status reports".[^2] The Fable 5.1 page repeats neither point. This guidance differs from the Opus-line guidance, where Anthropic says verification instructions cause over-verification (see `references/prompting-opus.md`).
- **Delegation (Fable 5 and 5.1).** The Fable 5 page says to "provide explicit guidance about when delegation is appropriate, and prefer asynchronous communication between orchestrator and subagents over blocking until each subagent returns." The Fable 5.1 page recommends a harness in which the subagent-starting tool returns immediately and results arrive later, and notes that "The model still often chooses to wait."[^2][^1] In a task skill that fans out agents, state when delegation is warranted.
- **Memory (Fable 5).** The model "performs particularly well when it can record lessons from previous runs and reference them"; the page's template stores one lesson per file and skips what the repository or chat history already records.[^2]
- **Remaining-context counts (Fable 5).** Showing the model a remaining-token countdown is the most common trigger for it proposing a new session or trimming work: "Avoid surfacing explicit context-budget counts where possible."[^2]
- **Searching at low effort (Fable 5.1).** "At `low` effort, Claude Fable 5.1 is less likely than Claude Fable 5 to call a search or retrieval tool, and more likely to answer from memory." Raise effort for those turns or add the page's search nudge.[^1]
</fable_verification_and_delegation>

## Thinking, Effort, and Refusals

<fable_thinking_and_refusals>
- **Thinking and effort (Fable 5 and 5.1).** Adaptive thinking is always on, and prefill returns a 400 error.[^3] Fable 5.1 defaults to `high` effort; re-run an effort sweep rather than carrying settings over, because "effort level names don't correspond to the same amount of thinking across models." At `xhigh` and `max`, the model may draft much of a long deliverable in its thinking and then write it out again.[^1] Leave effort out of skill prose; set it with the `effort` frontmatter field where a skill or subagent needs a level other than the session's.
- **Reasoning extraction (Fable 5 and 5.1).** The Fable 5 page warns that instructions telling the model "to echo, transcribe, or explain its internal reasoning as response text may trigger the `reasoning_extraction` refusal category" and says to audit skills "for reflection or show-your-thinking instructions." The Fable 5.1 page narrows the wording to prompts that "ask the model to write out its thinking or reasoning" and recommends asking "for a short explanation or a summary of the actions taken instead".[^2][^1]
- **Tool triggering (Fable 5.1).** Forced tool use returns an error; instead, "state in the prompt when the tool applies", because Fable 5.1 "follows explicit tool instructions reliably".[^3]
- **Cyber safeguard false positives (Fable 5.1).** "finding vulnerabilities in source code is permitted." The page lists three triggers to avoid in benign work: phrasing a review as a compile check (ask "Are there any bugs in this program?" instead), a lesser-known language without supplied documentation, and base64 in tool output.[^1]
</fable_thinking_and_refusals>

## Changes from Fable 5 to Fable 5.1

<fable_version_changes>
Per the "What's new" page, Fable 5.1 differs from Fable 5 in the following ways relevant to instructions: parallel tool calling is more variable in loops where the next calls are only implied; it writes fewer progress updates during long tool runs; it answers from memory more often at `low` effort; its prose is denser in places; it formats less in chat; it leaves more quotations unmarked in summaries; and it rewrites whole files for small changes more often.[^3] The Fable 5.1 prompting page adds unrequested additions and test files, longer thinking at `xhigh` and `max`, and fewer classifier false positives than Fable 5 had at launch.[^1]
</fable_version_changes>

## Retired Claims

<fable_retired_claims>
Earlier versions of `expert-skill-creator` made these claims about Fable; do not reintroduce them without a current source.
- "Fable 5 is new and capacity-limited as of June 2026", used to justify treating Fable as an upgrade path rather than a target. No current source supports it.
- The `reasoning_extraction` refusal described as a Fable-class hazard. Anthropic now documents it for Fable 5.1, Fable 5, Opus 5.5, Opus 5, and Sonnet 5.5;[^5] see `<model_targeting>` in `SKILL.md`.
</fable_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting Claude Fable 5.1. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1

[^2]: Anthropic. 2026. Prompting Claude Fable 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5

[^3]: Anthropic. 2026. What's new in Claude Fable 5.1. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1

[^4]: Anthropic. 2026. Prompting best practices, "General principles" and "Control the format of responses". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices

[^5]: Anthropic. 2026. Refusals and fallback, introduction and "Keep reasoning in thinking blocks". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback
</sources>

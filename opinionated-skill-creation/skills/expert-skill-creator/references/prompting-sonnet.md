# Prompting Sonnet-Line Models: Notes for Skill Authors

<sonnet_reference_scope>
Read this file in full, from its first line to its last, before applying it; a partial read can miss rules later in the file.

This file records what Anthropic documents about how Sonnet-line models respond to instructions, for authors of skills and agent prompts those models will run, most often as subagent workers. As of October 3, 2026, the current version is Claude Sonnet 5.5 (`claude-sonnet-5-5`). Anthropic writes each version's prompting page as a set of differences from its predecessor's; the Sonnet 5.5 page says "Existing Claude Sonnet 5 prompts should perform well without changes, and the patterns in Prompting Claude Sonnet 5 remain a reasonable starting point."[^1] This file therefore keeps the Sonnet 5 findings that the Sonnet 5.5 page does not revise, and labels every finding with the version it was documented for. The same page adds: "For the hardest long-horizon work, an Opus model is the better choice."[^1]

Treat each finding as measured on the version it names, and re-check it before applying it to another model line.[^7] Where this file disagrees with the current documentation, the documentation is correct and this file is out of date. When a new Sonnet version ships, compare its prompting page against this file using the model-upgrade checklist in `references/retrofitting-existing-skills.md`.

**Contents:** instruction following; scope and initiative; tools and search; thinking and effort; harness interactions; changes from Sonnet 5 to Sonnet 5.5; retired claims; sources.
</sonnet_reference_scope>

## Instruction Following

<sonnet_instruction_following>
- **Literal reading (Sonnet 5).** "Claude Sonnet 5 interprets prompts literally and explicitly, particularly at lower effort levels. It does not silently generalize an instruction from one item to another, and it does not infer requests you didn't make." To apply an instruction broadly, "state the scope explicitly (for example, "Apply this formatting to every section, not just the first one")."[^2] The Sonnet 5.5 page neither repeats nor revises this finding. In a skill a Sonnet worker will run, state the scope of every instruction.
- **Review filters lower recall (Sonnet 5).** When a review prompt says "only report high-severity issues," "be conservative," or "don't nitpick," "Precision typically rises, but measured recall can fall." The page's coverage instruction has the model report every issue it finds and "include your confidence level and an estimated severity so a downstream filter can rank them." For a single pass, "be concrete about where the bar is rather than using qualitative terms like "important"".[^2]
- **Positive examples for style (Sonnet 5).** "Positive examples ... tend to be more effective than negative examples or instructions that tell the model what not to do." In frontend work, generic instructions such as "make it clean and minimal" "tend to shift the model to a different fixed palette."[^2]
</sonnet_instruction_following>

## Scope and Initiative

<sonnet_scope_and_initiative>
- **Unrequested tests and documentation (Sonnet 5.5).** "The model tends to add tests, documentation, and small supporting files that fit your repository's conventions, even when you don't ask for them. It does this at every effort level, and more at higher effort." To limit it, the page's paragraph reads: "When the work the user asked for is done and checked, stop and report. Don't add features, tests, files, docs or refactors that weren't asked for. If you think one would help, mention it at the end instead of doing it."[^1]
- **Self-started review rounds (Sonnet 5.5).** At `xhigh` and `max`, after finishing a task the model "can start its own rounds of review and verification, sometimes with subagents if your harness provides them"; run routine work at `high` or below, where this is rare. The page's damping instruction "cut session cost by about a third, with no change in quality".[^1] Sonnet 5 is documented as running "self-verification loops more readily" than Sonnet 4.6.[^2]
- **Checking in early (Sonnet 5.5).** "On agentic coding tasks at `low` and `medium` effort, the model sometimes checks in before the work is done." Raise effort first; the page's prompt "Keep working until everything the user asked for is done, and only stop to ask when you can't go on without the user or before a risky step." makes sessions run longer and does not replace rules about risky or irreversible actions.[^1]
- **Requests for ideas or plans (Sonnet 5.5).** "When the user asks for ideas, options or a plan, give them that and stop. Don't start building or changing anything until they say to go ahead."[^1]
- **Verification at low effort (Sonnet 5.5).** The page supplies a paragraph that begins "When you change code that can be run, built, or type-checked, run a real check that exercises the change before reporting it done".[^1]
</sonnet_scope_and_initiative>

## Tools and Search

<sonnet_tools_and_search>
- **Answering from training data (Sonnet 5.5).** The model "sometimes answers from its training knowledge when a web search would catch details that have changed." First remove language that discourages tool use, "such as "only use tools when strictly necessary" or "minimize tool calls"", then add the page's instruction: "Use the search tool to check specifics that may have changed since your training, such as what is allowed, required or charged, even when you feel confident."[^1]
- **Tool triggering (Sonnet 5.5).** Forced tool use is not supported; "To make the model call a tool rather than reply in text, say in the prompt when the tool applies."[^4]
- **Tool-name drift (Sonnet 5.5).** The model "occasionally calls a declared tool by a name that differs only in letter case"; the fix is in the harness, not the prompt.[^1]
</sonnet_tools_and_search>

## Thinking and Effort

<sonnet_thinking_and_effort>
- **Prompts do not reliably reduce thinking (Sonnet 5.5).** "Asking it in the system prompt to think less doesn't reliably reduce its thinking."[^1] This revises Sonnet 5, whose page says "The triggering behavior for adaptive thinking is steerable".[^2] On Sonnet 5.5, lower effort instead.
- **Reasoning before JSON answers (Sonnet 5.5).** For reasoning tasks with JSON output, adding "Think the problem through before you answer." at `high` brings accuracy "close to what the model reaches at `xhigh`."[^1] This asks the model to think, not to write its reasoning into the output, so it does not conflict with the reasoning-extraction rule below.
- **Instructions not to think (Sonnet 5.5).** With `between_tools`, "remove any instruction that tells the model not to think. Such instructions make it more likely that the model writes internal XML tags in its visible output."[^1]
- **Effort (Sonnet 5 and 5.5).** "`high` is the default on the Claude API"; for agentic coding and multistep tool use, the effort page says to "start with `medium` for well-specified tasks and move to `high` for harder or longer ones."[^5] All five levels, including `xhigh` and `max`, are available on Sonnet 5 and 5.5.[^5] Set effort through the `effort` frontmatter field, not prose.
- **Reasoning extraction (Sonnet 5.5).** "If your prompts ask the model to include its reasoning in the response, remove those instructions, because they invite `reasoning_extraction` declines."[^1] The Sonnet 5.5 page also lists `cyber`, `bio`, `frontier_llm`, and `general_harms` refusal categories.
</sonnet_thinking_and_effort>

## Harness Interactions

<sonnet_harness_interactions>
These findings concern how a harness or a task skill passes text to the model.
- **User text in tool results (Sonnet 5.5).** "Never put user text inside a `tool_result` block. The model misreads that placement most often." A token countdown added after every tool result can make the model treat a genuine user message as a prompt injection, so "don't add your own token or budget countdown after tool results."[^1]
- **Context awareness (Sonnet 5 only).** Sonnet 5 receives injected tags reporting its remaining context window; Sonnet 5.5 does not.[^6] Do not assume a Sonnet 5.5 worker knows how much context remains.
- **Progress scaffolding (Sonnet 5 and 5.5).** Sonnet 5: "If you've added scaffolding to force interim status messages ("After every 3 tool calls, summarize progress"), try removing it." Sonnet 5.5: remove older instructions such as "hold all findings for the final response".[^2][^1]
</sonnet_harness_interactions>

## Changes from Sonnet 5 to Sonnet 5.5

<sonnet_version_changes>
The changes relevant to instructions are: the Sonnet 5.5 page reports unrequested tests and documentation at every effort level, early check-ins at `low` and `medium`, self-started reviews at `xhigh` and `max`, answering from training data, and misreading user text placed in tool results; asking for less thinking no longer reliably works; `thinking: {"type": "disabled"}` returns a 400 error and `between_tools` is the lowest setting; context awareness was removed; and Sonnet 5.5 "declines in more categories than Claude Sonnet 5."[^1][^3][^6]
</sonnet_version_changes>

## Retired Claims

<sonnet_retired_claims>
The previous version of this file made these claims; do not reintroduce them without a current source.
- "Strict literalism ... is documented by name for Opus, not for Sonnet." The Sonnet 5 page documents literal reading for Sonnet 5; the Opus documentation of literalism is for Opus 4.8 only.[^2]
- "Claude 4.6 models are significantly more proactive and may overtrigger on instructions that were needed for previous models", applied to Sonnet. The current text has no "significantly", concerns migrating to 4.6 models, and appears on no Sonnet page.[^7]
- Extended thinking with `budget_tokens` described as deprecated. It is removed and returns a 400 error on Sonnet 5 and 5.5.[^2][^4]
- Sonnet described as having context awareness. That holds for Sonnet 5 and not for Sonnet 5.5.[^6]
- "`xhigh` effort appears unavailable on Sonnet." The effort page lists `xhigh` for Sonnet 5.5 and Sonnet 5.[^5]
</sonnet_retired_claims>

## Sources

<sources>
[^1]: Anthropic. 2026. Prompting Claude Sonnet 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5

[^2]: Anthropic. 2026. Prompting Claude Sonnet 5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5

[^3]: Anthropic. 2026. Migrating to Claude Sonnet 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/models/sonnet-5-5/migration-guide

[^4]: Anthropic. 2026. What's new in Claude Sonnet 5.5. Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5

[^5]: Anthropic. 2026. Effort, "Effort levels" and "Recommended effort levels for Claude Sonnet 5.5". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/effort

[^6]: Anthropic. 2026. Context windows, "Context awareness". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/context-windows

[^7]: Anthropic. 2026. Prompting best practices, "General principles" and "Migration considerations". Claude Platform Docs. Retrieved October 3, 2026 from https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
</sources>

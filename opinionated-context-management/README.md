# opinionated-context-management

A mod that lets Claude compact its own conversation at points it chooses. Claude Code compacts a conversation by itself as it nears the context limit, which can happen partway through a step and under a summary written without instructions from Claude, so the work that follows depends on what that summary happened to keep. With this mod, Claude keeps notes on the task in workspace files as it works, asks for a compaction when the work reaches a point it can be resumed from, and is resumed afterward with a prompt it wrote for itself, so the task carries on without the person present.

Mods are an early-access plugin component, so the API this one is written against may change between Claude Code releases. Claude Code only.

## What the mod adds

The mod adds three things to a session:

- **A system prompt section** that tells Claude to keep task notes in files inside the workspace, by default under `{project-root}/.tmp/notes/{task-name}/`, and to compact at each resumable point after updating those notes.
- **A tool, `compact`,** which takes Claude's instructions for the summary, the prompt to resume with, and the paths of the note files. When that turn ends with Claude's answer, the mod compacts and then submits the prompt, led by the note files' absolute paths.
- **Notices** sent to Claude as the conversation grows (see "Notices").

The ordinary and final notices and the tool's description each restate where the notes go and what they hold, and say that the notes don't go in a persistent memory store outside the workspace (e.g., Claude Code's memory directory). These restatements reinforce the system prompt section and don't replace it: when a notice arrives or Claude considers calling the tool, much of the conversation lies between the section and the current work, and restating the documentation expectations reminds Claude of them at the point where they apply.

The notes folder is working material and is not meant to be committed; the main README's [section on `opinionated-research`](../README.md#opinionated-research) describes how `.tmp/` is usually already ignored by git.

## How a compaction request ends

A turn that ends any other way than with Claude's answer (interrupted, refused, or failed) drops the request. So does a later tool call in the main conversation, a `/clear` or `/resume`, a prompt that comes after the request and before the compaction starts, or a turn that starts before it. A subagent's tool calls, and calls another plugin makes for itself, don't count; a prompt here is any the session receives, e.g., a background task's notification as well as the person's message. A reload of the mod while Claude Code is compacting also ends the request when a prompt arrived during that compaction.

When Claude Code compacts the conversation by itself, the person runs `/compact`, or another plugin compacts it, while a request is scheduled, that compaction stands for the one Claude asked for: the mod doesn't compact a second time, and submits the prompt as it would have.

Except after a `/clear` or `/resume`, the mod tells Claude that the request ended without a compaction: with the result of the tool call that canceled it, or otherwise by a notice added to the conversation, which names the cause and says what to do next: for most causes, to attend to what canceled the request and then to ask again. When another compaction had replaced the conversation before the request was canceled, the notice says so and lists the note files, because Claude then has the summary and not the conversation it asked from.

When Claude Code declines or fails the compaction itself, the mod submits a notice in place of Claude's prompt, so the work carries on in the conversation as it stands; Claude's own prompt is submitted only after a compaction, because it was written for a reader who has just the summary. When a prompt can't be submitted, the mod tries once more and then leaves a notice in the conversation, which Claude reads with the next prompt.

A line in the transcript tells the person each of these outcomes, including a compaction that ran; where Claude Code gave a reason for declining or failing a compaction, that line carries it and Claude's notice doesn't.

A known limitation follows from the rule about prompts: when a background task (e.g., a subagent or a background command) finishes after the request and before the compaction starts, its notification cancels the compaction. The last notice tells Claude not to wait for background work, so the case is likeliest there. This behavior has been observed in a session: the request was canceled and Claude read the notice.

## Notices

An ordinary notice is sent to Claude when the context left before the limit falls to a threshold, saying that a compaction would be useful. It asks Claude to compact at the next point where the work can be resumed, and says that it is not an instruction to compact right away, so that a notice arriving partway through a step doesn't interrupt it. The final notice, described below, asks for a compaction at the nearest resumable point.

Thresholds passed in one step send one notice. A threshold the conversation is already past at the first response after a compaction doesn't send its notice, because compacting again wouldn't make the conversation smaller; a transcript line says so, and later thresholds still send theirs. The limit is the auto-compaction threshold, or the whole window when auto-compaction is off or Claude Code hasn't yet reported whether it is on; in that last case the last notice says that the status isn't known. A line in the transcript tells the person when a notice is sent.

Except for the last notice, the texts Claude reads don't state token counts or percentages. Anthropic's [prompting guidance for Fable 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5), in its section "Rare cases of context-budget concern", says that in very long sessions the model "can occasionally suggest a new session, offer to summarize and hand off, or trim its own work", that this "is most often triggered when the harness shows a remaining-token countdown to the model", and advises: "Avoid surfacing explicit context-budget counts where possible." Shortened or abandoned work is the outcome the mod exists to prevent, so the mod applies the same caution on every model. The last notice is sent once the room left before the limit is within a fixed number of tokens, states the room left, and asks for a compaction at the nearest resumable point, so that the compaction is one Claude prepared for.

## Settings

Two settings change when the notices are sent: `remainingContextNoticePercents` (default 50, 30, and 15 percent of context left), entered as percentages separated by commas, and `remainingContextFinalNoticeTokens` (default 30,000 tokens), entered as a whole number. Entering `auto` for either setting restores its default, which is the way to undo a setting, because Claude Code's settings screen doesn't clear a saved value. An entry the mod can't use is ignored and named in a transcript line when the mod loads; the other entries, or the default, apply in its place.

## Predicting the size of the next request

The mod predicts the size of Claude's next request so that a notice can go to Claude with that request. Each response reports how much context it used, and that figure is the starting point. The exception is a response in which Anthropic's API ran a tool itself (e.g., the advisor): Claude Code reports its usage summed over the several requests it made, each answered over the conversation again, so the mod doesn't take that sum as a size. It adds what the response generated to the figure it already had, and the next response made by one request reports the size exactly.

A tool result that arrives afterward will be part of the next request, but a response hasn't reported it yet, so the mod adds an estimate from the result's length, at 2.5 characters per token. That ratio suits what Claude Code's tool results mostly are: published measurements of the current tokenizer put most code, logs, and structured data at roughly 2.3 to 3.1 characters per token (shell scripts and numeric CSV measured lower, near 1.8) and English prose at 3.3 to 3.6, so the estimate of tool output taken together should come out slightly over the true count. An overestimate can send one notice a little early and is discarded when the next response reports its usage, while an underestimate can delay a notice past the end of the turn; the comment on the constant in `hooks/compaction.ts` gives the sources. A notice then reaches Claude with the result that passed the threshold and not a turn later.

The gauge in `opinionated-status-band` follows a different rule on purpose: it shows only what responses have reported as used and doesn't add an estimate. A notice can therefore be sent while the band still shows slightly more room than the notice's threshold. The difference is the estimated size of the tool results since the last response, and the two agree again when the next response reports its usage. The transcript line for a notice states the figure the notice was sent on, estimate included.

## What the tool checks

The tool refuses a call unless notes are current: the call has to list at least one note file, every listed path has to be a file that exists and holds something, and the newest of them has to have been written no earlier than the start of the last tool call or submitted prompt in the main conversation. After a compaction the notes and the summary are what remains of the earlier conversation, apart from any recent messages Claude Code keeps, so the check is made by the tool and not left to the instructions.

The check compares file times and does not read the notes: it does not see a tool call that started before the note was written and finished after it, or a tool that Anthropic's API runs itself, and it does not check what the notes say. A file time that falls on a whole second is allowed two seconds, because some file systems record times that coarsely, and an event inside that allowance is not seen either.

Because notes are required, a task that may not write files cannot compact through the mod. The section and the ordinary and final notices say that their instructions about notes don't override an instruction not to write to the workspace, so such a task carries on under Claude Code's own compaction.

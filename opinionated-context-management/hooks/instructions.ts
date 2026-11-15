// Every text this mod writes. What it gives the model is the system-prompt
// section, the tool's description, the notices sent as the conversation
// grows, the tool's replies, and the notices about a request that ended
// without a compaction. What it shows the person is at the end of the
// file. Kept in one file so the wording can be reviewed and revised as a
// whole. The other files pass these texts a cause's name, a figure, or a
// short phrase: what a setting takes and what applies in its place
// (`readSettings`), and the name of the work that failed (`report`,
// `failureLogLine`).
//
// The wording presents compaction as what lets a task run to any length at
// full quality. With one exception, `finalNoticeText`, whose comment gives
// its reason, it doesn't state token counts, percentages, or remaining room,
// and avoids terms of shortage or urgency, because a model shown how much
// room is left can shorten its work or propose stopping, which is the
// outcome managed compaction exists to prevent. Anthropic documents that
// behavior for Fable 5; this mod assumes it of the other model lines as a
// precaution. Anthropic's Fable 5 prompting page, in its section "Rare cases
// of context-budget concern", advises: "Avoid surfacing explicit
// context-budget counts where possible."
// https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5
// (read on 2026-11-15). This repository's
// opinionated-skill-creation/skills/expert-skill-creator/references/prompting-fable.md
// records the same advice under "Remaining-context counts".
//
// The plugin's name is written out, as a literal, in each of these places,
// because the engine reads them as literals or the model reads them as
// text. A rename has to change every one:
//
// - `.claude-plugin/plugin.json` (`name`), the catalog entry in the
//   repository's `.claude-plugin/marketplace.json`, and the README.
// - `types/index.d.ts`: the key under `PluginState`.
// - `hooks/compaction.ts`: each atom's `plugin`, and the matcher of the
//   tool's own hook.
// - `hooks/register.ts`: the tool name the unmatched `tool.call` hook
//   compares against.
// - This file: `SECTION_ID`, the tool name in `SECTION_TEXT` and in both
//   notices, and the `source` attribute of every `<context_notice>`.
// - `tests/compaction-flow.test.ts`: the tool name in `COMPACT`.

/** A token count in short form, e.g., 950 -> "950", 18_400 -> "18k", 1_000_000 -> "1M", 1_250_000 -> "1.3M". */
const formatTokens = (count: number): string => {
  if (count < 1000) return String(count)
  if (count < 999_500) return `${Math.round(count / 1000)}k`

  return `${(count / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`
}

export const TOOL_NAME = 'compact'

// Said in both notices as well as in the section, because a notice is read
// in a conversation that began before the mod loaded, where the section is
// not in force, and it tells the model to write notes.
const NOT_OVER_READ_ONLY =
  'This notice does not override an instruction not to write to the workspace: when the task\'s instructions do not allow writing files there (for example, a read-only review), do not write notes or call the tool, and carry on with the task.'

export const SECTION_ID = 'opinionated-context-management:context_checkpoints'

export const SECTION_TEXT = `<context_checkpoints>
This session can compact its own conversation, so a task can run to any length. Compaction replaces the conversation so far with a summary, and the work continues over that summary and the files on disk instead of over the whole history. Because you can compact whenever you choose, the size of the conversation is never a reason to shorten a task, skip a step, lower the standard of the work, or hurry. Plan and carry out every task at the scope and standard it calls for.

What compaction changes is where knowledge is kept: after it, you have the summary and the files on disk, and the earlier messages are gone, except any recent ones Claude Code keeps. Keeping notes as you work, and compacting when the conversation's detail is in them, means that what a later step needs is still at hand after that transition.

<task_notes>
During any task with more than a few steps, keep notes as you work, in files inside the workspace, that is, the project directory this session is working in. Use the location within the workspace that the user's or project's instructions name for task notes or progress records, or, when they don't name one, \`{project-root}/.tmp/notes/{task-name}/\`, where \`{task-name}\` is a short name for the task in lowercase words joined by hyphens. Tell the user the path when you create it. Keep these notes in workspace files even when other instructions name a notebook or knowledge base outside the workspace for general notes: the task's notes have to be readable from the workspace by a new context window or another agent, and the compaction tool checks them as files. The notes are where the task's knowledge is kept; the conversation is only where it is worked on.

The notes are working material, not part of the project's content. Leave them out of commits (that is, do not stage them, and do not add them to a commit that stages everything) unless the user or the project's instructions say to commit them.

These instructions about notes do not override an instruction not to write to the workspace. When a task's instructions do not allow writing files there (for example, a read-only review), do not keep notes and do not call the compaction tool, which requires them. Carry the task out at its full scope; Claude Code's own compaction applies to the conversation instead.

Keep two kinds of note:

- A progress record, which states, for example, what is finished and how it was verified, what remains, each decision with its reason, and the next step. Update it when a step completes.
- Detail notes: anything you have learned or produced that a later step may need and that the step in hand does not. Examples include findings from reading code or documentation with their file paths and line numbers, the relevant part of a command's output with the command that produced it, an interface or schema you worked out, options you considered with the reason each was kept or set aside, and open questions.

Write a detail to the notes as soon as the step in hand no longer needs it in view, without waiting for a checkpoint. A detail that is in the notes can be read back when a later step calls for it, so its copy in the conversation is no longer needed, and the conversation can be compacted without losing it. Prefer recording a detail you may not need again over leaving it only in the conversation: reading a note back is cheap, and a detail that existed only in the conversation is gone after compaction unless the summary kept it.

Write every note so that it can be used by a reader who has the note and the repository and nothing else, for example a new context window with no summary of this conversation, or another agent picking the task up. For such a reader:

- State the task's goal and constraints in the progress record itself, and say which files hold the other notes.
- Give each finding with what it is about, where it came from (for example, a file path and line range, a command, or a URL), and what follows from it. A reader cannot recover these from phrases such as "the bug discussed earlier" or "the second approach".
- Define each name you coined during the work at its first use in a note, or use the name the code or the documentation uses.
- State conclusions with the evidence for them, and mark what is unverified as unverified.
</task_notes>

<when_to_compact>
Compact, without waiting for a notice, each time work on the task remains and both of these hold:

- The work is at a checkpoint, that is, in a state you can resume from. Checkpoints include, for example, a milestone completed and verified, the end of one phase of a plan, and a change of topic.
- The detail in the conversation is no longer needed there, that is, everything a later step may need is in the notes or in other files on disk, so the next steps can be done without the exact content of earlier messages (for example, tool output you would otherwise re-read, a diff under discussion, or the wording of an error you are still diagnosing).

When the work is at a checkpoint but later steps still depend on detail that is only in the conversation, write that detail to the notes; the second condition then holds. Keeping the notes current as you work, as \`<task_notes>\` describes, means this is usually already done when a checkpoint arrives.

Compacting whenever both hold keeps the conversation small, so every later step is answered over the material that step needs instead of over the whole history.

As the conversation grows, the context-management mod sends you a context notice saying that a compaction would now be useful. After one arrives, compact at the next point where the work can be resumed; the notice is not a request to stop sooner than the work allows.

Wait to compact while a question to the user is unanswered, or while work you started in the background (for example, a subagent or a background command) is still running, because its answer or result would arrive in a conversation that no longer holds the question or the work it belongs to. A notice that tells you not to wait takes precedence over this rule, and says what to do instead.
</when_to_compact>

<how_to_compact>
Do these four steps in this order. The order matters because the tool checks it.

1. Finish everything else first. Bring the step in progress to a resumable state, that is, complete it or decide exactly where it stands. Do whatever the work still calls for with other tools, for example running a check or committing, before step 2.
2. Update the notes. Write the progress record, and any detail a later step may need that is not yet written down. Every compaction needs notes: for a short task, a brief progress record is enough (e.g., one that states the goal, what was done, and the next step). Writing the notes has to be the last thing you do before step 3.
3. Call the \`mcp__opinionated-context-management__${TOOL_NAME}\` tool as the next tool call after the notes, without another tool call in between. In \`instructions\`, say what the summary has to keep, for example the task's goal and constraints, the user's standing instructions and corrections, the paths of the task's notes, and open questions. In \`continuation\`, write the prompt you will receive after compaction, for a reader who has only the summary: name the progress record and the next step, and restate in full any request of the user's that is not yet finished. In \`notes\`, list the paths of the task's note files, the progress record first.
4. End your turn without calling another tool. The conversation is compacted after the turn ends with your answer, and your continuation is then submitted as the next prompt, so the work resumes without the user. A tool call made after the tool accepts the request cancels it, and so does a new prompt (for example, a message from the user or a notification from a background task) that arrives before the compaction starts. When a request ends without a compaction, a context notice tells you why and what to do next, and your continuation is not submitted. The one case without a notice is a conversation the user replaced (for example, with /clear), which no longer holds the request.

The tool checks steps 2 and 3. It refuses a call that doesn't list any note files, a call that lists a file that is missing, empty, or not a file, and a call made when any other tool call, or a new prompt, came after the newest note was written, because the notes would then not reflect it. A refusal says what to correct (for example, to update the progress record); after correcting it, call the tool again as the next tool call. After compaction the tool gives the note paths back to you, ahead of your continuation.
</how_to_compact>

Only the main conversation compacts this way: a subagent leaves compaction to the session that started it.
</context_checkpoints>`

export const TOOL_DESCRIPTION = `Compacts this conversation when the current turn ends, then resumes the work. The conversation so far is replaced with a summary written under your \`instructions\`, and your \`continuation\` is submitted as the next prompt, so the work carries on without the user.

Use it when the work can be resumed and the detail in the conversation is no longer needed for the next steps: for example, after a milestone is completed and verified, at a change of topic, or at the next such point after a context notice.

Updating the task's notes is required before every call, and it has to be the last thing you do before the call. After compaction the summary and the files on disk remain, with at most a few recent messages, so the notes are what carries the task's knowledge. Do the steps in this order:

1. Finish everything else: bring the step in progress to a resumable state, and make any other tool calls the work still needs (for example, running a check or committing).
2. Update the notes in workspace files: a progress record (e.g., the goal, what is finished and verified, what remains, decisions with their reasons, and the next step), plus any detail a later step may need. Write them so that a new context window or another agent could continue from them without the summary. A short task still needs a brief progress record.
3. Call this tool as the next tool call, listing the note files' paths in \`notes\`.
4. End your turn without calling another tool.

The tool refuses a call that doesn't list any note files, a call that lists a file that is missing, empty, or not a file, and a call made when any other tool call or a new prompt came after the newest note was written. A tool call made after the tool accepts the request cancels it, and so does a new prompt (for example, a message from the user or a notification from a background task) that arrives before the compaction starts. When a request ends without a compaction, a context notice tells you why and what to do next, and your continuation is not submitted. A refusal says what to correct (for example, to update the progress record); after correcting it, call the tool again as the next tool call. After compaction the tool gives the note paths back to you, ahead of your continuation.

Compacting is what lets a long task continue at full scope and quality; it is never a reason to shorten or hurry the work.`

export const TOOL_INPUT_SCHEMA = {
  type: 'object',
  properties: {
    instructions: {
      type: 'string',
      description:
        'What the summary has to keep, for example the task\'s goal and constraints, the user\'s standing instructions and corrections, the paths of the task\'s notes, and open questions.',
    },
    continuation: {
      type: 'string',
      description:
        'The prompt submitted after compaction, written for a reader who has only the summary: name the progress record and the next step, and restate in full any request of the user\'s that is not yet finished.',
    },
    notes: {
      type: 'array',
      items: { type: 'string' },
      description:
        'The paths of the task\'s note files, the progress record first. Each has to exist and hold something, and writing to at least one of them has to be the last thing done before this call: the tool refuses when any other tool call or a new prompt came after the newest note was written. A path may be absolute or relative to the session\'s directory. The paths are given to you again after compaction, as absolute paths, ahead of your continuation.',
    },
  },
  required: ['instructions', 'continuation', 'notes'],
} as const

/**
 * The notice sent when the conversation's size passes a threshold: with the
 * tool result that passed it, or appended after the response that did.
 * It repeats the procedure in brief because the system-prompt section is not
 * in force in a conversation that began before the mod loaded.
 */
export const NOTICE_TEXT = `<context_notice source="opinionated-context-management">
This notice was generated by the context-management mod; the user did not write it. The conversation has grown to a size where compacting it at your next resumable point would be useful.

The task doesn't change: keep its full scope and standard, and finish the step you are on properly. When you next reach a point where the work can be resumed (for example, the current step completed and verified), compact the conversation; the rest of the task then continues from your notes and your continuation. Wait to compact while a question to the user is unanswered or work you started in the background is still running. ${NOT_OVER_READ_ONLY}

1. Bring the task's notes up to date, written so that a new context window or another agent could continue from them without a summary of this conversation: a progress record (e.g., what is finished and verified, what remains, decisions with their reasons, and the next step), and any detail a later step may need, with where it came from.
2. Call \`mcp__opinionated-context-management__${TOOL_NAME}\` with \`instructions\` for the summary, a \`continuation\` prompt that names the next step, and \`notes\` listing the paths of the note files, the progress record first. Make this call directly after updating the notes, without another tool call in between.
3. End your turn without calling another tool; the work resumes from the continuation after compaction.
</context_notice>`

/**
 * The last notice, sent when the conversation is within the configured
 * margin of its limit: the size at which the engine compacts by itself, or
 * the window's end when auto-compaction is off. `tokensLeft` is the room
 * left at that moment, which is the margin or less.
 *
 * It is the one text here that states how much room is left and asks for
 * promptness. This close to the engine's own compaction, the earlier notices'
 * open-ended timing would be the costlier error: an automatic compaction can
 * start partway through a step, under a summary written without the model's
 * instructions, with the notes out of date. The notice still holds the task's scope fixed,
 * because what it asks to bring forward is the pause, not the end of the work.
 */
export const finalNoticeText = (
  tokensLeft: number,
  autoCompact: 'on' | 'off' | 'unknown',
): string =>
  `<context_notice source="opinionated-context-management">
This notice was generated by the context-management mod; the user did not write it. ${
    autoCompact === 'on'
      ? `About ${formatTokens(tokensLeft)} tokens of room are left before automatic compaction, so the engine may compact this conversation on its own at any response from here on, partway through a step and without your instructions for the summary.`
      : autoCompact === 'off'
        ? // With auto-compaction off, the limit is the window itself and the
          // compaction this session relies on is the one the model asks for.
          `About ${formatTokens(tokensLeft)} tokens of room are left in the context window, and automatic compaction is off in this session, so the conversation continues past this window only through a compaction you ask for.`
        : // The engine has not said whether auto-compaction is on, and the
          // notice says so instead of claiming either.
          `About ${formatTokens(tokensLeft)} tokens of room are left in the context window. Whether automatic compaction is on in this session is not known to the mod: when it is on, the engine may compact this conversation on its own at any response from here on, partway through a step and without your instructions for the summary; when it is off, the conversation continues past this window only through a compaction you ask for.`
  }

Compact now, at the nearest point where the work can be resumed, so that the compaction is yours. ${NOT_OVER_READ_ONLY}

1. Bring the step you are on to the nearest resumable state. Where finishing it would take more than a few tool calls, record exactly where it stands instead. Where work you started in the background is still running, or a question to the user is unanswered, do not wait for it: record it in the notes and in the continuation, because its result or answer can arrive after the compaction.
2. Bring the task's notes up to date, written so that a new context window or another agent could continue from them without a summary of this conversation: a progress record (e.g., what is finished and verified, what remains, decisions with their reasons, and the next step), and any detail a later step may need, with where it came from.
3. Call \`mcp__opinionated-context-management__${TOOL_NAME}\` with \`instructions\` for the summary, a \`continuation\` prompt that names the next step, and \`notes\` listing the paths of the note files, the progress record first. Make this call directly after updating the notes, without another tool call in between.
4. End your turn without calling another tool.

The task itself is unchanged: after compaction the remaining work continues from your continuation at its full scope and standard. Only the pause comes sooner; don't drop or shorten any part of the work.
</context_notice>`

export const SCHEDULED_REPLY =
  'Compaction is scheduled for the end of this turn. End the turn with a one-line message to the user and without calling another tool; a tool call made after this one cancels the compaction. After compaction, your continuation is submitted as the next prompt. When the compaction does not happen, a context notice tells you why, and your continuation is not submitted.'

/**
 * Why a request the tool accepted ended without the mod compacting for it.
 * Each cause has its wording for the model (`endedNotice`) and for the
 * person (`endedLogLine`) in this file, so that the two always agree and
 * the code that finds a cause does not write text.
 *
 * - `tool-call`: another main-thread tool call finished after the request.
 * - `prompt`: a prompt arrived before the compaction started.
 * - `turn-aborted`, `turn-refusal`, `turn-error`, `turn-other`: the turn
 *   that asked did not end with an answer; the last is for a reason the
 *   engine may add later.
 * - `turn-start`: a turn started while the request was due.
 * - `reload`: the mod was reloaded while the engine was compacting, after a
 *   prompt had overtaken the compaction.
 * - `mod-failure`: the mod failed while carrying the request out.
 * - `declined`: the engine answered the mod's one attempt with a skip.
 * - `not-started`: the engine rejected that attempt.
 * - `replaced`: the conversation was replaced by a /clear or a /resume. The
 *   model is not sent a notice for it, because the conversation that
 *   follows never held the request.
 */
export type EndCause =
  | 'tool-call'
  | 'prompt'
  | 'turn-aborted'
  | 'turn-refusal'
  | 'turn-error'
  | 'turn-other'
  | 'turn-start'
  | 'reload'
  | 'mod-failure'
  | 'declined'
  | 'not-started'
  | 'replaced'

/** The cause for a `turn.complete` reason other than `answer`. */
export const turnEndCause = (reason: string): Exclude<EndCause, 'replaced'> =>
  reason === 'aborted'
    ? 'turn-aborted'
    : reason === 'refusal'
      ? 'turn-refusal'
      : reason === 'error'
        ? 'turn-error'
        : 'turn-other'

// What the model does after a notice that arrives ahead of whatever ended
// the request: that comes first, and the compaction is asked for again
// only at a later resumable point.
const ATTEND_THEN_ASK_AGAIN =
  'First attend to what follows this notice (for example, a new prompt from the user or a background task\'s result). Then, where work on the task goes on, ask for the compaction again at your next resumable point: update the notes so that they cover what has happened since, call the compaction tool as the next tool call, and end your turn.'

const NOT_COMPACTED = 'The conversation was not compacted, and the task is unchanged.'

// A request the engine had begun compacting for when it ended: the mod
// cannot see whether that compaction finished.
const MAYBE_COMPACTED =
  'Your continuation was not submitted. The mod cannot tell whether the conversation was compacted first: when it was, the conversation now begins with a summary.'

// What a notice says of the note files, ahead of their paths.
const NOTES_ARE_IN =
  'The task\'s notes, as you listed them when you asked for the compaction, are in these files, given as absolute paths with the progress record first. Read them before continuing:'

// The state when another source compacted the conversation after the
// request was accepted and before it was canceled: the model then has the
// summary and not the conversation it asked from, and its continuation,
// which would have led with the note paths, is not submitted.
const COMPACTED_BEFORE_CANCEL =
  'Before the request was canceled, another source (for example, Claude Code\'s automatic compaction) compacted the conversation, so it now begins with a summary. Your continuation was not submitted.'

// One shape for every cause: what happened and why, what state the
// conversation is in, and what to do next. The engine's own words for a
// failure are left out, because they can state sizes; the person's line
// carries them.
const ENDED: Record<Exclude<EndCause, 'replaced'>, { happened: string; state: string; next: string }> = {
  'tool-call': {
    happened:
      'The compaction you asked for is canceled, because this tool call finished after the request was accepted, and the notes were checked before its result.',
    state: NOT_COMPACTED,
    next: 'To compact, update the notes so that they cover this call, call the compaction tool again as the next tool call, and end your turn.',
  },
  prompt: {
    happened:
      'The compaction you asked for is canceled, because a new prompt arrived before the compaction started.',
    state: NOT_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  'turn-aborted': {
    happened:
      'The compaction you asked for is canceled, because the turn that asked for it was interrupted before it ended.',
    state: NOT_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  'turn-refusal': {
    happened:
      'The compaction you asked for is canceled, because the turn that asked for it ended in a refusal.',
    state: NOT_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  'turn-error': {
    happened:
      'The compaction you asked for is canceled, because the turn that asked for it failed with an error.',
    state: NOT_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  'turn-other': {
    happened:
      'The compaction you asked for is canceled, because the turn that asked for it did not end with your answer.',
    state: NOT_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  'turn-start': {
    happened:
      'The compaction you asked for is canceled, because a new turn started before the compaction could start.',
    state: NOT_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  reload: {
    happened:
      'The compaction you asked for was cut short, because the mod was reloaded while the compaction was under way, after a new prompt had arrived.',
    state: MAYBE_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  'mod-failure': {
    happened:
      'The compaction you asked for was not completed, because the mod failed while carrying it out.',
    state: MAYBE_COMPACTED,
    next: ATTEND_THEN_ASK_AGAIN,
  },
  declined: {
    happened:
      'The compaction you asked for did not happen, because Claude Code or another plugin declined it when your turn ended.',
    state: 'The conversation is unchanged, so nothing needs to be read back.',
    next: 'Carry on with the work from where it stood. Ask for the compaction again when a later step brings the work to a resumable point: update the notes, call the compaction tool as the next tool call, and end your turn.',
  },
  'not-started': {
    happened:
      'The compaction you asked for did not happen, because Claude Code could not carry it out when your turn ended (for example, because something else was running in the session at that moment, such as a command the user ran, or because the summary could not be written).',
    state: 'The conversation is unchanged, so nothing needs to be read back.',
    next: 'Carry on with the work from where it stood. Ask for the compaction again when a later step brings the work to a resumable point: update the notes, call the compaction tool as the next tool call, and end your turn.',
  },
}

/**
 * Tells the model that a request the tool accepted ended without the mod
 * compacting for it, so that a request never ends without the model being
 * told; without it the model would go on believing a compaction is
 * scheduled. How it reaches the model depends on the cause: `tool-call`
 * goes with that call's result; `declined` and `not-started` are submitted
 * as a prompt in place of the continuation, because nothing else is then
 * driving the session; the others are appended to the conversation and
 * read with the prompt or request that follows.
 */
export const endedNotice = (
  cause: Exclude<EndCause, 'replaced'>,
  request?: EndedRequest,
): string => {
  const { happened, state, next } = ENDED[cause]
  const isCompacted = request?.isCompacted === true
  // The note paths are given wherever the model may have only a summary:
  // after another source's compaction, and where the mod cannot tell.
  const isListed = request !== undefined && (isCompacted || state === MAYBE_COMPACTED)
  if (!isListed) {
    return `<context_notice source="opinionated-context-management">
This notice was generated by the context-management mod; the user did not write it. ${happened} ${state} ${next}
</context_notice>`
  }

  return `<context_notice source="opinionated-context-management">
This notice was generated by the context-management mod; the user did not write it. ${happened} ${isCompacted ? COMPACTED_BEFORE_CANCEL : state} ${NOTES_ARE_IN}

${request.notes.map(path => `- \`${path}\``).join('\n')}

${isCompacted && cause === 'tool-call' ? AFTER_COMPACTED_TOOL_CALL : next}
</context_notice>`
}

/**
 * What an ended notice is told of the request it is about: the note files
 * the request listed, as absolute paths, and whether another source
 * compacted the conversation while the request stood.
 */
export type EndedRequest = { notes: readonly string[]; isCompacted?: boolean }

// After another source's compaction the conversation is already small, so
// the `tool-call` notice does not say to ask again at once.
const AFTER_COMPACTED_TOOL_CALL =
  'Carry on with the work. Ask for a compaction again when a later step brings the work to a resumable point: update the notes, call the compaction tool as the next tool call, and end your turn.'

/**
 * Appended to the conversation when the compaction ran but the prompt that
 * resumes the work could not be submitted. The model then has only the
 * summary, so the notice carries what that prompt would have: the note
 * paths and the continuation.
 */
export const resumeFallbackNotice = (notes: readonly string[], continuation: string): string =>
  `<context_notice source="opinionated-context-management">
This notice was generated by the context-management mod; the user did not write it. The conversation was compacted as you asked, but the prompt that resumes the work could not be submitted, so the work resumes with the next prompt you receive. First attend to that prompt. Where it does not direct otherwise, carry on from your continuation, which is given below. ${NOTES_ARE_IN}

${notes.map(path => `- \`${path}\``).join('\n')}

Your continuation:

${continuation}
</context_notice>`

/**
 * The tool's reply when the mod itself failed while handling a call. The
 * error's text goes to the person (`toolFailureLogLine`), not here.
 */
export const INTERNAL_FAILURE_REPLY =
  'The compaction was not scheduled, because the compaction tool failed while handling the request. Carry on with the work; you can call the tool again at a later resumable point.'

export const SUBAGENT_REPLY =
  'Only the main conversation compacts through this tool. Continue your task; the session that started you manages its own context.'

export const MISSING_INPUT_REPLY =
  'Both `instructions` and `continuation` are required and have to be non-empty text. The compaction was not scheduled.'

/**
 * Added to a refusal when the refused call also removed a request that an
 * earlier call in the same turn had scheduled, so that request does not
 * end without the model being told.
 */
export const EARLIER_REQUEST_REMOVED_REPLY =
  'The compaction that an earlier call in this turn scheduled is canceled as well, so no compaction is scheduled now.'

export const BLANK_NOTE_PATH_REPLY =
  'The compaction was not scheduled, because `notes` has an entry that is not a path: every entry has to be the non-empty text of a note file\'s path. Correct the list and call the tool again.'

export const NO_NOTES_REPLY =
  'The compaction was not scheduled, because the call doesn\'t list any note files. Every compaction needs notes, because after it the notes are what carries the task\'s knowledge. Write or update the task\'s progress record in a workspace file (for a short task, a brief one is enough, e.g., one stating the goal, what was done, and the next step), then call this tool as the very next tool call with the file\'s path in `notes`.'

export const noteProblemReply = (path: string, problem: string): string =>
  `The compaction was not scheduled, because of the note file \`${path}\`: ${problem}. Write the note, or correct the path, and call the tool again.`

export const STALE_NOTES_REPLY =
  'The compaction was not scheduled, because something happened after the notes were last written, that is, a tool call or a new prompt came later than the newest of the listed note files, so the notes may not reflect it. The later event can be a prompt you have not read yet (for example, a message the user typed while this turn ran), which reaches you with a later tool result or as the next prompt. Update the progress record so that it covers the work and the requests up to now, including that prompt when it has reached you, then call this tool as the very next thing you do, without another tool call in between.'

/**
 * Put ahead of the continuation in the prompt submitted after a compaction,
 * so the resumed model is told where the notes are by the mod, whatever the
 * summary kept. It is not sent when the compaction did not happen.
 */
export const notesLead = (notes: readonly string[]): string =>
  `<context_notice source="opinionated-context-management">
This notice was generated by the context-management mod; the user did not write it. ${NOTES_ARE_IN}

${notes.map(path => `- \`${path}\``).join('\n')}
</context_notice>`

/**
 * The transcript line shown to the person when a notice is sent to the
 * model. It is drawn in the interface and is not part of what the model
 * reads, so it states the figures the model's notice leaves out.
 */
export const noticeLogLine = (sent: {
  isFinal: boolean
  percentLeft: number
  tokensLeft: number
  isTurnEnding: boolean
}): string => {
  const what = sent.isFinal
    ? `Context management: told Claude that about ${formatTokens(sent.tokensLeft)} tokens of context are left and asked it to compact at the nearest resumable point`
    : `Context management: told Claude that compacting at its next resumable point would be useful (${sent.percentLeft}% of context left)`
  const when = sent.isTurnEnding
    ? 'Claude reads this with the next prompt, because the response that reached the threshold ended its turn.'
    : 'Claude reads this at its next request in the current turn.'

  return `${what}. ${when}`
}

// What the person is told about a request that ended without the mod
// compacting, and how the model learns of it. The lines share one pattern:
// what happened, why, and what Claude was told.
const ENDED_FOR_PERSON: Record<EndCause, { why: string; told: string }> = {
  'tool-call': {
    why: 'Claude made another tool call after asking',
    told: 'Claude is told with that call\'s result.',
  },
  prompt: {
    why: 'a new prompt arrived before the compaction started',
    told: 'Claude reads a notice about it with that prompt.',
  },
  'turn-aborted': {
    why: 'the turn that asked for it was interrupted',
    told: 'Claude reads a notice about it with the next prompt.',
  },
  'turn-refusal': {
    why: 'the turn that asked for it ended in a refusal',
    told: 'Claude reads a notice about it with the next prompt.',
  },
  'turn-error': {
    why: 'the turn that asked for it failed',
    told: 'Claude reads a notice about it with the next prompt.',
  },
  'turn-other': {
    why: 'the turn that asked for it did not end with Claude\'s answer',
    told: 'Claude reads a notice about it with the next prompt.',
  },
  'turn-start': {
    why: 'a new turn started before the compaction could start',
    told: 'Claude reads a notice about it in that turn.',
  },
  reload: {
    why: 'the mod was reloaded while the compaction was under way, after a new prompt had arrived',
    told: 'Claude reads a notice about it at its next request; its own prompt was not submitted.',
  },
  'mod-failure': {
    why: 'the mod failed while carrying it out',
    told: 'Claude reads a notice about it at its next request.',
  },
  declined: {
    why: 'Claude Code or another plugin declined it',
    told: 'Claude was sent a notice in place of its own prompt, and carries on without the compaction.',
  },
  'not-started': {
    why: 'Claude Code could not carry it out',
    told: 'Claude was sent a notice in place of its own prompt, and carries on without the compaction.',
  },
  replaced: {
    why: 'the conversation was replaced (for example, by /clear or /resume)',
    told: 'Claude is not told, because the new conversation never held the request.',
  },
}

/**
 * The transcript line for a request that ended without the mod compacting.
 * `detail` is the engine's or the error's own text, which the model's
 * notice leaves out.
 */
export const endedLogLine = (cause: EndCause, detail?: string, isCompacted = false): string => {
  const { why, told } = ENDED_FOR_PERSON[cause]
  const said = detail === undefined || detail.trim() === '' ? '' : ` (reported as: ${detail.trim()})`
  // The mod did not compact, but the conversation was compacted all the
  // same, and the line says so.
  const elsewhere = isCompacted
    ? ' Another source had compacted the conversation after Claude asked, and the prompt Claude wrote was not submitted.'
    : ''

  return `Context management: did not compact as Claude asked, because ${why}${said}.${elsewhere} ${told}`
}

/**
 * The transcript line for a request that the engine declined or could not
 * carry out, when the notice sent in place of Claude's prompt could not be
 * submitted either. `reason` is why the submit failed.
 */
export const endedNotSubmittedLogLine = (
  cause: 'declined' | 'not-started',
  detail: string,
  reason: string,
): string => {
  const { why } = ENDED_FOR_PERSON[cause]
  const said = detail.trim() === '' ? '' : ` (reported as: ${detail.trim()})`

  return `Context management: did not compact as Claude asked, because ${why}${said}. The notice that tells Claude so could not be submitted as a prompt (${reason}); it is left for Claude in the conversation, so sending any message carries the work on.`
}

/** The transcript line when a refused call removed an earlier call's request. */
export const EARLIER_REQUEST_REMOVED_LOG_LINE =
  'Context management: a compaction Claude had scheduled earlier in this turn is canceled, because a later call of the compaction tool was refused. Claude is told with that refusal.'

/** The transcript line for a compaction the mod carried out. */
export const COMPACTED_LOG_LINE =
  'Context management: compacted the conversation as Claude asked. Claude resumes from the prompt it wrote.'

/**
 * The transcript line when another source compacted the conversation while
 * a request was scheduled, and that compaction stands for the one asked for.
 */
export const COMPACTED_ELSEWHERE_LOG_LINE =
  'Context management: another source (Claude Code itself, /compact, or another plugin) compacted the conversation while a compaction Claude had asked for was scheduled, so the mod did not compact a second time. Claude resumes from the prompt it wrote.'

/**
 * The transcript line when the conversation was compacted but the prompt
 * that resumes the work could not be submitted, after the one retry.
 */
export const resumeNotSubmittedLogLine = (reason: string): string =>
  `Context management: the conversation was compacted, but the prompt that resumes Claude's work could not be submitted (${reason}). A notice with that prompt's content is left for Claude in the conversation, so sending any message resumes the work.`

/** The transcript line when the tool failed while handling a call. */
export const toolFailureLogLine = (reason: string): string =>
  `Context management: the compaction tool failed while handling Claude's request (${reason}). Claude was told that the compaction was not scheduled.`

/**
 * The transcript line when the first response after a compaction is already
 * past a notice threshold, and the notice is held back.
 */
export const pastThresholdAfterCompactionLogLine = (percentLeft: number): string =>
  `Context management: the conversation is already past a notice threshold right after a compaction (${percentLeft}% of context left). Claude was not sent that notice, because compacting again would not make the conversation smaller; later thresholds still send theirs.`

/**
 * The transcript line for a setting entry the mod could not use. `option` is
 * the setting's name, `entry` what was entered, `expected` what the setting
 * takes, and `inForce` what applies in its place.
 */
export const settingProblemLogLine = (problem: {
  option: string
  entry: string
  expected: string
  inForce: string
}): string =>
  `Context management: ignored "${problem.entry}" in the setting ${problem.option}, which takes ${problem.expected}. ${problem.inForce}`

/** The transcript line for a failure of the mod's own work in a hook. */
export const failureLogLine = (what: string, reason: string): string =>
  `Context management: ${what} failed: ${reason}`

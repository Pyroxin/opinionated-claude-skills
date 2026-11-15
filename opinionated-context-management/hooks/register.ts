// The hooks module of the context-management mod: model-controlled
// compaction. The logic is in `compaction.ts` and the texts given to the
// model are in `instructions.ts`; this file only connects them to events.

import type { EngineInterface, Register } from 'claude-code'

import {
  afterStep,
  afterToolResult,
  afterTurn,
  cancelPending,
  compactedElsewhere,
  configure,
  conversationReplaced,
  markEvent,
  measure,
  promptedDuring,
  registerTool,
  registerToolHook,
  resumePending,
  runDue,
  reportSettingProblems,
  takeOwed,
  tellEnded,
  turnStarted,
} from './compaction'
import { endedNotice, failureLogLine, SECTION_ID, SECTION_TEXT } from './instructions'

/**
 * Tells the person about a failure of this mod's own work, in place of
 * letting it end the hook it happened in. The mod's work is secondary to
 * the session start, prompt, response or tool call it is attached to, and
 * the engine skips a hook that throws without saying what it was doing.
 */
const report = ($: EngineInterface, what: string, error: unknown): void => {
  const reason = error instanceof Error ? error.message : String(error)
  try {
    $.ui.log(failureLogLine(what, reason))
  } catch {
    // A failed report can't be reported anywhere.
  }
}

/**
 * The origins of a prompt that the engine delivers into the running turn
 * when the prompt carries that turn's id, as opposed to holding it to start
 * the next turn. They are the two kinds of `PromptOrigin` whose doc in the
 * engine's types says so; a kind whose doc doesn't say (e.g.,
 * `peer-send-message`) is treated as one that may be held.
 */
const DELIVERED_INTO_TURN: ReadonlySet<string> = new Set(['task-notification', 'peer'])

export const register: Register = (on, options) => {
  configure(options)

  on('session.start', async ($, e, next) => {
    // Each step fails alone: without the tool the notices still arrive, and
    // without a first measurement the tool still works.
    try {
      await registerTool($)
    } catch (error) {
      report($, 'registering the compaction tool', error)
    }
    try {
      await measure($)
    } catch (error) {
      report($, 'the first measurement of the context', error)
    }
    // Said at each load, so a person who has just saved a setting sees
    // which of its entries the mod could not use.
    reportSettingProblems($)
    // `session.start` runs again when the module is reloaded: a compaction
    // that was due is carried out.
    try {
      await resumePending($)
    } catch (error) {
      report($, 'restarting the compaction Claude asked for', error)
    }

    return next(e)
  })

  // A compaction of the main conversation that this mod did not ask for: the
  // engine's own, the person's /compact, or another plugin's. When the model
  // had asked for
  // one before it, this one stands for it. The mod's own compaction is
  // recorded where it is asked for, because the engine's types leave open
  // whether this hook sees a compaction this plugin asked for; when it does,
  // the request is being compacted for and is left alone. A `precompute`
  // compaction prepares a summary ahead of time and leaves the conversation
  // as it is, so it doesn't replace anything: treating it as a replacement
  // would discard the size and send again the notices already sent.
  on('session.compact', async ($, e, next) => {
    const outcome = await next(e)
    if (e.agentId === undefined && outcome.skip === undefined && e.trigger !== 'precompute') {
      try {
        await compactedElsewhere($)
      } catch (error) {
        report($, 'recording a compaction', error)
      }
    }

    return outcome
  })

  on('session.end', async ($, e, next) => {
    // A /clear ends the conversation, and a /resume puts another in its
    // place; the process goes on under a new session, without a
    // `session.start` after a /clear. A request belongs to the conversation
    // it was made in, so it is dropped, and the model is not told: the
    // conversation that follows never held the request. Each step fails
    // alone.
    if (e.reason === 'clear' || e.reason === 'resume') {
      try {
        await cancelPending($, 'replaced')
      } catch (error) {
        report($, 'dropping a request when the conversation was replaced', error)
      }
      try {
        await conversationReplaced($)
      } catch (error) {
        report($, 'recording that the conversation was replaced', error)
      }
    }

    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    try {
      await measure($)
    } catch (error) {
      report($, 'a measurement of the context', error)
    }
    // A request is carried out when its turn ends (`turn.complete`, below).
    // The engine raises this after each main-thread turn, so it is a second
    // occasion for a request that is still due: one left by a prompt
    // submitted while the turn ran, or by a turn's end that was not handled.
    try {
      await runDue($)
    } catch (error) {
      report($, 'carrying out the compaction Claude asked for', error)
    }

    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      try {
        await turnStarted($)
      } catch (error) {
        report($, 'dropping a request when a turn started', error)
      }
    }

    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const composed = await next(e)

    return {
      sections: [
        ...composed.sections,
        { id: SECTION_ID, text: SECTION_TEXT, scope: 'session' as const },
      ],
    }
  })

  on('turn.step', async function* ($, e, next) {
    const response = yield* next(e)
    // The conversation grows within a turn, and a long turn is where its
    // size matters, so it is measured after every main-thread response
    // instead of once when the turn ends.
    if (e.agentId === undefined && response.usage !== null) {
      try {
        // A response that doesn't call any tools ends its turn.
        await afterStep(
          $,
          response.usage,
          response.toolUses.length === 0,
          // The API ran a tool inside this response, so its usage is summed
          // over several requests and is not the conversation's size.
          (response.serverToolUses?.length ?? 0) > 0,
        )
      } catch (error) {
        report($, 'measuring the context after a response', error)
      }
    }

    return response
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) return next(e)

    // The request is settled after the engine's own handling of the turn's
    // end, which is when the engine accepts a compaction, and it is settled
    // when that handling rejects as well: left in its `turn` phase, the
    // request would stand until the next prompt without a word to anyone.
    let isHandled = false
    try {
      const outcome = await next(e)
      isHandled = true

      return outcome
    } finally {
      try {
        await afterTurn($, e.reason, e.turnId, isHandled)
      } catch (error) {
        report($, 'settling the compaction Claude asked for', error)
      }
    }
  })

  on('prompt.submit', async ($, e, next) => {
    // Each step fails alone: a prompt that could not be recorded still
    // cancels a scheduled compaction.
    try {
      await markEvent($)
    } catch (error) {
      report($, 'recording a submitted prompt', error)
    }

    // A prompt submitted before a scheduled compaction has started is not in
    // its notes, and the compaction would replace the conversation the
    // prompt was written into. The mod's own continuation is submitted
    // after the request has left state, so it doesn't cancel that request.
    // The prompt can be the person's or one the session receives, e.g., a
    // background task's notification. Once the engine is compacting, the
    // request is kept, so the continuation still follows.
    //
    // Known limitation: a background task (e.g., a subagent or a
    // background command) that finishes after the request and before the
    // compaction starts cancels the compaction, because its notification
    // is such a prompt (`PromptOrigin` kind `task-notification` in the
    // engine's types). The final notice tells the model not to wait for
    // background work, which makes this case likelier there. Seen in a live
    // session on 2026-11-15: the request was canceled and the model read
    // the notice. A remedy would have to
    // tell such a prompt from the person's, e.g., by its origin, and decide
    // whether the notes can be taken to cover it.
    //
    // The cancellation is never silent: the model is told by a notice
    // appended ahead of the prompt, which says to attend to what canceled
    // the request and then to ask again. The notice is appended and not
    // attached as the prompt's `context`, because the engine's types say a
    // prompt the person did not type "takes" no rewrite when it starts a
    // turn, and do not say whether an added `context` counts as one; a
    // background task's notification is such a prompt.
    // A prompt submitted while a turn runs is either delivered into that
    // turn or held to start the next one. One that may be held is recorded,
    // so that a request made after it is not carried out at the end of that
    // turn, ahead of the held prompt (`afterTurn`). The engine's types say
    // it "queues every prompt typed mid-turn". Of a background task's
    // notification they say it is "delivered into a running turn (`turnId`
    // set)", and of another session's message, "as a turn of its own or
    // delivered into a running one"; those the model reads in the turn, so
    // they are not recorded. Recording them would leave the request of
    // any turn that received one (e.g., a subagent's report) to the
    // measurement after the turn.
    if (e.turnId !== undefined && !DELIVERED_INTO_TURN.has(String(e.origin?.kind))) {
      try {
        await promptedDuring($, e.turnId)
      } catch (error) {
        report($, 'recording a prompt submitted during a turn', error)
      }
    }

    try {
      const canceled = await cancelPending($, 'prompt', true)
      if (canceled !== null) await tellEnded($, 'prompt', canceled)
    } catch (error) {
      report($, 'canceling a compaction after a prompt', error)
    }

    return next(e)
  })

  // Every main-thread tool call is an event the notes may need to reflect,
  // read-only ones included: what a call read can change what the model does
  // next. The compaction tool's own call is the one exception, since it is
  // the call the notes are being checked for.
  //
  // The same calls are the ones whose results the main conversation grows
  // by, so each result is also counted toward the conversation's size here.
  //
  // A call another plugin made through `$.tool.call` is neither: its result
  // goes to that plugin, not into the conversation, and the engine drops any
  // `context` on it. `next.origin` names who raised the call.
  on('tool.call', async ($, e, next) => {
    const isOwnTool = String(e.tool) === 'mcp__opinionated-context-management__compact'
    const isCounted = e.agentId === undefined && !isOwnTool && next.origin.plugin === 'engine'
    if (isCounted) {
      try {
        await markEvent($)
      } catch (error) {
        report($, 'recording a tool call', error)
      }
    }

    const outcome = await next(e)
    if (!isCounted) return outcome

    let canceled: Awaited<ReturnType<typeof cancelPending>> = null
    try {
      // A tool call after the compaction tool accepted a request makes the
      // request out of date: the notes were checked before this call. The
      // turn cannot end while the call runs, so canceling after it is in time.
      canceled = await cancelPending($, 'tool-call')
    } catch (error) {
      report($, 'canceling a compaction after a tool call', error)
    }

    // What the model is to be told with this result, apart from a
    // threshold notice: that this call canceled its request, and any notice
    // of an earlier dropped request that could not be appended when it
    // happened.
    const notices = canceled === null ? [] : [endedNotice('tool-call', canceled)]
    try {
      const owed = await takeOwed($)
      if (owed !== undefined) notices.push(owed)
    } catch (error) {
      report($, 'sending a notice that was owed', error)
    }

    // A refused call cancels as well. The engine's types say of a refusal:
    // "Returned after the tool answered without error it withholds that
    // result and undoes nothing". So a hook beneath this one can refuse a
    // call that ran, and a refusal seen here does not show which it was. A
    // refusal cannot carry `context` and is not counted toward the
    // conversation's size; its text is what the model reads, so the
    // notices go there.
    if (outcome.deny !== undefined) {
      return notices.length === 0
        ? outcome
        : { ...outcome, deny: [outcome.deny, ...notices].join('\n\n') }
    }

    // Notices go to the model after this result, as the result's `context`,
    // so the model reads them at its next request in this turn even when
    // that request's response ends the turn. The rest of the result is
    // handed back as it came.
    try {
      const attached = [...(outcome.context ?? []), ...notices].join('\n')
      const notice = await afterToolResult($, `${outcome.text ?? ''}${attached}`)
      if (notice !== undefined) notices.push(notice)
    } catch (error) {
      report($, 'measuring the context after a tool result', error)
    }

    return notices.length === 0
      ? outcome
      : { ...outcome, context: [...(outcome.context ?? []), ...notices] }
  })

  // Registered last: within one module the hook registered first is
  // outermost, and this one answers without calling `next`.
  registerToolHook(on)
}

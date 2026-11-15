// Model-controlled compaction: the model is told as the conversation grows,
// records its progress, and asks for a compaction through a tool; the mod
// compacts when that turn ends and submits the model's own continuation, so
// a long task carries on without the person present.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, ModelUsage, On, PluginOptions } from 'claude-code'

import type { ContextFill, PendingCompaction } from '../types'
import type { EndCause, EndedRequest } from './instructions'
import {
  BLANK_NOTE_PATH_REPLY,
  COMPACTED_ELSEWHERE_LOG_LINE,
  COMPACTED_LOG_LINE,
  EARLIER_REQUEST_REMOVED_LOG_LINE,
  EARLIER_REQUEST_REMOVED_REPLY,
  endedLogLine,
  endedNotice,
  endedNotSubmittedLogLine,
  failureLogLine,
  finalNoticeText,
  INTERNAL_FAILURE_REPLY,
  MISSING_INPUT_REPLY,
  NO_NOTES_REPLY,
  NOTICE_TEXT,
  noteProblemReply,
  notesLead,
  noticeLogLine,
  pastThresholdAfterCompactionLogLine,
  resumeFallbackNotice,
  resumeNotSubmittedLogLine,
  SCHEDULED_REPLY,
  settingProblemLogLine,
  STALE_NOTES_REPLY,
  SUBAGENT_REPLY,
  TOOL_DESCRIPTION,
  TOOL_INPUT_SCHEMA,
  TOOL_NAME,
  toolFailureLogLine,
  turnEndCause,
} from './instructions'

// The atoms are declared in the file that uses them because `claude plugin
// validate` reads a state reference only where its literal is written.
const context = atom({ plugin: 'opinionated-context-management', key: 'context' } as const, null)
const pending = atom({ plugin: 'opinionated-context-management', key: 'pending' } as const, null)
const noticeLevel = atom(
  { plugin: 'opinionated-context-management', key: 'noticeLevel' } as const,
  0,
)
const scale = atom({ plugin: 'opinionated-context-management', key: 'scale' } as const, '')
const lastEventAt = atom(
  { plugin: 'opinionated-context-management', key: 'lastEventAt' } as const,
  0,
)
const eventCount = atom(
  { plugin: 'opinionated-context-management', key: 'eventCount' } as const,
  0,
)
const promptedTurn = atom(
  { plugin: 'opinionated-context-management', key: 'promptedTurn' } as const,
  null,
)
const owedNotice = atom(
  { plugin: 'opinionated-context-management', key: 'owedNotice' } as const,
  null,
)

/** The settings a person can change, with the values in force for this load. */
export type CompactionSettings = {
  /**
   * Fractions of the compaction limit used at which a notice is sent,
   * ascending; 0.7 is the point where 30% of the context remains.
   * More than one, so a notice that arrives when a resumable point isn't near
   * is followed by another later in the same stretch of work.
   */
  noticeAt: readonly number[]
  /**
   * How many tokens before the compaction limit the last notice is sent: the
   * one that states how little room is left before the engine compacts by
   * itself and asks for a compaction at the nearest resumable point.
   *
   * A token count, not a fraction, because the room the model needs to
   * record its progress and call the tool is about the same on every window
   * size, while a fraction of a small window can be less than that.
   */
  finalTokens: number
}

export const DEFAULT_SETTINGS: CompactionSettings = {
  noticeAt: [0.5, 0.7, 0.85],
  finalTokens: 30_000,
}

/**
 * The word a person enters for "use the mod's default". The settings
 * interface of Claude Code 2.1.325 does not let a person clear a value they
 * once saved (an erased number reappears after a save), so the default needs
 * a value that can be typed. It is also what the manifest declares as each
 * option's default, so the default can change in a later version without a
 * stored number pinning the old one.
 */
const AUTO = 'auto'

/**
 * The separate entries of a stored option value: every string in it, split
 * on commas and whitespace, without the empty pieces and without `auto`.
 *
 * A value can arrive as a list, as one string, or as a number, and a list
 * entry can itself hold several entries: the settings interface stores what
 * a person types into a `multiple` field as ONE string (e.g., "85, 80, 75"
 * was stored as `"85, 80, 75"`, observed on 2.1.325), while the manifest's
 * default and a hand-edited settings file give a list. Splitting each string
 * makes every one of those forms mean the same thing.
 */
const entriesOf = (given: unknown): string[] =>
  (Array.isArray(given) ? given : given === undefined || given === null ? [] : [given])
    .flatMap(value => String(value).split(/[\s,]+/))
    .filter(entry => entry !== '' && entry.toLowerCase() !== AUTO)

/** A setting entry the mod could not use, as `settingProblemLogLine` takes it. */
export type SettingProblem = { option: string; entry: string; expected: string; inForce: string }

/**
 * Reads `options` into the settings in force and the entries that could not
 * be used. `auto` (in any letter case), an empty value, and an option that
 * is not set all ask for the default and are not problems. A percentage has
 * to be above 0 and below 100; one that is not is left out, and when none
 * is left the defaults are in force, so a mistyped setting does not turn
 * the notices off. A token count has to be one number above 0; anything
 * else leaves the default in force. A token count that passes is used as
 * given, including one that makes little sense, such as a final margin
 * larger than the window.
 */
const readSettings = (
  options: PluginOptions,
): { settings: CompactionSettings; problems: SettingProblem[] } => {
  // The setting gives each threshold as the percentage of context remaining
  // before the limit, the same direction `finalTokens` is measured in.
  //
  // Both options are numbers, but the manifest declares both as strings,
  // because a `userConfig` field can hold neither a list of numbers nor
  // "a number or the word auto". As `claude plugin validate` reported on
  // Claude Code 2.1.325:
  //
  // - A field's `type` is exactly one of "string", "number", "boolean",
  //   "directory" or "file"; "array", an `items` key, and every spelling of
  //   a union that was tried (a list of types, "number|string", `anyOf`) are
  //   refused.
  // - `"type": "number"` with `"multiple": true` is accepted as a
  //   declaration, but a list of numbers as its `default` is refused
  //   ("Invalid input").
  // - `PluginOptions`, the type of `options`, has `readonly string[]` as its
  //   only list value.
  //
  // So the conversion to numbers, and the check that an entry is one, are
  // made here and not by the settings interface, which is why an entry that
  // fails the check is reported to the person (`reportSettingProblems`). A
  // number is still accepted for the token count, because a settings file
  // written while that option was declared a number holds one. If a later
  // release adds a list-of-numbers or a union type, declare the fields with
  // it and drop the conversion.
  const problems: SettingProblem[] = []
  const isPercent = (percent: number): boolean =>
    Number.isFinite(percent) && percent > 0 && percent < 100
  const percents = entriesOf(options.remainingContextNoticePercents)
  const remaining = percents.map(Number).filter(isPercent)
  for (const entry of percents.filter(entry => !isPercent(Number(entry)))) {
    problems.push({
      option: 'remainingContextNoticePercents',
      entry,
      expected: 'percentages above 0 and below 100, separated by commas',
      inForce:
        remaining.length > 0
          ? 'The other entries are in force.'
          : 'The default thresholds are in force.',
    })
  }
  // Most remaining first, so the fractions used come out ascending.
  const noticeAt = [...new Set(remaining)].sort((a, b) => b - a).map(p => 1 - p / 100)
  // One entry is a count; more than one is not a count, so the default holds.
  const counts = entriesOf(options.remainingContextFinalNoticeTokens)
  // Digits only: `Number` would also take a fraction, an exponent, or a
  // hexadecimal form, none of which is the whole number the setting asks for.
  const finalTokens =
    counts.length === 1 && /^\d+$/.test(counts[0]!) ? Number(counts[0]) : Number.NaN
  const isCount = Number.isFinite(finalTokens) && finalTokens > 0
  if (counts.length > 0 && !isCount) {
    problems.push({
      option: 'remainingContextFinalNoticeTokens',
      // Shown joined as it was most likely typed, e.g., "30,000".
      entry: counts.join(','),
      expected: 'one whole number of tokens above 0, written without separators',
      inForce: 'The default count is in force.',
    })
  }

  return {
    settings: {
      noticeAt: noticeAt.length > 0 ? noticeAt : DEFAULT_SETTINGS.noticeAt,
      finalTokens: isCount ? finalTokens : DEFAULT_SETTINGS.finalTokens,
    },
    problems,
  }
}

/** The settings `options` asks for; see `readSettings`. */
export const settingsOf = (options: PluginOptions): CompactionSettings =>
  readSettings(options).settings

/** The entries of `options` that could not be used; see `readSettings`. */
export const settingProblemsOf = (options: PluginOptions): SettingProblem[] =>
  readSettings(options).problems

// Set once per load by `configure`; the functions the hooks module calls
// read it, so the settings are parsed in one place.
let settings = DEFAULT_SETTINGS
let settingProblems: SettingProblem[] = []

/** Puts the person's settings in force for this load of the module. */
export function configure(options: PluginOptions): void {
  const read = readSettings(options)
  settings = read.settings
  settingProblems = read.problems
}

/**
 * Tells the person which setting entries this load could not use. Called at
 * `session.start`, because `configure` runs before there is an interface to
 * log to. Without it a mistyped entry falls back to a default unnoticed.
 */
export function reportSettingProblems($: EngineInterface): void {
  for (const problem of settingProblems) log($, settingProblemLogLine(problem))
}

/**
 * Reads the context window and the auto-compaction threshold from the
 * engine. Called when the session starts and at each `session.measure`
 * event, which the engine raises after a main-thread turn and when a
 * rate-limit figure moves, since either can change during a session (a model
 * switch, a settings change).
 */
export async function measure($: EngineInterface): Promise<void> {
  // `summary` estimates the breakdown locally; it is asked for to learn the
  // auto-compaction threshold, which the plain call leaves out.
  const usage = await $.session.usage({ breakdown: 'summary' })
  const breakdown = usage.context.breakdown

  const held = await update($, context, (current): ContextFill => ({
    // The engine's figure is the last response's input side. The figure
    // kept from `afterStep` also counts that response's output, so it is
    // the one retained when both exist.
    tokens: current?.tokens ?? usage.context.tokens,
    unmeasured: current?.unmeasured,
    window: usage.context.window,
    // An answer without a breakdown doesn't say whether auto-compaction is on, so
    // the threshold already held is kept: reading it as "off" would move the
    // limit to the window's end and delay every notice.
    compactAt:
      breakdown === undefined
        ? current?.compactAt
        : breakdown.isAutoCompactEnabled
          ? breakdown.autoCompactThreshold
          : undefined,
    // Known once any answer has carried a breakdown; until then the final
    // notice says that it is not known, and does not say "off".
    isAutoCompactKnown: breakdown !== undefined || current?.isAutoCompactKnown === true,
    isJustCompacted: current?.isJustCompacted,
  }))
  if (held === null) return

  // A notice level counts thresholds passed, so it holds only for the limit
  // and the settings it was counted against. When either changes (a model
  // with another window, a changed setting loaded by a reload), the noticed
  // level is lowered to the level the conversation's size has on the new
  // scale: left as it was, a level reached on a small window would silence
  // every threshold of a larger one, the final notice included.
  const signature = [limitOf(held), settings.noticeAt.join(','), settings.finalTokens].join('|')
  let isChanged = false
  await update($, scale, previous => {
    isChanged = previous !== signature

    return signature
  })
  if (isChanged && held.tokens !== undefined) {
    const level = levelOf(held.tokens + (held.unmeasured ?? 0), limitOf(held), settings)
    await update($, noticeLevel, noticed => Math.min(noticed, level))
  }
}

/**
 * Runs `measure` when a measurement hasn't succeeded yet, so that a first
 * measurement that failed at the session's start is made up at the next
 * response or tool result instead of leaving the notices off.
 */
async function ensureMeasured($: EngineInterface): Promise<void> {
  if ((await read($, context)) === null) await measure($)
}

/**
 * Records that the conversation was replaced by a shorter one (a compaction
 * of the main conversation, or a /clear or /resume): its size is unknown
 * until the next response, and every threshold is ahead of it again.
 *
 * `isCompaction` says the replacement was a compaction. The first response
 * after one then sets the level already reached as noticed, without a
 * notice (`afterStep`). A /clear or a /resume does not: the conversation
 * that follows a /resume can be a long one, where a notice is useful.
 */
export async function conversationReplaced(
  $: EngineInterface,
  isCompaction = false,
): Promise<void> {
  await update($, context, current =>
    current === null
      ? current
      : {
          ...current,
          tokens: undefined,
          unmeasured: undefined,
          isJustCompacted: isCompaction ? true : undefined,
        },
  )
  await update($, noticeLevel, () => 0)
  // After a /clear or a /resume, a notice still owed is about a request made
  // in a conversation that is gone. After a compaction the model that made
  // the request is still at work on the same task and has not been told, so
  // the notice stays owed.
  if (!isCompaction) await update($, owedNotice, () => null)
}

/**
 * The conversation's size after a response: everything the request was
 * answered over plus what it generated, which the next request sends back.
 *
 * It is that size only for a response made by one request. The engine's
 * types say the counts are "summed over the call's responses when it made
 * several", which a response does when the API runs a tool inside it (e.g.,
 * the advisor): each of its requests is answered over the conversation
 * again, so the sum counts the conversation once per request. `afterStep`
 * does not size the conversation from such a response.
 */
export const tokensAfter = (usage: ModelUsage): number =>
  usage.input_tokens +
  usage.cache_read_input_tokens +
  usage.cache_creation_input_tokens +
  usage.output_tokens

/** The size at which the engine compacts by itself, or the window when it never does. */
export const limitOf = (context: ContextFill): number =>
  context.compactAt !== undefined && context.compactAt < context.window
    ? context.compactAt
    : context.window

/**
 * The notice level a conversation of `tokens` has reached: one for each
 * ordinary threshold passed, or `finalLevelOf` once it is within
 * `finalTokens` of the limit. The final level is above every ordinary one
 * wherever those are set, so the final notice is always the last sent.
 */
export const levelOf = (tokens: number, limit: number, from: CompactionSettings): number =>
  tokens >= limit - from.finalTokens
    ? finalLevelOf(from)
    : from.noticeAt.filter(fraction => tokens >= fraction * limit).length

/** The level that only the final threshold reaches. */
export const finalLevelOf = (from: CompactionSettings): number => from.noticeAt.length + 1

/**
 * How many characters of a tool result are counted as one token.
 *
 * The engine gives a hook a tool result's text and not its token count,
 * so the count is estimated from the text's length, which JavaScript counts
 * in UTF-16 code units: a character outside the Basic Multilingual Plane
 * counts as two. The ratio is a choice
 * informed by published measurements, not a measurement of this mod's own.
 *
 * Why 2.5. Claude Code is used mostly on code, so tool results are mostly
 * code, logs, traces and structured data, which take fewer characters per
 * token than prose. Measurements made with Anthropic's token-counting
 * endpoint on Claude Opus 4.7, which uses the current tokenizer,
 * put most such content between about 2.3 and 3.1 characters per token: e.g.,
 * a git log at 2.33, a Python stack trace at 2.42, terminal output at 2.62,
 * TypeScript at 2.69, Python at 2.86, a code diff and dense JSON at 3.06.
 * English prose measured 3.3 to 3.6. Seven samples of what a Claude Code
 * session sends came to 2.68 together (their characters summed and divided by
 * their tokens summed). Anthropic's glossary gives about 3.5
 * English characters per token on earlier models and about 30 percent more
 * tokens on Claude 4.7 and later, which is about 2.7.
 *
 * 2.5 is a little under that average on purpose, so that the estimate of
 * tool output taken together comes out slightly over the true count. The two
 * directions of error do not cost the same. An estimate under the true count
 * delays a notice until the next response, and where that response ends the
 * turn, the model reads the notice only with the next prompt. An estimate
 * over the true count sends a notice early, by no more than the error on the
 * tool results since the last response: the next response reports the exact
 * size and the estimate is discarded, so the error does not accumulate and
 * does not make the window smaller for the rest of the session. At 2.5 the
 * largest overestimate among the measured kinds is English prose and
 * documentation at about 3.6, counted about 44 percent over for that one
 * batch of results. Every kind under 2.5 still comes out under: a git log
 * and a stack trace slightly (by about 7 and 3 percent), the densest kinds of
 * code and data measured, shell scripts and numeric CSV at about 1.8, by nearly 30 percent,
 * and prose in some other languages, e.g., German at 2.1 by about 16 percent
 * and Chinese or Japanese at about 1 by about 60 percent.
 *
 * Whether models after Opus 4.7 tokenize the same way is taken from the
 * glossary's "Claude 4.7 and later models" and has not been measured here.
 * A change of tokenizer is a reason to choose this value again.
 *
 * Sources, read on 2026-11-15:
 * - Anthropic. Glossary, "Tokens".
 *   https://platform.claude.com/docs/en/about-claude/glossary
 * - Abhishek Ray. 2026. I Measured Claude 4.7's New Tokenizer. Here's What
 *   It Costs You. Claude Code Camp (April 16, 2026).
 *   https://www.claudecodecamp.com/p/i-measured-claude-4-7-s-new-tokenizer-here-s-what-it-costs-you
 *   The article states the ratios for English prose (3.60) and TypeScript
 *   (2.69). The other per-sample ratios above, and the 2.68 for the seven
 *   samples, are its character counts divided by its Opus 4.7 token counts.
 * - Masashi Tomooka. 2026. Claude Opus 4.6 vs 4.7 Tokenizer Benchmark.
 *   https://github.com/tmokmss/token-opus47-benchmark (English prose 3.30, German 2.10, Chinese 0.92, Japanese 0.98).
 */
const CHARS_PER_TOKEN = 2.5

/** The estimated token count of `text` as a tool result. */
export const estimatedTokensOf = (text: string): number => Math.ceil(text.length / CHARS_PER_TOKEN)

/**
 * Raises the noticed level to `level` when it is above the level already
 * noticed, and answers whether it did. The comparison and the write are one
 * update, so of several tool results that finish together and pass the same
 * threshold, one sends the notice.
 */
async function claimLevel($: EngineInterface, level: number): Promise<boolean> {
  let isClaimed = false
  await update($, noticeLevel, noticed => {
    isClaimed = level > noticed

    return isClaimed ? level : noticed
  })

  return isClaimed
}

/** The notice for `level`, and the line that tells the person it was sent. */
function noticeFor(
  level: number,
  tokens: number,
  held: ContextFill,
  isTurnEnding: boolean,
): { text: string; logLine: string } {
  const limit = limitOf(held)
  const isFinal = level === finalLevelOf(settings)
  // The room stated is the room there is. A response or a tool result can
  // carry the conversation well inside the margin in one step, and the
  // configured margin would then overstate what is left.
  const tokensLeft = Math.max(0, limit - tokens)

  return {
    text: isFinal
      ? finalNoticeText(
          Math.min(settings.finalTokens, tokensLeft),
          held.compactAt !== undefined ? 'on' : held.isAutoCompactKnown === true ? 'off' : 'unknown',
        )
      : NOTICE_TEXT,
    // The model's notice leaves the figures out so that the model is not
    // shown how much room is left; this line is for the person, is not sent
    // to the model, and can state them.
    logLine: noticeLogLine({
      isFinal,
      percentLeft: Math.max(0, Math.round((1 - tokens / limit) * 100)),
      tokensLeft,
      isTurnEnding,
    }),
  }
}

/**
 * Counts a main-thread tool result toward the conversation's size, and
 * answers the notice to send with that result when the size has passed a
 * threshold not yet noticed in this window.
 *
 * A response reports the conversation's size as of its own request, so a
 * tool result is first counted by the response after it. Where that response
 * ends the turn, a notice appended then is read only with the next prompt.
 * Estimating each result as it arrives lets the notice go to the model with
 * the result, in the same turn.
 *
 * `resultText` is the result as the model reads it, with any text other
 * hooks attached to it. Images in a result and the reminders the engine adds
 * are not in it, so they are counted by the next response and not here. A
 * result made mostly of those can pass a threshold, or the limit itself,
 * before any notice is sent.
 */
export async function afterToolResult(
  $: EngineInterface,
  resultText: string,
): Promise<string | undefined> {
  await ensureMeasured($)
  const added = estimatedTokensOf(resultText)
  const held = await update($, context, current =>
    // An estimate is added to an exact figure, and there isn't one yet.
    current === null || current.tokens === undefined
      ? current
      : { ...current, unmeasured: (current.unmeasured ?? 0) + added },
  )
  if (held === null || held.tokens === undefined) return undefined
  // The first response after a compaction settles which thresholds the
  // summary is already past (`afterStep`); until it has, a notice is not sent.
  if (held.isJustCompacted === true) return undefined
  // A compaction already asked for doesn't need a further notice.
  if ((await read($, pending)) !== null) return undefined

  const tokens = held.tokens + (held.unmeasured ?? 0)
  const level = levelOf(tokens, limitOf(held), settings)
  if (!(await claimLevel($, level))) return undefined

  const notice = noticeFor(level, tokens, held, false)
  log($, notice.logLine)

  return notice.text
}

/**
 * Records the conversation's size after a main-thread response and appends a
 * notice when it has passed a threshold not yet noticed in this window.
 *
 * `isTurnEnding` says whether that response didn't call any tools, which ends its
 * turn. It decides only what the person is told about when the model will
 * read the notice: a turn that goes on reads it at its next request, and one
 * that has ended reads it with the next prompt.
 *
 * `isSummed` says the response made more than one request, because the API
 * ran a tool inside it (`serverToolUses` on the step's result). Its usage is
 * then a sum over those requests and not the conversation's size
 * (`tokensAfter`): taken as the size, it counted a conversation of about
 * 230,000 tokens as 469,717 and sent a notice for a threshold that was not
 * reached (observed on 2026-11-15, after an advisor call). The size is
 * instead carried forward: the figure already held, with the estimate of
 * the tool results since, plus what this response generated. The result of
 * the tool the API ran is left out, because the step's result does not carry
 * it, so the figure is slightly under until the next response made by one
 * request reports the size exactly.
 */
export async function afterStep(
  $: EngineInterface,
  usage: ModelUsage,
  isTurnEnding: boolean,
  isSummed = false,
): Promise<void> {
  await ensureMeasured($)
  let previous: number | undefined
  let isFirstAfterCompaction = false
  let isSummedAfterCompaction = false
  const held = await update($, context, current => {
    previous = current?.tokens
    isFirstAfterCompaction = false
    isSummedAfterCompaction = false
    if (current === null) return current
    if (isSummed) {
      isSummedAfterCompaction = current.isJustCompacted === true
      // Without a figure to carry forward, the size stays unknown until the
      // next response made by one request.
      return current.tokens === undefined
        ? current
        : { ...current, tokens: current.tokens + usage.output_tokens }
    }
    isFirstAfterCompaction = current.isJustCompacted === true

    // The exact figure counts every tool result estimated since the last
    // response, so the estimate is cleared.
    return {
      ...current,
      tokens: tokensAfter(usage),
      unmeasured: undefined,
      isJustCompacted: undefined,
    }
  })
  await deliverOwed($)
  // A size can't be judged until `measure` has run once, or without a figure.
  if (held === null || held.tokens === undefined) return
  // A summed response right after a compaction is not judged: which
  // thresholds the summary is already past is settled by the exact figure
  // that follows, and a notice sent here would be the one that figure
  // withholds. A figure can be held by then, because a measurement between
  // the compaction and this response fills one in (`measure`).
  if (isSummedAfterCompaction) return
  // After a summed response the estimate of the tool results since the last
  // exact figure is still part of the size.
  const tokens = held.tokens + (isSummed ? (held.unmeasured ?? 0) : 0)

  const level = levelOf(tokens, limitOf(held), settings)
  if (isFirstAfterCompaction) {
    // What the conversation holds right after a compaction is the summary
    // and what the engine restores, and a second compaction would not make
    // that smaller. A notice for a threshold it is already past could only
    // lead the model to compact again without having worked, at every
    // compaction, so the level is taken as noticed and the person is told.
    // Thresholds above it still send their notices as the work goes on.
    await update($, noticeLevel, () => level)
    if (level > 0) {
      log(
        $,
        pastThresholdAfterCompactionLogLine(
          Math.max(0, Math.round((1 - tokens / limitOf(held)) * 100)),
        ),
      )
    }

    return
  }
  const noticed = await read($, noticeLevel)
  if (level < noticed) {
    // The conversation shrank, so the thresholds above its new size are
    // ahead of it again. A compaction and a /clear are seen as they happen
    // (`conversationReplaced`); this covers what is not, such as a rewind.
    //
    // Shrinking is judged between two exact figures. A level noticed on an
    // estimate that came out over the true count is also above the level of
    // the exact figure that follows it, and lowering the noticed level then
    // would send the same notice a second time.
    if (previous === undefined || tokens < previous) await update($, noticeLevel, () => level)

    return
  }
  // A compaction already asked for doesn't need a further notice.
  if ((await read($, pending)) !== null) return
  if (!(await claimLevel($, level))) return

  const notice = noticeFor(level, tokens, held, isTurnEnding)
  let refusal: string | undefined
  try {
    refusal = await appendNotice($, notice.text)
  } catch (error) {
    // The level was claimed for a notice that was not sent, so it is given
    // back and a later response sends the notice.
    await update($, noticeLevel, current => Math.min(current, noticed))
    throw error
  }
  if (refusal !== undefined) {
    await update($, noticeLevel, current => Math.min(current, noticed))
    throw new Error(`the notice was refused: ${refusal}`)
  }
  log($, notice.logLine)
}

/**
 * Appends `text` to the main conversation as a row the model reads, and
 * answers the reason when the row was refused. The engine answers a refusal
 * from a plugin above and does not reject, so a caller that only caught a
 * rejection would count a refused notice as sent.
 */
async function appendNotice($: EngineInterface, text: string): Promise<string | undefined> {
  const stored: unknown = await $.session.append({
    message: { type: 'user', content: [{ type: 'text', text }] },
  })
  const refusal = (stored as { deny?: unknown } | null | undefined)?.deny

  return refusal === undefined ? undefined : String(refusal)
}

/**
 * Carries out a request that is due: compacts under the model's
 * instructions, then submits its continuation.
 *
 * It is called at the events at which a compaction can run, and does
 * nothing when a request isn't due: the end of the turn that asked
 * (`afterTurn`), the measurement the engine raises after a main-thread
 * turn, and the session's start after a reload. The mod doesn't wait or
 * retry on a clock. The request made in a turn becomes due when that turn
 * has ended with an answer, and is carried out there, in the `turn.complete`
 * hook, once the engine's own handling of the turn's end has resolved: the
 * engine accepts `$.session.compact` at that point (observed on 2.1.325).
 * The measurement is a second occasion and not the first, because a request
 * that depended on it alone was once left standing for 52 minutes without a
 * compaction and without a word to the model or the person, until the next
 * prompt dropped it (2026-11-15; which of the two events failed to do its
 * part was not established).
 *
 * The request is read from state here, so that whatever dropped it in the
 * meantime (a prompt, a new turn, a /clear) stops the attempt: a compaction
 * that ran after a later prompt would replace a conversation its notes and
 * continuation were not written for.
 *
 * One attempt is made. A prompt is submitted whether or not the compaction
 * ran, because the model ended its turn expecting to be resumed and the
 * person may not be present. After a compaction it is the model's
 * continuation, led by the note paths. When the compaction did not run, it
 * is a notice that says so and nothing else: the continuation was written
 * for a reader who has only the summary, and the conversation is still
 * whole. When another source compacted the conversation after the request
 * was made, that compaction stands for this one, and the continuation is
 * submitted.
 */
export async function runDue($: EngineInterface): Promise<void> {
  try {
    // Claimed in one update, so of two events that find the request due,
    // one carries it out.
    let asked: PendingCompaction | null = null
    await update($, pending, current => {
      asked = current !== null && current.phase === 'waiting' ? current : null

      return current !== null && current.phase === 'waiting'
        ? { ...current, phase: 'compacting' as const }
        : current
    })
    if (asked === null) return
    const { instructions, continuation, notes, isCompacted } = asked as PendingCompaction

    // The cause is named by how the engine answered, not by what its text
    // says: a skip is a refusal by the engine or a plugin, a rejection is
    // the engine being unable to start or finish. The text goes to the
    // person's line only.
    let failure: { cause: 'declined' | 'not-started'; detail: string } | undefined
    if (isCompacted !== true) {
      try {
        const skip = (await $.session.compact({ instructions })).skip
        if (skip !== undefined) failure = { cause: 'declined', detail: skip }
      } catch (error) {
        failure = {
          cause: 'not-started',
          detail: error instanceof Error ? error.message : String(error),
        }
      }

      if (failure === undefined) {
        // Recorded here as well as by this plugin's `session.compact` hook:
        // the engine's types say a plugin's call skips "the calling hook
        // alone", which leaves open whether that hook sees this compaction,
        // and recording it twice changes nothing. A failure to record it is
        // not allowed to cost the continuation.
        try {
          await conversationReplaced($, true)
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error)
          log($, failureLogLine('recording a compaction', reason))
        }
      }
    }

    // Taken out of state as the last thing before the prompt is submitted,
    // so that a /clear up to that point is seen. When the request is
    // already gone, a /clear or a reload dropped it while the engine
    // compacted, and nothing is submitted.
    let isStanding = false
    await update($, pending, current => {
      isStanding = current !== null

      return null
    })
    if (!isStanding) return

    if (failure !== undefined) {
      const { cause, detail } = failure
      const notice = endedNotice(cause)
      await submitOrAppend($, notice, notice, {
        submitted: endedLogLine(cause, detail),
        notSubmitted: reason => endedNotSubmittedLogLine(cause, detail, reason),
      })

      return
    }
    await submitContinuation(
      $,
      notes,
      continuation,
      isCompacted === true ? COMPACTED_ELSEWHERE_LOG_LINE : COMPACTED_LOG_LINE,
    )
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error)
    await abandon($, reason)
  }
}

/**
 * Submits the model's continuation after a compaction, led by the note
 * paths. The paths are put ahead of the continuation by the mod, so the
 * resumed model is told where they are whether or not the summary or its
 * own continuation mentions them.
 */
async function submitContinuation(
  $: EngineInterface,
  notes: readonly string[],
  continuation: string,
  submittedLine: string,
): Promise<void> {
  await submitOrAppend(
    $,
    [notesLead(notes), continuation].join('\n\n'),
    resumeFallbackNotice(notes, continuation),
    { submitted: submittedLine, notSubmitted: resumeNotSubmittedLogLine },
  )
}

/**
 * Submits `text` as a prompt, which starts a turn once the session is idle.
 * When the submit fails, it is tried once more, and when that fails too,
 * `fallback` is appended to the conversation as a notice and the person is
 * told that any message resumes the work.
 *
 * The person's line is logged once the outcome is known, because each line
 * says how Claude was told: `lines.submitted` when the prompt entered, and
 * `lines.notSubmitted`, given the reason, when it did not.
 *
 * A submit fails by rejecting, or by resolving to `{ drop }` when a hook or
 * the engine did not let the prompt in. Without the check a prompt that did
 * not enter would leave the session idle with nothing said, after a
 * compaction that left the model only the summary. The second try is not
 * timed: it is made at once, for a failure that does not repeat.
 */
async function submitOrAppend(
  $: EngineInterface,
  text: string,
  fallback: string,
  lines: { submitted: string; notSubmitted: (reason: string) => string },
): Promise<void> {
  let reason = ''
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const entered: unknown = await $.prompt.submit({ text })
      const drop = (entered as { drop?: unknown } | null | undefined)?.drop
      if (drop === undefined) {
        log($, lines.submitted)

        return
      }
      reason = String(drop)
    } catch (error) {
      reason = error instanceof Error ? error.message : String(error)
    }
  }
  log($, lines.notSubmitted(reason))
  await tellByNotice($, fallback)
}

/**
 * Records that the main conversation was compacted by a source other than
 * this mod: the engine's auto-compaction, the person's /compact, or another
 * plugin's call. When the
 * model had asked for a compaction before it, that compaction stands for the
 * one asked for, so the conversation is not compacted a second time.
 *
 * A request whose turn is still running is marked, and its continuation
 * follows when the turn ends with an answer. A request that was already due
 * has its continuation submitted here. A request the mod is itself
 * compacting for is left alone: the compaction seen is then the mod's own.
 */
export async function compactedElsewhere($: EngineInterface): Promise<void> {
  let due: PendingCompaction | null = null
  await update($, pending, current => {
    due = current !== null && current.phase === 'waiting' ? current : null
    if (current === null || current.phase === 'compacting') return current

    return current.phase === 'waiting' ? null : { ...current, isCompacted: true }
  })
  await conversationReplaced($, true)
  if (due === null) return

  const { notes, continuation } = due as PendingCompaction
  await submitContinuation($, notes, continuation, COMPACTED_ELSEWHERE_LOG_LINE)
}

/**
 * Drops a request that is due when a main-thread turn starts before it was
 * carried out, and tells the model. The turn was started by a prompt the
 * mod saw before the request was made (e.g., one typed while the asking
 * turn ran, which the engine holds until that turn ends), so the prompt
 * did not cancel the request when it arrived; its turn adds to the
 * conversation what the notes do not cover. `afterTurn` leaves a request
 * due, without compacting, for exactly this case.
 */
export async function turnStarted($: EngineInterface): Promise<void> {
  let due: PendingCompaction | null = null
  await update($, pending, current => {
    due = current !== null && current.phase === 'waiting' ? current : null

    return due === null ? current : null
  })
  if (due === null) return

  const request = due as PendingCompaction
  log($, endedLogLine('turn-start', undefined, request.isCompacted === true))
  await tellEnded($, 'turn-start', request)
}

/**
 * Removes a request the mod failed to carry out, and tells the model. Left
 * in state, the request would hold back every later notice. When the
 * request has already left state, the failure came after it was settled:
 * there is nothing to remove, and the person is told what failed.
 */
async function abandon($: EngineInterface, reason: string): Promise<void> {
  try {
    let left: PendingCompaction | null = null
    await update($, pending, current => {
      left = current

      return null
    })
    if (left !== null) {
      // Whether the conversation was compacted is not known here, so the
      // notice says so and lists the note files in either case.
      log($, endedLogLine('mod-failure', reason))
      await tellEnded($, 'mod-failure', { notes: (left as PendingCompaction).notes })
    } else {
      log($, failureLogLine('resuming after a compaction', reason))
    }
  } catch {
    // The state cannot be reached, so there is nothing further to try.
  }
}

/** Logs a line for the person; a failure to log is not allowed to matter. */
function log($: EngineInterface, text: string): void {
  try {
    $.ui.log(text)
  } catch {
    // A failed report can't be reported anywhere.
  }
}

/**
 * Declares the compaction tool. Called at `session.start`, because a
 * registration rejects before the session binds.
 */
export async function registerTool($: EngineInterface): Promise<void> {
  // Listed in the prompt's tool list from the start: behind ToolSearch the
  // model would not have the tool's full description until it loaded it.
  await $.tool.register({
    name: TOOL_NAME,
    description: TOOL_DESCRIPTION,
    inputSchema: TOOL_INPUT_SCHEMA,
    isDeferred: false,
  })
}

/**
 * Records that a prompt was submitted while the main-thread turn `turnId`
 * ran. The engine either delivers such a prompt into that turn or holds it
 * until the turn ends, and its event does not say which, so `afterTurn`
 * does not compact at the end of that turn.
 */
export async function promptedDuring($: EngineInterface, turnId: string): Promise<void> {
  await update($, promptedTurn, () => turnId)
}

/**
 * Makes a request the model made during the main-thread turn that just
 * ended as `reason` due, or drops it when that turn did not end in an
 * answer, and carries a due request out (`runDue`).
 *
 * It is called from the `turn.complete` hook after the engine's own
 * handling. `isHandled` says that handling resolved; when it rejected, the
 * request is made due and left for the measurement that follows the turn,
 * because what state the engine is in is then not known.
 *
 * A request is also left for that measurement when a prompt was submitted
 * while the turn `turnId` ran and before the request was made (one
 * submitted after it cancels the request). Such a prompt may be held to
 * start the next turn; that turn then starts first and drops the request
 * (`turnStarted`), where a compaction here would put the prompt on a
 * summary whose notes were not written for it.
 */
export async function afterTurn(
  $: EngineInterface,
  reason: string,
  turnId?: string,
  isHandled = true,
): Promise<void> {
  let asked: PendingCompaction | null = null
  await update($, pending, current => {
    // Only a request made in the turn that just ended is this turn's to
    // settle; one already waiting belongs to an earlier turn's end.
    asked = current !== null && current.phase === 'turn' ? current : null
    if (asked === null) return current

    return reason === 'answer' ? { ...current!, phase: 'waiting' as const } : null
  })
  if (asked === null) return

  if (reason !== 'answer') {
    // An interrupted or failed turn is the person's or the engine's stop;
    // resuming by itself would override it. The model reads the notice with
    // the next prompt, and it names which of those the turn's end was.
    const cause = turnEndCause(reason)
    const request = asked as PendingCompaction
    log($, endedLogLine(cause, undefined, request.isCompacted === true))
    await tellEnded($, cause, request)

    return
  }
  if (!isHandled) return
  if (turnId !== undefined && (await read($, promptedTurn)) === turnId) return
  await runDue($)
}

/**
 * Carries out a request that was due when the module was reloaded. A reload
 * keeps the module's state, and the events that would have carried the
 * request out (the turn's end, and the measurement after it) may already
 * have passed, so without this the request could
 * stay in state and hold every later notice back until the next prompt.
 */
export async function resumePending($: EngineInterface): Promise<void> {
  let dropped: PendingCompaction | null = null
  await update($, pending, current => {
    // A request that a prompt overtook while the engine was compacting is
    // not started again: whether or not that compaction finished, a new one
    // would replace a conversation that holds a prompt the notes were not
    // written for.
    dropped = current !== null && current.isOvertaken === true ? current : null
    if (dropped !== null) return null

    return current !== null && current.phase === 'compacting'
      ? { ...current, phase: 'waiting' as const }
      : current
  })
  if (dropped !== null) {
    log($, endedLogLine('reload'))
    await tellEnded($, 'reload', { notes: (dropped as PendingCompaction).notes })

    return
  }
  await runDue($)
}

/**
 * Tells the model that its request ended without a compaction, by a notice
 * appended to the conversation, which it reads at its next request. Used
 * where the end doesn't have a tool result to carry the news. `request` is
 * the request that ended, from which the notice takes the note files and
 * whether another source compacted the conversation while it stood.
 */
export async function tellEnded(
  $: EngineInterface,
  cause: Exclude<EndCause, 'replaced'>,
  request?: EndedRequest,
): Promise<void> {
  await tellByNotice($, endedNotice(cause, request))
}

/**
 * Appends `text` to the conversation as a notice. When the notice is refused
 * or cannot be appended, its text is kept in state as owed, and goes to the
 * model by the next route that opens: with the next main-thread tool result
 * (`takeOwed`), or appended after the next response (`deliverOwed`). The
 * model is then never left untold for longer than it takes one of those to
 * happen.
 */
async function tellByNotice($: EngineInterface, text: string): Promise<void> {
  let isTold = false
  try {
    isTold = (await appendNotice($, text)) === undefined
  } catch {
    // Handled below, as a refusal is.
  }
  if (!isTold) await update($, owedNotice, () => text)
}

/**
 * Takes the owed notice out of state and answers it, for a caller that will
 * send it with a tool result; undefined when nothing is owed.
 */
export async function takeOwed($: EngineInterface): Promise<string | undefined> {
  let owed: string | null = null
  await update($, owedNotice, current => {
    owed = current

    return null
  })

  return owed ?? undefined
}

/** Appends the owed notice, and keeps it owed when that fails again. */
async function deliverOwed($: EngineInterface): Promise<void> {
  const owed = await takeOwed($)
  if (owed === undefined) return
  let isTold = false
  try {
    isTold = (await appendNotice($, owed)) === undefined
  } catch {
    // Handled below, as a refusal is.
  }
  if (!isTold) await update($, owedNotice, current => current ?? owed)
}

/**
 * Cancels a compaction the model asked for, and answers the request that
 * was canceled, or null when there was none. `cause` selects the line the
 * person is shown.
 *
 * Called for whatever makes the request out of date before it runs: a tool
 * call after the tool accepted it, a submitted prompt, a /clear. The notes
 * were checked when the tool was called, and each of these can add to the
 * conversation something they do not reflect. A submitted prompt is any the
 * session receives, not only the person's: e.g., a background task's
 * notification is one. With `isKeptWhileCompacting`, a request the engine
 * has begun compacting for is kept and marked as overtaken.
 *
 * Telling the model is the caller's part: with the result of the tool call
 * that canceled the request, or by `tellEnded` for a prompt. After a
 * /clear a conversation that holds the request isn't left, and the model is
 * not told.
 */
export async function cancelPending(
  $: EngineInterface,
  cause: EndCause,
  isKeptWhileCompacting = false,
): Promise<PendingCompaction | null> {
  let canceled: PendingCompaction | null = null
  await update($, pending, current => {
    // Once the engine is compacting, the conversation is already being
    // replaced, and dropping the request would only drop the continuation
    // and the note paths that follow it. A prompt that arrives then is
    // answered first and the continuation after it. The request is marked,
    // so that a compaction that fails is not tried again after that prompt.
    // The flag is set on every path, because the engine applies this
    // function again when the stored value changed under it.
    if (isKeptWhileCompacting && current !== null && current.phase === 'compacting') {
      canceled = null

      return { ...current, isOvertaken: true }
    }
    canceled = current

    return null
  })
  if (canceled !== null) {
    log($, endedLogLine(cause, undefined, (canceled as PendingCompaction).isCompacted === true))
  }

  return canceled
}

/**
 * Records that something happened in the main conversation that the notes
 * may need to reflect: a tool call other than the compaction tool's own, or
 * a submitted prompt.
 */
export async function markEvent($: EngineInterface): Promise<void> {
  const now = await $.clock.now()
  // The later of the two, so that of calls that start together the last to
  // be recorded cannot move the time back.
  await update($, lastEventAt, last => Math.max(last, now))
  await update($, eventCount, count => count + 1)
}

/** The coarsest modification-time step allowed for, in milliseconds. */
const COARSE_MTIME_MS = 2000

/**
 * Checks the note files the model lists, and answers what is wrong with
 * them, or, when they are sound, each file's absolute path in the order listed.
 *
 * Each file has to exist and hold something, and the newest of them has to
 * have been written no earlier than the last event `markEvent` recorded.
 * Writing a note is itself a tool call, recorded as it starts, so a note
 * written by the last call before this one passes, and a tool call or
 * prompt that starts after that write fails.
 *
 * What the comparison cannot see: a tool call that started before the note
 * was written and finished after it, a tool the API runs itself (which
 * doesn't raise a `tool.call`), an event in the two seconds allowed for a
 * file system with coarse times, and a modification time set by hand.
 * Recording a call's end as well would refuse every request, since the call that writes the note ends
 * after the time the file records. The rule is about order, not elapsed time,
 * because the time between writing a note and calling the tool is mostly
 * the model composing the call, which varies with the model and its effort.
 *
 * The check is of what a file system can show. Whether the notes are good
 * notes is left to the instructions.
 */
export async function checkNotes(
  $: EngineInterface,
  paths: readonly string[],
): Promise<{ problem: string } | { resolved: string[]; events: number }> {
  let newest = 0
  const resolved: string[] = []
  for (const path of paths) {
    let stat
    try {
      // `resolve` also answers the file's absolute path, which is what is
      // handed back after the compaction: a path relative to this session's
      // directory would point elsewhere for a reader started in another.
      stat = await $.fs.stat(path, { resolve: true })
    } catch {
      // `$.fs.stat` rejects for a path that cannot be read, which for a note
      // the model says it wrote means the file is not there.
      return { problem: noteProblemReply(path, 'it does not exist or cannot be read') }
    }
    if (stat.kind !== 'file') return { problem: noteProblemReply(path, 'it is not a file') }
    if (stat.size === 0) return { problem: noteProblemReply(path, 'it is empty') }
    // A time that falls on a whole second is taken as coming from a file
    // system that doesn't record finer times (some record whole seconds,
    // some every other one). Such a time can be up to two seconds before the
    // write it records, which would put every note before the call that
    // wrote it and refuse every request, so that much is allowed for. The
    // allowance is each file's own, so that an older note with a finer time
    // does not take it from the newest.
    const allowed = stat.mtimeMs % 1000 === 0 ? COARSE_MTIME_MS : 0
    newest = Math.max(newest, stat.mtimeMs + allowed)
    resolved.push(stat.realPath ?? (await absolutePathOf($, path)))
  }

  // The count is read before the time: an event recorded between the two
  // reads then shows as a later count in the caller's second look.
  const events = await read($, eventCount)

  return newest >= (await read($, lastEventAt))
    ? { resolved, events }
    : { problem: STALE_NOTES_REPLY }
}

/**
 * `path` made absolute against the session's directory. Used only where the
 * engine answers a file's details without its resolved path.
 */
async function absolutePathOf($: EngineInterface, path: string): Promise<string> {
  if (path.startsWith('/') || /^[A-Za-z]:[\\/]/.test(path)) return path

  return `${(await $.session.cwd()).replace(/\/+$/, '')}/${path}`
}

/**
 * Adds the tool's own hook, the one hook here with a matcher.
 */
export function registerToolHook(on: On): void {
  // The name is written out, not built from `TOOL_NAME`, because
  // `claude plugin validate` reads a matcher only as a literal.
  on('tool.call', { tool: 'mcp__opinionated-context-management__compact' }, async ($, e) => {
    if (e.agentId !== undefined) return { result: SUBAGENT_REPLY }

    let answer: { result: string } | { deny: string }
    try {
      answer = await schedule($, e)
    } catch (error) {
      // Answered as a refusal, so the model is told the compaction was not
      // scheduled instead of the call ending without an answer. The error's
      // text goes to the person: it is the engine's or the runtime's, and
      // the model's texts state only what the mod itself knows.
      log($, toolFailureLogLine(error instanceof Error ? error.message : String(error)))
      answer = { deny: INTERNAL_FAILURE_REPLY }
    }
    if ('deny' in answer) {
      // The refusal says a compaction was not scheduled, so a request an
      // earlier call in this turn stored is removed: left in place, it
      // would run when the turn ends, against what the model was just told.
      // The refusal then says that the earlier request is gone too, so that
      // request does not end without the model being told.
      try {
        let isRemoved = false
        await update($, pending, current => {
          isRemoved = current !== null && current.phase === 'turn'

          return isRemoved ? null : current
        })
        if (isRemoved) {
          log($, EARLIER_REQUEST_REMOVED_LOG_LINE)
          answer = { deny: `${answer.deny} ${EARLIER_REQUEST_REMOVED_REPLY}` }
        }
      } catch {
        // The refusal is still answered.
      }
    }

    return answer
  })
}

/** Checks a call of the compaction tool and, when it passes, stores the request. */
async function schedule(
  $: EngineInterface,
  e: unknown,
): Promise<{ result: string } | { deny: string }> {
  {
    const { instructions, continuation, notes } = e as {
      instructions?: unknown
      continuation?: unknown
      notes?: unknown
    }
    if (
      typeof instructions !== 'string' ||
      typeof continuation !== 'string' ||
      instructions.trim() === '' ||
      continuation.trim() === ''
    ) {
      return { deny: MISSING_INPUT_REPLY }
    }

    const listed: unknown[] = Array.isArray(notes) ? notes : []
    // Notes are required for every compaction: after it they are what
    // carries the task's knowledge, and a rule with an exception the mod
    // cannot check would leave the requirement to the model's discretion.
    if (listed.length === 0) return { deny: NO_NOTES_REPLY }
    // Every listed entry is checked, so an entry that is not a path is
    // refused and not passed over.
    const paths = listed.filter(
      (path): path is string => typeof path === 'string' && path.trim() !== '',
    )
    if (paths.length !== listed.length) return { deny: BLANK_NOTE_PATH_REPLY }

    const checked = await checkNotes($, paths)
    if ('problem' in checked) return { deny: checked.problem }

    await update($, pending, () => ({
      instructions,
      continuation,
      notes: checked.resolved,
      phase: 'turn' as const,
    }))
    // A prompt or tool call that started while the files were being checked
    // found no request to cancel. It is seen here, after the request is in
    // state: from this point on, whatever arrives cancels the request itself.
    if ((await read($, eventCount)) !== checked.events) {
      await update($, pending, () => null)

      return { deny: STALE_NOTES_REPLY }
    }
    // News of an earlier request's end is out of date once a new one stands.
    await update($, owedNotice, () => null)

    return { result: SCHEDULED_REPLY }
  }
}

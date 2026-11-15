/**
 * The live context window's fill, as the mod last measured it.
 *
 * `tokens` is the size the last main-thread response reported, an exact
 * figure. Before the first response this load of the mod sees, it is the
 * engine's own figure, which leaves that response's output out. It is absent
 * when both are missing. A compaction or a /clear removes it, and it is
 * filled again by the next response or, when a measurement comes first, by
 * the engine's figure.
 */
export type ContextFill = {
  tokens?: number
  /**
   * An estimate of the tokens that tool results have added since that
   * response. The next response reports the exact size, which replaces
   * `tokens` and clears this estimate.
   */
  unmeasured?: number
  /** The model's context window, in tokens. */
  window: number
  /**
   * The token count at which auto-compaction runs; absent when it is off,
   * and when whether it is on is not known.
   */
  compactAt?: number
  /**
   * Whether the engine has said if auto-compaction is on. It says so only
   * in an answer that carries a breakdown, so until one has arrived an
   * absent `compactAt` means "not known" and not "off".
   */
  isAutoCompactKnown?: boolean
  /**
   * Set when the conversation was replaced by a compaction, until the first
   * response after it. That response sets the notice level the summary has
   * already reached as noticed, without sending the notice: compacting again
   * would not make the conversation smaller.
   */
  isJustCompacted?: boolean
}

/**
 * A compaction the model asked for through the mod's tool, held from the
 * request until the compaction has run or the request is canceled.
 */
export type PendingCompaction = {
  /** What the summary has to keep. */
  instructions: string
  /**
   * The prompt submitted after the compaction. It is not submitted when the
   * compaction did not run; a notice is, in its place.
   */
  continuation: string
  /** The absolute paths of the note files the model listed, checked when it asked. */
  notes: string[]
  /**
   * Where the request stands: `turn` while the turn that asked is still
   * running, `waiting` once that turn has ended in an answer and the
   * compaction is due, `compacting` while the engine is compacting. A due
   * request is carried out as its turn ends; it stays `waiting` for the
   * measurement that follows the turn only when a prompt was submitted
   * while that turn ran, or the turn's end was not handled.
   */
  phase: 'turn' | 'waiting' | 'compacting'
  /**
   * Set when a prompt was submitted while the engine was compacting for this
   * request. The request is kept so that its continuation still follows, but
   * a compaction that fails is then not tried again: a later attempt would
   * replace a conversation that holds a prompt the notes were not written for.
   */
  isOvertaken?: boolean
  /**
   * Set when the conversation was compacted by another source (the engine's
   * auto-compaction, or the person's /compact) after this request was made.
   * That compaction stands for the one asked for: the mod doesn't compact
   * again, and submits the continuation when the request comes due.
   */
  isCompacted?: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'opinionated-context-management': {
      /** Null until the engine has been asked for the window once. */
      context: ContextFill | null
      pending: PendingCompaction | null
      /**
       * The notice level the live context window has reached with a notice
       * sent; lowered when the conversation shrinks.
       */
      noticeLevel: number
      /**
       * The limit and the settings that `noticeLevel` was counted against,
       * as one text; "" before the first measurement. A level is a count of
       * thresholds passed, so it means something only on one such scale.
       */
      scale: string
      /**
       * When the main conversation last had a tool call other than the
       * compaction tool's, or a submitted prompt, in epoch milliseconds; 0
       * before the first.
       */
      lastEventAt: number
      /**
       * How many such events there have been. Order between events is judged
       * by this count; the time is kept only to compare with a note file's
       * modification time.
       */
      eventCount: number
      /**
       * The id of the main-thread turn that was running when a prompt was
       * last submitted over a running turn; null before the first. A
       * request made in that turn is not carried out at the turn's end,
       * because the prompt may be held to start the next turn.
       */
      promptedTurn: string | null
      /**
       * The text of a notice about a request that ended (or, after a
       * compaction, about a prompt that could not be submitted), kept while
       * it could not be appended to the conversation; null when nothing is owed. It
       * is sent with the next main-thread tool result, or appended after
       * the next response.
       */
      owedNotice: string | null
    }
  }
}

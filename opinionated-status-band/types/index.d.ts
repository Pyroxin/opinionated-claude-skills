/**
 * One rate-limit window as the engine reports it (`five_hour`, `seven_day`,
 * or a gateway's `spend_limit`).
 */
export type RateLimit = {
  kind: string
  /** 0 to 100, past 100 on an exceeded spend limit. */
  percentUsed: number
  /** ISO 8601 timestamp of the window's reset. */
  resetsAt?: string
}

/**
 * The live context window's fill.
 *
 * `tokens` is absent until the first response of the live window, which
 * includes the stretch between a compaction and the next response.
 */
export type ContextFill = {
  tokens?: number
  /** The model's context window, in tokens. */
  window: number
  /** The token count at which auto-compaction runs; absent when it is off. */
  compactAt?: number
}

/**
 * What the status band draws from. Every field is optional because each one
 * arrives from a different event, and the band draws whichever it has.
 */
export type Status = {
  context?: ContextFill
  rateLimits?: RateLimit[]
  costUsd?: number
  model?: string
  effort?: string
  /** The repository's directory name, or the working directory's outside one. */
  project?: string
  branch?: string
  turns?: number
  /** When the main thread's current or latest turn began, in epoch milliseconds. */
  turnStartedAt?: number
  /**
   * When the main thread's latest turn ended, in epoch milliseconds, and
   * whether it ended in a reply; a turn can also be interrupted, refused, or
   * fail.
   */
  lastTurn?: { at: number; isReply: boolean }
}

declare module 'claude-code' {
  interface PluginState {
    'opinionated-status-band': {
      status: Shaped<Status>
      /** Epoch milliseconds of the last clock tick; a write redraws the band. */
      tick: number
    }
  }
}

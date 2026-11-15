import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Status } from '../types'
import { fit, segmentsOf } from './segments'
import type { Segment } from './segments'

// The atoms are declared in this file because `claude plugin validate` reads
// a state reference only where its literal is written.
//
// Change the tag when `Status` changes shape: a stored value outlives a
// reload, and the tag makes the atom read one stored under another tag as
// the initial value.
const status = atom(
  { plugin: 'opinionated-status-band', key: 'status' } as const,
  {},
  { shape: 'status-2' },
)
const tick = atom({ plugin: 'opinionated-status-band', key: 'tick' } as const, 0)

/** How often the band redraws so its ages and reset countdowns stay current. */
const TICK_MS = 15_000

/**
 * The band's colors are based on the Adwaita-inspired colors of the
 * `adwaita-inspired-light` theme in this marketplace's `opinionated-themes`
 * plugin. The text, the gauge's warning orange, and the gauge's error red
 * are that theme's `text`, `warning`, and `error` values. The rest were
 * chosen to sit with them: the grays for the tiers and the gauge's track, a
 * green lighter than the theme's `success`, which was too dark against a
 * gray tier, and darker tones of orange and red for text.
 *
 * Eight of the ten values are entries in the GNOME palette, the palette the
 * Adwaita style draws on: the tier grays are its Light 4, Light 3 and Light
 * 2, the muted text its Dark 2, the gauge's green, orange and red its Green
 * 4, Orange 4 and Red 4, and the error text its Red 5. The text color
 * `#1d1d20` and the warning text `#8f3a00` are not in it; the second is
 * darker than the palette's darkest orange, for contrast on a gray tier.
 * https://developer.gnome.org/hig/reference/palette.html (retrieved
 * November 15, 2026)
 *
 * The colors are fixed instead of theme keys because each block sets both
 * its background and its text, so it is legible on any terminal background,
 * and because a theme's status colors are chosen for text on the terminal's
 * background, where they have too little contrast against a shaded block.
 */

/**
 * Shading per tier. Tier 0 sits at the band's outer ends and tier 2 toward
 * its middle. The grays are light, darkest at the ends.
 */
const TIERS = [
  { backgroundColor: '#c0bfbc' },
  { backgroundColor: '#deddda' },
  { backgroundColor: '#f6f5f4' },
] as const

/** Text on any tier: the theme's near-black `text`, as every tier is light. */
const TEXT = '#1d1d20'

/**
 * Text colors per tone. A figure within its limits is plain text; the two
 * tones that call for attention use an orange and a red dark enough to read
 * on the darkest tier.
 */
const TEXT_TONES = {
  success: TEXT,
  warning: '#8f3a00',
  error: '#a51d2d',
  muted: '#5e5c64',
} as const

/**
 * Gauge cell colors per tone. `warning` and `error` are the theme's. `muted`
 * is the empty track: a gray one step lighter than the tier the gauge sits
 * on, so the track is visible without matching a white terminal background,
 * which would read as a gap in the band.
 */
const BAR_TONES = {
  success: '#2ec27e',
  warning: '#e66100',
  error: '#c01c28',
  muted: '#deddda',
} as const

// Powerline separators: a solid triangle pointing right, and one pointing left.
// They are Private Use Area characters, as is the branch glyph in
// `segments.ts`, so the terminal's font has to include the Powerline symbols;
// the README states the requirement for users.
const SEPARATOR_RIGHT = '\ue0b0'
const SEPARATOR_LEFT = '\ue0b2'

const basename = (path: string): string => path.replace(/\/+$/, '').split('/').pop() || path

/** The checked-out branch, or undefined outside a repository or on a detached HEAD. */
const branchOf = async ($: EngineInterface, cwd: string): Promise<string | undefined> => {
  try {
    const { exitCode, stdout } = await $.process.run(['git', 'branch', '--show-current'], {
      cwd,
      timeoutMs: 5000,
    })
    const branch = stdout.trim()

    return exitCode === 0 && branch !== '' ? branch : undefined
  } catch {
    // The call rejects when git cannot start or outlasts the timeout. The
    // band then draws without a branch, which is also what it draws outside
    // a repository.
    return undefined
  }
}

/** The answer of `ask`, or undefined when it rejects. */
const optional = async <T,>(ask: Promise<T>): Promise<T | undefined> => {
  try {
    return await ask
  } catch {
    return undefined
  }
}

/** The usage figures the engine pushes with `session.measure` and answers from `$.session.usage`. */
type Figures = {
  context: { tokens?: number; window: number }
  rateLimits: Status['rateLimits']
  cost?: { usd: number }
}

/**
 * Merges the engine's usage figures into the status.
 *
 * The engine's context figure is the last response's input side. The
 * `turn.step` hook measures input plus output, which approximates what the
 * next request sends back, so its figure is the one kept once it exists: writing the
 * engine's over it would make the gauge fall at the end of every turn, and
 * could put an older count over a newer one.
 */
const applyFigures = async ($: EngineInterface, figures: Figures): Promise<void> => {
  await update($, status, (held): Status => ({
    ...held,
    context: {
      ...held.context,
      tokens: held.context?.tokens ?? figures.context.tokens,
      window: figures.context.window,
    },
    rateLimits: figures.rateLimits,
    costUsd: figures.cost?.usd,
  }))
}

/**
 * Reads what the engine answers only on request: the auto-compaction
 * threshold, the model, the turn count, and the project and branch.
 *
 * Each is read on its own, so one that fails leaves the others, and the band
 * draws without it. This costs a local breakdown estimate and a git process,
 * so it runs when a turn has ended and not on every measurement.
 */
const refreshDetails = async ($: EngineInterface): Promise<void> => {
  const [usage, model, turns, cwd, repo] = await Promise.all([
    // `summary` estimates the breakdown locally; it is asked for only to
    // learn the auto-compaction threshold, which the plain call leaves out.
    optional($.session.usage({ breakdown: 'summary' })),
    optional($.session.model()),
    optional($.session.turns()),
    optional($.session.cwd()),
    optional($.session.repo()),
  ])
  const branch = cwd === undefined ? undefined : await branchOf($, cwd)
  const breakdown = usage?.context.breakdown
  const root = repo?.root ?? cwd

  await update($, status, (held): Status => ({
    ...held,
    context:
      held.context === undefined || breakdown === undefined
        ? held.context
        : {
            ...held.context,
            compactAt: breakdown.isAutoCompactEnabled ? breakdown.autoCompactThreshold : undefined,
          },
    model: model ?? held.model,
    turns: turns ?? held.turns,
    project: root === undefined ? held.project : basename(root),
    branch,
  }))
}

/** Reports a failure of this mod without letting it reach the event it happened in. */
const report = ($: EngineInterface, what: string, error: unknown): void => {
  const reason = error instanceof Error ? error.message : String(error)
  $.ui.log(`Status band: ${what} failed: ${reason}`)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // Started before anything that can fail, so the band's ages and
    // countdowns keep advancing whatever the first reads do. The timer ends
    // when the module reloads, and `session.start` runs again then, so each
    // load holds exactly one.
    $.clock.every(TICK_MS, async () => {
      const now = await $.clock.now()
      await update($, tick, () => now)
    })
    try {
      await applyFigures($, await $.session.usage())
      await refreshDetails($)
    } catch (error) {
      report($, 'the first reading', error)
    }

    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    try {
      // The pushed figures are published first, so a slow git process does
      // not hold them back.
      await applyFigures($, e)
      // The context figure moves when a turn has ended, which is when the
      // model, the branch, and the turn count can have changed. A measurement
      // for a rate-limit window alone leaves them as they are.
      if (e.changed.includes('context')) await refreshDetails($)
    } catch (error) {
      report($, 'a measurement', error)
    }

    return next(e)
  })

  on('session.compact', async ($, e, next) => {
    const outcome = await next(e)
    // A compaction of the main conversation that stands empties the window
    // the gauge measures, and the engine reports no fill until the next
    // response. A `precompute` compaction prepares a summary ahead of time
    // and leaves the conversation as it is.
    if (outcome.skip === undefined && e.agentId === undefined && e.trigger !== 'precompute') {
      try {
        await update($, status, (held): Status =>
          held.context === undefined
            ? held
            : { ...held, context: { ...held.context, tokens: undefined } },
        )
      } catch (error) {
        report($, 'clearing the gauge after a compaction', error)
      }
    }

    return outcome
  })

  on('turn.start', async ($, e, next) => {
    // The main thread's turn, timed from its start. A prompt submitted while
    // a turn runs is queued and does not start one, so it is not the event
    // to time from.
    if (e.agentId === undefined) {
      try {
        const turnStartedAt = await $.clock.now()
        await update($, status, (held): Status => ({ ...held, turnStartedAt }))
      } catch (error) {
        report($, 'timing a turn', error)
      }
    }

    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    // The model and effort in force are reported per request. Only the main
    // thread's are the session's; a subagent runs at its own.
    if (e.agentId === undefined) {
      try {
        const effort = e.effort === undefined ? undefined : String(e.effort)
        await update($, status, (held): Status => ({ ...held, effort, model: e.model }))
      } catch (error) {
        report($, 'reading the model and effort', error)
      }
    }

    const response = yield* next(e)
    // The conversation grows within a turn, and a long turn is where its
    // size matters, so it is measured after every main-thread response
    // instead of once when the turn ends.
    const usage = response.usage
    if (e.agentId === undefined && usage !== null) {
      // Everything the request was answered over plus what it generated,
      // which approximates what the next request sends back. It can run
      // high, since some of what a response generates (its thinking, for
      // one) may be left out of later requests.
      const tokens =
        usage.input_tokens +
        usage.cache_read_input_tokens +
        usage.cache_creation_input_tokens +
        usage.output_tokens
      try {
        await update($, status, (held): Status =>
          held.context === undefined ? held : { ...held, context: { ...held.context, tokens } },
        )
      } catch (error) {
        // The measurement is secondary to the request it follows: a failure
        // here is reported and the response is returned as it came.
        report($, 'measuring the context after a response', error)
      }
    }

    return response
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      try {
        const at = await $.clock.now()
        // A turn can end without a reply: interrupted, refused, or failed.
        const lastTurn = { at, isReply: e.reason === 'answer' }
        await update($, status, (held): Status => ({ ...held, lastTurn }))
      } catch (error) {
        report($, 'timing the end of a turn', error)
      }
    }

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    // The row is built for a terminal: its widths are counted in character
    // cells, its gauge is a run of spaces on a background, and its separators
    // are Powerline glyphs from a patched font. On the desktop surface the
    // same tree draws in a proportional font with the glyphs missing, so the
    // band is left to the engine everywhere but the terminal.
    if (e.surface !== 'terminal' || e.props.hasSurvey) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const held = await read($, status)
    // Read for its subscription: a tick's write is what redraws the band
    // between events. The time drawn is the clock's own, so a redraw for any
    // other reason is current too.
    await read($, tick)
    const now = await $.clock.now()

    const columns = e.props.bodyColumns
    const segments = fit(segmentsOf(held, now, e.props.isWorking), columns)

    const body = (segment: Segment) => {
      const tier = TIERS[segment.tier]

      return (
        <Text backgroundColor={tier.backgroundColor} color={TEXT} wrap="truncate-end">
          {' '}
          {segment.parts.map(part =>
            part.isBar ? (
              <Text backgroundColor={BAR_TONES[part.tone ?? 'muted']}>{part.text}</Text>
            ) : (
              <Text
                color={part.tone === undefined ? TEXT : TEXT_TONES[part.tone]}
                weight={part.tone === 'warning' || part.tone === 'error' ? 'bold' : undefined}
              >
                {part.text}
              </Text>
            ),
          )}{' '}
        </Text>
      )
    }

    // A separator is drawn in its own segment's shade over its neighbor's,
    // which is what makes the two blocks read as one chevron-edged strip.
    const left = segments.filter(segment => segment.side === 'left')
    const right = segments.filter(segment => segment.side === 'right')
    const shadeOf = (segment: Segment | undefined) =>
      segment === undefined ? undefined : TIERS[segment.tier].backgroundColor

    return (
      <Box flexDirection="row" justifyContent="space-between" width={columns}>
        <Box flexDirection="row">
          {left.map((segment, index) => (
            <Box flexDirection="row">
              {body(segment)}
              <Text color={shadeOf(segment)} backgroundColor={shadeOf(left[index + 1])}>
                {SEPARATOR_RIGHT}
              </Text>
            </Box>
          ))}
        </Box>
        <Box flexDirection="row">
          {right.map((segment, index) => (
            <Box flexDirection="row">
              <Text color={shadeOf(segment)} backgroundColor={shadeOf(right[index - 1])}>
                {SEPARATOR_LEFT}
              </Text>
              {body(segment)}
            </Box>
          ))}
        </Box>
      </Box>
    )
  })
}

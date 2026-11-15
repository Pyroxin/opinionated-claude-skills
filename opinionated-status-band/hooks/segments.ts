// The status band's content as plain data: which segments exist, what each
// says, and which of them fit a given width. Kept free of `$` and of elements
// so the wording and the fitting rule can be tested without a session.

import type { ContextFill, RateLimit, Status } from '../types'

/**
 * What a run of text signifies, left for the drawing code to turn into a
 * color: the same tone is one color as text and another as a gauge cell.
 */
export type Tone = 'success' | 'warning' | 'error' | 'muted'

/**
 * A run of text within a segment; without a `tone` it is the block's plain
 * text. A part with `isBar` is a stretch of a gauge: its text is spaces, and
 * its tone colors the cells themselves instead of glyphs within them.
 */
export type Part = { text: string; tone?: Tone; isBar?: boolean }

/**
 * One block of the band.
 *
 * `tier` selects the block's shading.
 * `priority` orders removal when the band is too narrow: the highest number
 * is removed first, so 0 is the segment that survives longest.
 */
export type Segment = {
  id: string
  side: 'left' | 'right'
  tier: 0 | 1 | 2
  priority: number
  parts: Part[]
}

const GAUGE_CELLS = 10

/** Severity thresholds as fractions of the limit a figure is measured against. */
const WARNING_AT = 0.6
const DANGER_AT = 0.85

export const severityOf = (ratio: number): Tone =>
  ratio >= DANGER_AT ? 'error' : ratio >= WARNING_AT ? 'warning' : 'success'

/**
 * The context gauge's tone for a fraction of the limit used: warning once
 * half the context is left and error once 15% is left. The two points are
 * choices about when the gauge should draw the eye while there is still room
 * to act on it; the engine supplies no thresholds of its own.
 */
export const contextToneOf = (used: number): Tone =>
  used >= 0.85 ? 'error' : used >= 0.5 ? 'warning' : 'success'

/** 950 -> "950", 18_400 -> "18k", 1_000_000 -> "1M", 1_250_000 -> "1.3M". */
export const formatTokens = (count: number): string => {
  if (count < 1000) return String(count)
  if (count < 999_500) return `${Math.round(count / 1000)}k`

  return `${(count / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`
}

/**
 * 42_000 -> "42s", 250_000 -> "4m", 8_040_000 -> "2h14m", four days and five
 * hours -> "4d5h". Negative reads as 0.
 */
export const formatDuration = (milliseconds: number): string => {
  const seconds = Math.max(0, Math.floor(milliseconds / 1000))
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h${String(minutes % 60).padStart(2, '0')}m`

  return `${Math.floor(hours / 24)}d${hours % 24}h`
}

const contextSegment = (context: ContextFill | undefined): Segment => {
  const base = { id: 'context', side: 'left', tier: 0, priority: 0 } as const
  if (context === undefined) return { ...base, parts: [{ text: 'ctx …' }] }

  const { tokens, window, compactAt } = context
  // One limit is the base of every figure in the segment: the bar, the two
  // counts, the percentage, and the color. With auto-compaction on, that
  // limit is its threshold, which is where the usable window ends; otherwise
  // it is the window. Measuring the color against the threshold and the
  // percentage against the window would show a color change at a percentage
  // that matches neither.
  const limit = compactAt !== undefined && compactAt < window ? compactAt : window
  if (tokens === undefined) {
    // No response has reported the live window's fill yet: a new session, or
    // one just compacted.
    return { ...base, parts: [{ text: `ctx –/${formatTokens(limit)}` }] }
  }

  const used = tokens / limit
  const tone = contextToneOf(used)
  const filled = Math.min(GAUGE_CELLS, Math.max(0, Math.round(used * GAUGE_CELLS)))
  // Percent remaining, since how much room is left is what the reader acts on.
  const percentLeft = Math.max(0, Math.round((1 - used) * 100))
  const parts: Part[] = [
    { text: 'ctx ' },
    { text: ' '.repeat(filled), tone, isBar: true },
    { text: ' '.repeat(GAUGE_CELLS - filled), tone: 'muted', isBar: true },
    { text: ` ${formatTokens(tokens)}/${formatTokens(limit)} · ` },
    { text: `${percentLeft}% left`, tone },
  ]

  return { ...base, parts }
}

const LIMIT_LABELS: Record<string, string> = {
  five_hour: '5h',
  seven_day: '7d',
  spend_limit: 'spend',
}

const rateLimitParts = (limit: RateLimit, now: number): Part[] => {
  const label = LIMIT_LABELS[limit.kind] ?? limit.kind
  const parts: Part[] = [
    { text: `${label} ` },
    { text: `${Math.round(limit.percentUsed)}%`, tone: severityOf(limit.percentUsed / 100) },
  ]
  const resetsAt = limit.resetsAt === undefined ? NaN : Date.parse(limit.resetsAt)
  if (Number.isFinite(resetsAt) && resetsAt > now) {
    parts.push({ text: ` ↻${formatDuration(resetsAt - now)}`, tone: 'muted' })
  }

  return parts
}

/** The band's segments for `status`, each side in drawing order, left to right. */
export const segmentsOf = (status: Status, now: number, isWorking: boolean): Segment[] => {
  const segments: Segment[] = [contextSegment(status.context)]

  if (status.model !== undefined) {
    const effort = status.effort === undefined ? '' : ` · ${status.effort}`
    segments.push({
      id: 'model',
      side: 'left',
      tier: 1,
      priority: 1,
      // The engine answers the model's id. Where an id begins `claude-`, the
      // prefix says nothing the rest of the id does not.
      parts: [{ text: `${status.model.replace(/^claude-/, '')}${effort}` }],
    })
  }

  if (status.project !== undefined) {
    // U+E0A0 is the Powerline branch glyph.
    const branch = status.branch === undefined ? '' : ` \ue0a0 ${status.branch}`
    segments.push({
      id: 'project',
      side: 'left',
      tier: 2,
      priority: 4,
      parts: [{ text: `${status.project}${branch}` }],
    })
  }

  // While a turn runs, the age that matters is how long it has run; once it
  // ends, how long the conversation has sat untouched. A turn that ended
  // without a reply (interrupted, refused, or failed) is said to have stopped.
  const { turnStartedAt, lastTurn } = status
  const age =
    isWorking && turnStartedAt !== undefined
      ? `working ${formatDuration(now - turnStartedAt)}`
      : lastTurn !== undefined
        ? `${lastTurn.isReply ? 'replied' : 'stopped'} ${formatDuration(now - lastTurn.at)} ago`
        : undefined
  if (age !== undefined) {
    segments.push({ id: 'age', side: 'right', tier: 2, priority: 2, parts: [{ text: age }] })
  }

  const limits = status.rateLimits ?? []
  if (limits.length > 0) {
    const parts = limits.flatMap((limit, index) => [
      ...(index === 0 ? [] : [{ text: '  ' }]),
      ...rateLimitParts(limit, now),
    ])
    segments.push({ id: 'limits', side: 'right', tier: 1, priority: 3, parts })
  }

  if (status.costUsd !== undefined) {
    const turns = status.turns === undefined ? '' : ` · ${status.turns} turns`
    segments.push({
      id: 'cost',
      side: 'right',
      tier: 0,
      priority: 5,
      parts: [{ text: `$${status.costUsd.toFixed(2)}${turns}` }],
    })
  }

  return segments
}

/**
 * The terminal cells `text` occupies: two for a wide East Asian or fullwidth
 * character, none for a combining diacritical mark (U+0300 to U+036F), a
 * zero-width joiner, or a variation selector, one for anything else. A project or branch name can hold any of these, and the
 * band is fitted to a width the engine gives in cells.
 *
 * The ranges cover the common cases, not the whole of Unicode's width data:
 * the combining marks of other scripts count one cell each, and an emoji
 * joined from several counts each part. A name with such characters is
 * counted a cell or more off, and the band then truncates or leaves cells
 * unused.
 */
export const cellWidth = (text: string): number => {
  let cells = 0
  for (const character of text) {
    const code = character.codePointAt(0) ?? 0
    const isZeroWidth =
      (code >= 0x0300 && code <= 0x036f) || code === 0x200d || (code >= 0xfe00 && code <= 0xfe0f)
    const isWide =
      (code >= 0x1100 && code <= 0x115f) ||
      (code >= 0x2e80 && code <= 0xa4cf) ||
      (code >= 0xac00 && code <= 0xd7a3) ||
      (code >= 0xf900 && code <= 0xfaff) ||
      (code >= 0xfe30 && code <= 0xfe4f) ||
      (code >= 0xff00 && code <= 0xff60) ||
      (code >= 0xffe0 && code <= 0xffe6) ||
      (code >= 0x1f300 && code <= 0x1faff) ||
      (code >= 0x20000 && code <= 0x3fffd)
    cells += isZeroWidth ? 0 : isWide ? 2 : 1
  }

  return cells
}

/**
 * The cells a segment occupies: its text, a space of padding on each side,
 * and its separator glyph.
 */
export const widthOf = (segment: Segment): number =>
  segment.parts.reduce((sum, part) => sum + cellWidth(part.text), 0) + 3

/**
 * The segments that fit in `columns`, in their original order.
 *
 * Removes the segment with the highest `priority` number until the rest fit;
 * the last segment standing is kept even when it is too wide, so the band
 * truncates it instead of drawing nothing.
 */
export const fit = (segments: Segment[], columns: number): Segment[] => {
  let kept = segments
  while (kept.length > 1 && kept.reduce((sum, s) => sum + widthOf(s), 0) > columns) {
    const victim = kept.reduce((worst, s) => (s.priority > worst.priority ? s : worst))
    kept = kept.filter(s => s !== victim)
  }

  return kept
}

import { expect, test } from 'claude-code/testing'

import {
  cellWidth,
  contextToneOf,
  fit,
  formatDuration,
  formatTokens,
  segmentsOf,
  widthOf,
} from '../hooks/segments'

const textOf = (parts: { text: string }[]) => parts.map(part => part.text).join('')

test('token counts are abbreviated at thousands and millions', async () => {
  expect(formatTokens(950)).toBe('950')
  expect(formatTokens(18_400)).toBe('18k')
  expect(formatTokens(1_000_000)).toBe('1M')
  expect(formatTokens(1_250_000)).toBe('1.3M')
})

test('durations show one unit under an hour and two from an hour up', async () => {
  expect(formatDuration(42_000)).toBe('42s')
  expect(formatDuration(250_000)).toBe('4m')
  expect(formatDuration(8_040_000)).toBe('2h14m')
  expect(formatDuration((4 * 24 + 5) * 3_600_000)).toBe('4d5h')
  expect(formatDuration(-5)).toBe('0s')
})

test('every figure in the context gauge is measured against one limit', async () => {
  // 600k of a 1M window whose auto-compaction threshold is 800k: 75% of the
  // limit is used, so 25% is left, whatever share of the window that is.
  const [context] = segmentsOf(
    { context: { tokens: 600_000, window: 1_000_000, compactAt: 800_000 } },
    0,
    false,
  )

  expect(textOf(context!.parts)).toBe(`ctx ${' '.repeat(10)} 600k/800k · 25% left`)
  // Eight of ten cells are filled: 75% of the limit, rounded.
  expect(context!.parts[1]).toEqual({ text: ' '.repeat(8), tone: 'warning', isBar: true })
  expect(context!.parts[2]).toEqual({ text: ' '.repeat(2), tone: 'muted', isBar: true })
  expect(context!.parts[4]).toEqual({ text: '25% left', tone: 'warning' })
})

test('the gauge changes tone at half the context left and at 15% left', async () => {
  expect(contextToneOf(0.49)).toBe('success')
  expect(contextToneOf(0.5)).toBe('warning')
  expect(contextToneOf(0.84)).toBe('warning')
  expect(contextToneOf(0.85)).toBe('error')
})

test('with auto-compaction off the limit is the window', async () => {
  const [context] = segmentsOf({ context: { tokens: 50_000, window: 200_000 } }, 0, false)

  expect(textOf(context!.parts)).toBe(`ctx ${' '.repeat(10)} 50k/200k · 75% left`)
  // The joined text is ten spaces however the bar is split, so the split and
  // the tones are checked part by part: 25% used rounds to three cells.
  expect(context!.parts[1]).toEqual({ text: ' '.repeat(3), tone: 'success', isBar: true })
  expect(context!.parts[2]).toEqual({ text: ' '.repeat(7), tone: 'muted', isBar: true })
  expect(context!.parts[4]).toEqual({ text: '75% left', tone: 'success' })
})

test('a conversation past its limit fills the bar and leaves nothing', async () => {
  const [context] = segmentsOf({ context: { tokens: 210_000, window: 200_000 } }, 0, false)

  expect(context!.parts[1]).toEqual({ text: ' '.repeat(10), tone: 'error', isBar: true })
  expect(context!.parts[2]).toEqual({ text: '', tone: 'muted', isBar: true })
  expect(context!.parts[4]).toEqual({ text: '0% left', tone: 'error' })
})

test('a window with no reported fill draws a placeholder against the same limit', async () => {
  const [off] = segmentsOf({ context: { window: 200_000 } }, 0, false)
  expect(textOf(off!.parts)).toBe('ctx –/200k')

  // With auto-compaction on, the placeholder names the threshold, as the
  // gauge will once a response reports the fill.
  const [on] = segmentsOf({ context: { window: 200_000, compactAt: 160_000 } }, 0, false)
  expect(textOf(on!.parts)).toBe('ctx –/160k')
})

test('the age segment reports the running turn, then how the last turn ended', async () => {
  const ageOf = (held: Parameters<typeof segmentsOf>[0], now: number, isWorking: boolean) =>
    textOf(segmentsOf(held, now, isWorking).find(s => s.id === 'age')!.parts)
  const replied = { turnStartedAt: 0, lastTurn: { at: 60_000, isReply: true } }

  expect(ageOf(replied, 30_000, true)).toBe('working 30s')
  expect(ageOf(replied, 360_000, false)).toBe('replied 5m ago')
  // A turn that was interrupted, refused, or failed did not end in a reply.
  expect(ageOf({ lastTurn: { at: 60_000, isReply: false } }, 360_000, false)).toBe(
    'stopped 5m ago',
  )
})

test('widths are counted in terminal cells', async () => {
  expect(cellWidth('main')).toBe(4)
  // Two wide characters occupy four cells.
  expect(cellWidth('工程')).toBe(4)
  // An "e" followed by a combining acute accent occupies one cell.
  expect(cellWidth('é')).toBe(1)

  const [, , project] = segmentsOf({ model: 'Model', project: '工程' }, 0, false)
  // Four cells of text, a space each side, and the separator.
  expect(widthOf(project!)).toBe(7)
})

test('a narrow band removes the lowest-priority segments first and keeps context', async () => {
  const segments = segmentsOf(
    {
      context: { tokens: 10_000, window: 200_000 },
      model: 'Model',
      project: 'project',
      costUsd: 1,
      lastTurn: { at: 0, isReply: true },
    },
    1000,
    false,
  )
  const idsAt = (columns: number) => fit(segments, columns).map(s => s.id)
  const total = segments.reduce((sum, s) => sum + widthOf(s), 0)

  // All five fit in exactly their summed width, and one cell less removes
  // the segment with the lowest priority.
  expect(idsAt(total)).toEqual(['context', 'model', 'project', 'age', 'cost'])
  expect(idsAt(total - 1)).toEqual(['context', 'model', 'project', 'age'])
  expect(idsAt(64)).toEqual(['context', 'model', 'age'])
  // The last segment is kept even when it is wider than the band.
  expect(idsAt(5)).toEqual(['context'])
})

import { expect, test } from 'claude-code/testing'

import {
  DEFAULT_SETTINGS,
  finalLevelOf,
  levelOf,
  limitOf,
  settingProblemsOf,
  settingsOf,
  tokensAfter,
} from '../hooks/compaction'
import {
  BLANK_NOTE_PATH_REPLY,
  EARLIER_REQUEST_REMOVED_REPLY,
  endedLogLine,
  endedNotice,
  finalNoticeText,
  INTERNAL_FAILURE_REPLY,
  MISSING_INPUT_REPLY,
  noticeLogLine,
  NO_NOTES_REPLY,
  NOTICE_TEXT,
  noteProblemReply,
  notesLead,
  resumeFallbackNotice,
  STALE_NOTES_REPLY,
  SCHEDULED_REPLY,
  SECTION_TEXT,
  settingProblemLogLine,
  SUBAGENT_REPLY,
  TOOL_DESCRIPTION,
  TOOL_INPUT_SCHEMA,
} from '../hooks/instructions'

test('the conversation size counts every token the next request sends back', async () => {
  expect(
    tokensAfter({
      input_tokens: 10,
      cache_read_input_tokens: 1000,
      cache_creation_input_tokens: 200,
      output_tokens: 300,
    }),
  ).toBe(1510)
})

test('the limit is the auto-compaction threshold when one is in force', async () => {
  expect(limitOf({ window: 1_000_000, compactAt: 800_000 })).toBe(800_000)
  expect(limitOf({ window: 200_000 })).toBe(200_000)
})

test('a notice level is passed at each threshold of the limit', async () => {
  expect(levelOf(490_000, 1_000_000, DEFAULT_SETTINGS)).toBe(0)
  expect(levelOf(500_000, 1_000_000, DEFAULT_SETTINGS)).toBe(1)
  expect(levelOf(700_000, 1_000_000, DEFAULT_SETTINGS)).toBe(2)
  expect(levelOf(900_000, 1_000_000, DEFAULT_SETTINGS)).toBe(3)
})

test('the final level is reached a fixed number of tokens before the limit', async () => {
  const final = finalLevelOf(DEFAULT_SETTINGS)
  expect(final).toBe(4)

  // The same 30k margin on a large window and on a small one.
  expect(levelOf(969_999, 1_000_000, DEFAULT_SETTINGS)).toBe(3)
  expect(levelOf(970_000, 1_000_000, DEFAULT_SETTINGS)).toBe(final)
  expect(levelOf(169_999, 200_000, DEFAULT_SETTINGS)).toBe(2)
  expect(levelOf(170_000, 200_000, DEFAULT_SETTINGS)).toBe(final)

  // Where the margin starts below an ordinary threshold, that threshold is
  // never reported: the final level is reached first and stays the highest.
  expect(levelOf(84_000, 100_000, DEFAULT_SETTINGS)).toBe(final)
})

test('the final notice states the room left and keeps the task whole', async () => {
  const text = finalNoticeText(30_000, 'on')

  expect(text).toMatch(/About 30k tokens of room are left before automatic compaction/)
  // With auto-compaction off, the notice names the window and doesn't
  // claim that the engine will compact.
  const withoutAuto = finalNoticeText(30_000, 'off')
  expect(withoutAuto).toMatch(/About 30k tokens of room are left in the context window/)
  expect(withoutAuto).toMatch(/automatic compaction is off in this session/)
  expect(withoutAuto).not.toMatch(/the engine may compact/)
  expect(withoutAuto).toMatch(/don't drop or shorten any part of the work/)
  // When the engine has not said, the notice says that and claims neither.
  const unknown = finalNoticeText(30_000, 'unknown')
  expect(unknown).toMatch(/Whether automatic compaction is on in this session is not known/)
  expect(unknown).not.toMatch(/automatic compaction is off in this session/)
  expect(unknown).toMatch(/don't drop or shorten any part of the work/)
  expect(text).toMatch(/don't drop or shorten any part of the work/)
})

test('settings are read from the options, and an unusable value keeps the default', async () => {
  // 90% and 75% remaining are the points where 10% and 25% is used; the
  // order they are given in does not matter, and a repeat counts once.
  expect(
    settingsOf({
      remainingContextNoticePercents: ['75', '90', '75'],
      remainingContextFinalNoticeTokens: 5000,
    }),
  ).toEqual({ noticeAt: [1 - 0.9, 1 - 0.75], finalTokens: 5000 })
  expect(
    settingsOf({ remainingContextNoticePercents: ['often'], remainingContextFinalNoticeTokens: 'many' }),
  ).toEqual(DEFAULT_SETTINGS)
  expect(settingsOf({})).toEqual(DEFAULT_SETTINGS)
})

test('a stored setting means the same as one string, as a list, or as a mixture', async () => {
  // The settings interface stores a typed list as one comma-separated
  // string; the manifest default and a hand-edited file give a list.
  const expected = { noticeAt: [1 - 0.85, 1 - 0.8, 1 - 0.75], finalTokens: 5000 }
  for (const percents of ['85, 80, 75', '85 80 75', ['85', '80', '75'], ['85, 80', '75']]) {
    expect(
      settingsOf({ remainingContextNoticePercents: percents, remainingContextFinalNoticeTokens: '5000' }),
    ).toEqual(expected)
  }
})

test('auto, an empty value, and a value that is not one count ask for the default', async () => {
  for (const percents of ['auto', 'AUTO', ['auto'], '', ' , ']) {
    for (const tokens of ['auto', 'Auto', '', '30,000', '30k']) {
      expect(
        settingsOf({ remainingContextNoticePercents: percents, remainingContextFinalNoticeTokens: tokens }),
      ).toEqual(DEFAULT_SETTINGS)
    }
  }
  // `auto` beside real entries is ignored, not a reason to drop them.
  expect(
    settingsOf({ remainingContextNoticePercents: 'auto, 40', remainingContextFinalNoticeTokens: 'auto' }),
  ).toEqual({ noticeAt: [1 - 0.4], finalTokens: DEFAULT_SETTINGS.finalTokens })
})

// The final notice is left out of this check on purpose: it is the one text
// that states the room left.
test('an entry a setting cannot use is reported, and auto or an empty value is not', async () => {
  expect(
    settingProblemsOf({ remainingContextNoticePercents: 'auto', remainingContextFinalNoticeTokens: '' }),
  ).toEqual([])
  expect(settingProblemsOf({})).toEqual([])

  const problems = settingProblemsOf({
    remainingContextNoticePercents: '85, often, 150',
    remainingContextFinalNoticeTokens: '30,000',
  })
  expect(problems.map(problem => [problem.option, problem.entry])).toEqual([
    ['remainingContextNoticePercents', 'often'],
    ['remainingContextNoticePercents', '150'],
    ['remainingContextFinalNoticeTokens', '30,000'],
  ])
  // 85 is usable, so it stays in force beside the entries that are not.
  expect(problems[0]?.inForce).toBe('The other entries are in force.')
  expect(problems[2]?.inForce).toBe('The default count is in force.')
  expect(settingProblemLogLine(problems[2]!)).toBe(
    'Context management: ignored "30,000" in the setting remainingContextFinalNoticeTokens, which takes one whole number of tokens above 0, written without separators. The default count is in force.',
  )
  expect(
    settingProblemsOf({ remainingContextNoticePercents: ['0'], remainingContextFinalNoticeTokens: '-5' }).map(
      problem => problem.inForce,
    ),
  ).toEqual(['The default thresholds are in force.', 'The default count is in force.'])
})

test('the final-notice setting takes digits only', async () => {
  for (const entry of ['0.5', '1e4', '0x10', '1.0', '0']) {
    expect(
      settingProblemsOf({ remainingContextFinalNoticeTokens: entry }).map(problem => problem.entry),
    ).toEqual([entry])
    expect(settingsOf({ remainingContextFinalNoticeTokens: entry }).finalTokens).toBe(
      DEFAULT_SETTINGS.finalTokens,
    )
  }
  expect(settingProblemsOf({ remainingContextFinalNoticeTokens: '20000' })).toEqual([])
  expect(settingsOf({ remainingContextFinalNoticeTokens: '20000' }).finalTokens).toBe(20_000)
})

test('a notice for a request that ended after another source compacted says so and lists the notes', async () => {
  const request = { notes: ['/work/notes/progress.md', '/work/notes/findings.md'], isCompacted: true }
  for (const cause of ['tool-call', 'prompt', 'turn-aborted', 'turn-start'] as const) {
    const notice = endedNotice(cause, request)
    expect(notice).not.toContain('The conversation was not compacted')
    expect(notice).toContain('compacted the conversation, so it now begins with a summary')
    expect(notice).toContain('Your continuation was not submitted')
    expect(notice).toContain('- `/work/notes/progress.md`\n- `/work/notes/findings.md`')
  }
  // The conversation was just compacted, so the notice does not say to ask
  // again at once.
  expect(endedNotice('tool-call', request)).not.toContain('To compact, update the notes')
  expect(endedNotice('tool-call', request)).toContain('Carry on with the work.')

  // Without that compaction the wording is as before, and paths are not listed.
  const plain = endedNotice('turn-aborted', { notes: request.notes })
  expect(plain).toContain('The conversation was not compacted')
  expect(plain).not.toContain('/work/notes/progress.md')

  // The person's line says that the conversation was compacted all the same.
  expect(endedLogLine('turn-aborted', undefined, true)).toContain(
    'Another source had compacted the conversation after Claude asked',
  )
  expect(endedLogLine('turn-aborted')).not.toContain('Another source')
})

test('a notice that cannot say whether the conversation was compacted lists the notes', async () => {
  for (const cause of ['reload', 'mod-failure'] as const) {
    const notice = endedNotice(cause, { notes: ['/work/notes/progress.md'] })
    expect(notice).toContain('The mod cannot tell whether the conversation was compacted first')
    expect(notice).toContain('- `/work/notes/progress.md`')
  }
})

test('the section and both notices leave an instruction not to write to the workspace in force', async () => {
  const kept = 'not override an instruction not to write to the workspace'
  expect(SECTION_TEXT).toContain(kept)
  expect(NOTICE_TEXT).toContain(kept)
  for (const autoCompact of ['on', 'off', 'unknown'] as const) {
    expect(finalNoticeText(20_000, autoCompact)).toContain(kept)
  }
})

test('both notices and the tool description say where notes go and set them apart from memory', async () => {
  // Each restates the section's documentation expectations to bring them
  // back to the model's attention when they apply; they reinforce the
  // section and don't replace it.
  const texts = [
    NOTICE_TEXT,
    TOOL_DESCRIPTION,
    ...(['on', 'off', 'unknown'] as const).map(autoCompact => finalNoticeText(20_000, autoCompact)),
  ]
  for (const text of texts) {
    expect(text).toContain('`{project-root}/.tmp/notes/{task-name}/`')
    expect(text).toContain('memory directory')
    expect(text).toContain('readable from the workspace by whoever resumes the task')
  }
})

test('the ordinary notice leaves the timing to the two conditions', async () => {
  // Models compacted at the first notice without checking for a checkpoint,
  // so the notice says it is not a request to compact now and gives both
  // conditions; the section and the tool description say the same.
  expect(NOTICE_TEXT).toContain("This notice doesn't ask you to compact before both conditions below hold")
  expect(NOTICE_TEXT).toContain('Partway through a step is not a checkpoint')
  expect(NOTICE_TEXT).toContain('The detail in the conversation is no longer needed there')
  expect(SECTION_TEXT).toContain("A notice doesn't change the two conditions above")
  expect(TOOL_DESCRIPTION).toContain("A context notice doesn't change these conditions")
})

test('the stale-notes refusal allows for a prompt the model has not read yet', async () => {
  expect(STALE_NOTES_REPLY).toContain('The later event can be a prompt you have not read yet')
  expect(STALE_NOTES_REPLY).toContain('including that prompt when it has reached you')
})

// Every cause the model is sent a notice for.
const ENDED_CAUSES = [
  'tool-call',
  'prompt',
  'turn-aborted',
  'turn-refusal',
  'turn-error',
  'turn-other',
  'turn-start',
  'reload',
  'mod-failure',
  'declined',
  'not-started',
] as const

test('no other text given to the model states a size or uses a listed term of shortage', async () => {
  // This checks the two properties a pattern can check: that no figure
  // appears, and that none of these particular terms does. Whether the
  // wording as a whole leaves a model unhurried is a question for trials
  // with the model, which no pattern answers.
  const terms =
    /running out|run out|almost full|nearly full|limited|urgent|immediately|quickly|as soon as possible|remaining|exhaust|budget/i
  const texts = [
    SECTION_TEXT,
    TOOL_DESCRIPTION,
    NOTICE_TEXT,
    SCHEDULED_REPLY,
    ...ENDED_CAUSES.map(cause => endedNotice(cause)),
    ...ENDED_CAUSES.map(cause => endedNotice(cause, { notes: ['/work/notes/progress.md'] })),
    ...ENDED_CAUSES.map(cause =>
      endedNotice(cause, { notes: ['/work/notes/progress.md'], isCompacted: true }),
    ),
    EARLIER_REQUEST_REMOVED_REPLY,
    BLANK_NOTE_PATH_REPLY,
    resumeFallbackNotice(['notes/progress.md'], 'carry on'),
    INTERNAL_FAILURE_REPLY,
    SUBAGENT_REPLY,
    MISSING_INPUT_REPLY,
    JSON.stringify(TOOL_INPUT_SCHEMA),
    NO_NOTES_REPLY,
    STALE_NOTES_REPLY,
    noteProblemReply('notes/progress.md', 'it is empty'),
    notesLead(['notes/progress.md']),
  ]
  for (const text of texts) {
    expect(terms.test(text)).toBe(false)
    expect(/\d+\s*(k|%|tokens|percent)/i.test(text)).toBe(false)
  }
})

test('the line shown to the person says when the model will read the notice', async () => {
  const midTurn = noticeLogLine({
    isFinal: false,
    percentLeft: 30,
    tokensLeft: 290_000,
    isTurnEnding: false,
  })
  expect(midTurn).toBe(
    'Context management: told Claude that compacting at its next resumable point would be useful (30% of context left). Claude reads this at its next request in the current turn.',
  )

  const atTurnEnd = noticeLogLine({
    isFinal: true,
    percentLeft: 3,
    tokensLeft: 29_000,
    isTurnEnding: true,
  })
  expect(atTurnEnd).toMatch(/about 29k tokens of context are left/)
  expect(atTurnEnd).toMatch(/reads this with the next prompt/)
})

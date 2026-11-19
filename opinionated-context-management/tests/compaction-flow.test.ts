import type { SessionCompacted } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// Each hook registered here stands for the engine beneath the mod, so what
// it records is what the mod asked the engine to do.

const COMPACT = 'mcp__opinionated-context-management__compact'
const TURN = { answer: 'done', durationMs: 1, isAborted: false, turnId: 't1' } as const
// A compaction that stands leaves at least one message: the summary.
const COMPACTED: SessionCompacted = {
  messages: [{ role: 'user', text: 'summary', toolUses: [] }],
}
const NOTES = { tool: COMPACT, instructions: 'keep the plan', continuation: 'carry on' } as const
// What each listed note file is, as the engine would answer. A path absent
// from `files` cannot be read.
type TestBody = Extract<Parameters<typeof test>[1], (...args: never[]) => unknown>
type On = Parameters<TestBody>[1]
// The measurement the engine raises after a main-thread turn, which is when
// the mod carries out a compaction that is due.
const MEASURE = { context: { window: 100_000 }, rateLimits: [], changed: ['context'] } as never
const withFiles = (on: On, files: Record<string, { size: number; mtimeMs: number }>) => {
  on('session.measure', (_, e) => ({ changed: e.changed }) as never)
  on('fs.stat', (_, e) => {
    // The engine may hand the path over made absolute, so a file is found
    // by the end of its path.
    const name = Object.keys(files).find(key => e.path.endsWith(key))
    const file = name === undefined ? undefined : files[name]
    if (file === undefined) throw new Error(`no such file: ${e.path}`)

    // The resolved path the engine would answer: the workspace this test
    // pretends to run in, then the file's path within it.
    return { value: { kind: 'file', isLink: false, realPath: `/work/${name}`, ...file } as never }
  })
}
// Stands for the engine running any tool the mod does not answer itself.
const withTools = (on: On) => on('tool.call', () => ({ result: {} }))
const PROGRESS = '.tmp/notes/task/progress.md'
const FINDINGS = '.tmp/notes/task/findings.md'

// A call that lists a note. Each test that uses it supplies the file with
// `withNote`, written no earlier than any event in the test.
const ASK = { ...NOTES, notes: [PROGRESS] } as const
// A prompt submitted while the turn `t1` ran, before the model asked. The
// engine may hold such a prompt to start the next turn, so the mod leaves a
// request made after it due at the turn's end, for the measurement.
const TYPED_DURING_TURN = { text: 'typed earlier', turnId: TURN.turnId } as never
const withNote = (on: On) => withFiles(on, { [PROGRESS]: { size: 900, mtimeMs: 0 } })

test('a compaction the model asks for runs when its turn ends, then the work resumes', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  const compacted: (string | undefined)[] = []
  const submitted: string[] = []
  const order: string[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)
    order.push('compact')

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)
    order.push('submit')

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  const reply = await $.tool.call(ASK)
  expect(String(reply.result)).toMatch(/scheduled/)
  // Nothing runs while the turn that asked is still going.
  expect(order).toEqual([])

  // It runs when that turn ends, without waiting for the measurement.
  await $.turn.complete({ ...TURN, reason: 'answer' })
  expect(order).toEqual(['compact', 'submit'])
  // The measurement that follows finds the request settled.
  await $.session.measure(MEASURE)

  expect(compacted).toEqual(['keep the plan'])
  expect(order).toEqual(['compact', 'submit'])
  expect(submitted.length).toBe(1)
  // The note's path is carried ahead of the continuation.
  expect(submitted[0]).toContain(`- \`/work/${PROGRESS}\``)
  expect(submitted[0]).toMatch(/carry on$/)
})

test('a skipped compaction resumes the work with a notice, and without the continuation', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  const submitted: string[] = []
  on('session.compact', () => ({ skip: 'a hook declined it' }))
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(submitted.length).toBe(1)
  expect(submitted[0]).toContain('did not happen, because Claude Code or another plugin declined it')
  expect(submitted[0]).toContain('The conversation is unchanged')
  // The continuation was written for a reader who has only the summary, and
  // the engine's own words stay out of what the model reads.
  expect(submitted[0]).not.toContain('carry on')
  expect(submitted[0]).not.toContain('.tmp/notes')
  expect(submitted[0]).not.toContain('a hook declined it')
})

test('an interrupted turn drops the compaction and doesn\'t resume anything', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  const compacted: unknown[] = []
  const submitted: string[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
  expect(submitted).toEqual([])
})

test('a call without both inputs is refused and doesn\'t schedule anything', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  const reply = await $.tool.call({ tool: COMPACT, instructions: 'keep the plan' })
  expect(reply.deny ?? reply.text ?? String(reply.result)).toMatch(/required/)

  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
})

test('a call that doesn\'t list any notes is refused', async $ => {
  const reply = await $.tool.call(NOTES)

  expect(String(reply.deny ?? reply.text)).toMatch(/doesn't list any note files/)

  const empty = await $.tool.call({ ...NOTES, notes: [] })

  expect(String(empty.deny ?? empty.text)).toMatch(/doesn't list any note files/)
})

test('notes written after the last tool call are accepted, and lead the continuation', async ($, on) => {
  const clock = mock.clock(on)
  const submitted: string[] = []
  withTools(on)
  on('session.compact', () => COMPACTED)
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))
  // Hooks are registered before the test first calls `$`, so the files are
  // filled in afterward, once their times are known.
  const files: Record<string, { size: number; mtimeMs: number }> = {}
  withFiles(on, files)

  // Work, then the progress record written after it. The findings note is
  // older than the work, which is allowed: one current note is enough.
  await clock.advance(1000)
  files[FINDINGS] = { size: 400, mtimeMs: clock.now() }
  await clock.advance(1000)
  await $.tool.call({ tool: 'Bash', command: 'make test' })
  await clock.advance(1000)
  files[PROGRESS] = { size: 900, mtimeMs: clock.now() }

  const reply = await $.tool.call({ ...NOTES, notes: [PROGRESS, FINDINGS] })
  expect(String(reply.result)).toMatch(/scheduled/)

  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(submitted.length).toBe(1)
  // The paths were listed relative and are handed back absolute.
  expect(submitted[0]).toContain(`- \`/work/${PROGRESS}\`\n- \`/work/${FINDINGS}\``)
  expect(submitted[0]).toMatch(/carry on$/)
})

test('a tool call after the notes were written, even a read, refuses the compaction', async ($, on) => {
  const clock = mock.clock(on)
  withTools(on)
  // A time off the whole second, so the allowance for coarse file times does
  // not apply.
  await clock.advance(1001)
  withFiles(on, { [PROGRESS]: { size: 900, mtimeMs: clock.now() } })
  await clock.advance(1000)
  await $.tool.call({ tool: 'Read', file_path: 'src/main.ts' })

  const reply = await $.tool.call({ ...NOTES, notes: [PROGRESS] })

  expect(String(reply.deny ?? reply.text)).toContain(
    'something happened after the notes were last written',
  )
})

test('a note time on a whole second is allowed the coarseness of its file system', async ($, on) => {
  const clock = mock.clock(on)
  withTools(on)
  // The call that writes the note starts at 1,500 ms, and a file system that
  // records whole seconds gives the note the time 1,000 ms.
  withFiles(on, { [PROGRESS]: { size: 900, mtimeMs: 1000 } })
  await clock.advance(1500)
  await $.tool.call({ tool: 'Bash', command: 'write the note' })

  const reply = await $.tool.call({ ...NOTES, notes: [PROGRESS] })

  expect(String(reply.result)).toMatch(/scheduled/)
})

test('a prompt after the notes were written refuses the compaction', async ($, on) => {
  const clock = mock.clock(on)
  on('prompt.submit', (_, e) => ({ text: e.text }))
  await clock.advance(1001)
  withFiles(on, { [PROGRESS]: { size: 900, mtimeMs: clock.now() } })
  await clock.advance(1000)
  // The test kit's type also asks for the engine's own fields of a prompt.
  await $.prompt.submit({ text: 'Also rename the module before you stop.' } as never)

  const reply = await $.tool.call({ ...NOTES, notes: [PROGRESS] })

  expect(String(reply.deny ?? reply.text)).toContain(
    'something happened after the notes were last written',
  )
})

test('a subagent\'s tool calls do not count against the notes', async ($, on) => {
  const clock = mock.clock(on)
  withTools(on)
  // Off the whole second, so the allowance for coarse file times does not
  // hide a subagent's call that was counted.
  await clock.advance(1001)
  withFiles(on, { [PROGRESS]: { size: 900, mtimeMs: clock.now() } })
  await clock.advance(1000)
  await $.tool.call({ tool: 'Bash', command: 'ls', agentId: 'a1' })

  const reply = await $.tool.call({ ...NOTES, notes: [PROGRESS] })

  expect(String(reply.result)).toMatch(/scheduled/)
})

test('a listed note that is missing or empty is refused', async ($, on) => {
  withFiles(on, { 'empty.md': { size: 0, mtimeMs: 5000 } })
  const refusal = async (notes: string[]) => {
    const reply = await $.tool.call({ ...NOTES, notes })

    return String(reply.deny ?? reply.text)
  }

  expect(await refusal(['missing.md'])).toContain('`missing.md`: it does not exist or cannot be read')
  expect(await refusal(['empty.md'])).toContain('`empty.md`: it is empty')
})

// A response of `tokens` in all, as the engine would report its usage.
const usageOf = (tokens: number) => ({
  input_tokens: tokens,
  cache_read_input_tokens: 0,
  cache_creation_input_tokens: 0,
  output_tokens: 0,
})
// Stands for the engine beneath the mod for the measurement tests: a 100k
// window with auto-compaction off, a model whose every response reports the
// size `sizes` holds next, and tools whose result is the text `results`
// holds next. Answers the notices appended to the conversation and the
// lines logged for the person.
// What the mod's `session.start` hook and its log lines need beneath them.
const withSession = (on: On, logged: string[] = []) => {
  on('session.start', (_, e) => ({ cwd: e.cwd }) as never)
  on('tool.register', () => ({ value: undefined as never }))
  on('ui.log', (_, e) => {
    logged.push(e.text)

    return { value: undefined as never }
  })
}
const START = { cwd: '/work' } as never
const withConversation = (
  on: On,
  sizes: number[],
  results: string[],
  logged: string[] = [],
  // Stands for a plugin above the engine that refuses appended rows while
  // this answers true.
  isRefusing: () => boolean = () => false,
  // The indexes of the steps whose response used a tool the API ran itself.
  // Such a response reports its usage summed over its requests, so its
  // entry in `sizes` is that sum, of which `SUMMED_OUTPUT` is output.
  summedSteps: readonly number[] = [],
  // The size the engine's measurement reports, when it reports one: the
  // engine's does after a turn, and a test that needs that says so here.
  measured: () => number | undefined = () => undefined,
) => {
  const appended: string[] = []
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: { tokens: measured(), window: 100_000 },
      rateLimits: [],
    } as never,
  }))
  on('session.append', (_, e, next) => {
    if (isRefusing()) return { deny: 'rows are not accepted' } as never
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  withSession(on, logged)
  on('turn.step', async function* (_, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      ...(summedSteps.includes(e.index)
        ? {
            serverToolUses: [{ id: 's1', name: 'advisor', input: {}, startedAt: 0, endedAt: 1 }],
            usage: { ...usageOf((sizes.shift() ?? 0) - SUMMED_OUTPUT), output_tokens: SUMMED_OUTPUT },
          }
        : { usage: usageOf(sizes.shift() ?? 0) }),
    } as never
  })
  on('tool.call', () => ({ result: {}, text: results.shift() ?? '' }))

  return appended
}
// What a response that used a server-side tool generated, in tokens.
const SUMMED_OUTPUT = 1_000
const STEP = { turnId: 't1', index: 0 as number, model: 'model', messageCount: 1 }
// Runs one model step to its end. The test kit hands a step back as a
// stream, and the mod measures once the stream has ended.
const step = async ($: Parameters<TestBody>[0], input: typeof STEP) => {
  const chunks = ($.turn.step(input) as unknown as AsyncIterable<unknown>)[Symbol.asyncIterator]()
  let chunk = await chunks.next()
  while (chunk.done !== true) chunk = await chunks.next()
}
const READ = { tool: 'Read', file_path: 'src/main.ts' } as const
// 2,500 characters are counted as 1,000 tokens.
const textOfTokens = (tokens: number) => 'x'.repeat(tokens * 2.5)

test('a tool result that passes a threshold carries the notice with it', async ($, on) => {
  const appended = withConversation(on, [45_000], [textOfTokens(1_000), textOfTokens(6_000)])
  await $.session.start(START)
  await step($, STEP)

  // 46k of 100k: under the first threshold, so the result comes back as it was.
  const small = await $.tool.call(READ)
  expect(small.context).toBeUndefined()

  // 52k of 100k: past the threshold at half the context left.
  const large = await $.tool.call(READ)
  expect(large.context?.length).toBe(1)
  expect(large.context?.[0]).toContain("This notice doesn't ask you to compact before both conditions below hold")
  expect(large.text).toBe(textOfTokens(6_000))
  // The notice went with the result and was not appended as a row of its own.
  expect(appended).toEqual([])
})

test('a notice sent on an estimate is not sent again when the exact size is lower', async ($, on) => {
  const appended = withConversation(on, [45_000, 49_000, 51_000], [textOfTokens(6_000)])
  await $.session.start(START)
  await step($, STEP)

  const result = await $.tool.call(READ)
  expect(result.context?.length).toBe(1)

  // The response after the result reports 49k: the estimate was over the
  // true count, and the conversation did not shrink.
  await step($, { ...STEP, index: 1 })
  // The next reports 51k, past the threshold the notice was already sent for.
  await step($, { ...STEP, index: 2 })

  expect(appended).toEqual([])
})

test('tool results that finish together and pass one threshold send one notice', async ($, on) => {
  withConversation(on, [45_000], [textOfTokens(6_000), textOfTokens(6_000)])
  await $.session.start(START)
  await step($, STEP)

  const results = await Promise.all([$.tool.call(READ), $.tool.call(READ)])

  expect(results.filter(result => result.context !== undefined).length).toBe(1)
})

test('a response that passes a threshold appends the notice, once', async ($, on) => {
  const appended = withConversation(on, [45_000, 52_000, 53_000], [])
  await $.session.start(START)
  await step($, STEP)
  await step($, { ...STEP, index: 1 })
  await step($, { ...STEP, index: 2 })

  expect(appended.length).toBe(1)
  expect(appended[0]).toContain("This notice doesn't ask you to compact before both conditions below hold")
})

test('after the conversation shrinks, its thresholds are ahead of it again', async ($, on) => {
  const appended = withConversation(on, [52_000, 20_000, 52_000], [])
  await $.session.start(START)
  await step($, STEP)
  // A compaction: the next response reports a smaller conversation.
  await step($, { ...STEP, index: 1 })
  await step($, { ...STEP, index: 2 })

  expect(appended.length).toBe(2)
})

test('a first measurement that failed is reported and made up at the next response', async ($, on) => {
  const logged: string[] = []
  const appended: string[] = []
  withSession(on, logged)
  let isFailing = true
  on('session.usage', () => {
    if (isFailing) throw new Error('usage is unavailable')

    return { value: { startedAt: 0, context: { window: 100_000 }, rateLimits: [] } as never }
  })
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('turn.step', async function* (_, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      usage: usageOf(52_000),
    } as never
  })
  on('tool.call', () => ({ result: {}, text: 'output' }))

  await $.session.start(START)
  expect(logged.some(line => line.includes('the first measurement of the context failed'))).toBe(true)
  // The tool result comes back as it was while nothing can be measured.
  expect((await $.tool.call(READ)).text).toBe('output')

  isFailing = false
  await step($, STEP)

  expect(appended.length).toBe(1)
})

test('an exact size replaces the estimate, which is not counted again', async ($, on) => {
  withConversation(on, [45_000, 46_000], [textOfTokens(4_000), textOfTokens(3_000)])
  await $.session.start(START)
  await step($, STEP)

  // 49k by estimate: under the threshold.
  expect((await $.tool.call(READ)).context).toBeUndefined()
  // The response after it reports 46k, which already counts that result.
  await step($, { ...STEP, index: 1 })
  // 49k again. Were the first estimate still held, this would read as 53k.
  expect((await $.tool.call(READ)).context).toBeUndefined()
})

test('tool results that pass a threshold only together send one notice', async ($, on) => {
  withConversation(on, [45_000], [textOfTokens(3_000), textOfTokens(3_000)])
  await $.session.start(START)
  await step($, STEP)

  // Neither 48k alone passes; 51k does, so no estimate may be lost.
  const results = await Promise.all([$.tool.call(READ), $.tool.call(READ)])

  expect(results.filter(result => result.context !== undefined).length).toBe(1)
})

test('the final notice states the room there is, not the configured margin', async ($, on) => {
  withConversation(on, [60_000], [textOfTokens(35_000)])
  await $.session.start(START)
  await step($, STEP)

  // 95k of 100k: 5k left, inside the 30k margin.
  const result = await $.tool.call(READ)

  expect(result.context?.[0]).toContain('About 5k tokens of room are left in the context window')
  // This engine stand-in never says whether auto-compaction is on.
  expect(result.context?.[0]).toContain('Whether automatic compaction is on in this session is not known')
})

test('the final notice says auto-compaction is off only when the engine has said so', async ($, on) => {
  withSession(on)
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: { window: 100_000, breakdown: { isAutoCompactEnabled: false } },
      rateLimits: [],
    } as never,
  }))
  on('turn.step', async function* (_, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      usage: usageOf(60_000),
    } as never
  })
  on('tool.call', () => ({ result: {}, text: textOfTokens(35_000) }))
  await $.session.start(START)
  await step($, STEP)

  const result = await $.tool.call(READ)

  expect(result.context?.[0]).toContain('automatic compaction is off in this session')
})

test('after a compaction, a threshold the conversation passes again sends its notice', async ($, on) => {
  const appended = withConversation(on, [52_000, 10_000, 52_000], [])
  on('session.compact', () => COMPACTED)
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  // The person's /compact: the summary is small, and the work then grows
  // the conversation past the same threshold a second time.
  await $.session.compact({ trigger: 'manual', messages: COMPACTED.messages } as never)
  await step($, { ...STEP, index: 1 })
  expect(appended.length).toBe(1)
  await step($, { ...STEP, index: 2 })

  expect(appended.length).toBe(2)
})

test('a summary prepared ahead of time leaves the notices already sent as sent', async ($, on) => {
  const logged: string[] = []
  const appended = withConversation(on, [52_000, 52_000], [], logged)
  on('session.compact', () => COMPACTED)
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  // A `precompute` compaction doesn't install anything, so the conversation is the
  // one the first notice was sent in.
  await $.session.compact({ trigger: 'precompute', messages: COMPACTED.messages } as never)
  await step($, { ...STEP, index: 1 })

  expect(appended.length).toBe(1)
  // Taken as a replacement, it would make this response the first after a
  // compaction, whose threshold is taken as noticed with a line to the
  // person; the count of notices alone would not show the difference.
  expect(logged.some(line => line.includes('right after a compaction'))).toBe(false)
})

test('a tool call after the request cancels it, and its result says so', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  withTools(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  const later = await $.tool.call(READ)
  expect(later.context?.[0]).toContain('is canceled, because this tool call finished after the request was accepted')

  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
})

test('a prompt submitted before the compaction starts cancels it, and the model is told', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  const submitted: { text: string; context?: readonly string[] }[] = []
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push({ text: e.text, context: e.context })

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  // While the turn that asked is still running.
  await $.prompt.submit({ text: 'One more thing first.', turnId: TURN.turnId } as never)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
  // Only the person's prompt: the continuation was not submitted.
  expect(submitted.map(prompt => prompt.text)).toEqual(['One more thing first.'])
  // The model is told by one notice, which says why and what to do next.
  expect(appended.length).toBe(1)
  expect(appended[0]).toContain('is canceled, because a new prompt arrived before the compaction started')
  expect(appended[0]).toContain('First attend to what follows this notice')
  expect(appended[0]).toContain('ask for the compaction again')
  // The prompt itself goes through as it came.
  expect(submitted[0]?.context).toBeUndefined()

  // A prompt with nothing scheduled adds nothing.
  await $.prompt.submit({ text: 'And another.' } as never)
  expect(appended.length).toBe(1)
})

test('a larger window puts its thresholds ahead of a conversation that had passed them', async ($, on) => {
  const appended: string[] = []
  const sizes = [75_000, 520_000]
  let window = 100_000
  withSession(on)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window }, rateLimits: [] } as never,
  }))
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('turn.step', async function* (_, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      usage: usageOf(sizes.shift() ?? 0),
    } as never
  })

  await $.session.start(START)
  // 75k of 100k is inside the final margin: the highest level is noticed.
  await step($, STEP)
  expect(appended.length).toBe(1)

  // A model with a 1M window; starting again measures it, as a reload does.
  window = 1_000_000
  await $.session.start(START)
  // 520k of 1M passes the first threshold of the new window.
  await step($, { ...STEP, index: 1 })

  expect(appended.length).toBe(2)
})

test('a compaction that was due when the module reloaded runs once', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 100_000 }, rateLimits: [] } as never,
  }))
  const order: string[] = []
  on('session.compact', () => {
    order.push('compact')

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    order.push('submit')

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.prompt.submit(TYPED_DURING_TURN)
  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  // A reload runs `session.start` again while the compaction is waiting,
  // and carries it out without waiting for a measurement.
  await $.session.start(START)
  expect(order).toEqual(['submit', 'compact', 'submit'])
  await $.session.measure(MEASURE)

  // The typed prompt, then one compaction and its continuation.
  expect(order).toEqual(['submit', 'compact', 'submit'])
})

test('a refused tool call after the request cancels it, and the refusal says so', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  // Stands for a refusal from beneath the mod, which may come after the
  // tool ran.
  on('tool.call', () => ({ deny: 'a plugin withheld the result' }))
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  const refused = await $.tool.call(READ)
  expect(refused.deny).toMatch(/^a plugin withheld the result/)
  expect(refused.deny).toContain('is canceled, because this tool call finished after the request was accepted')

  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])

  // A refusal with nothing scheduled comes back as it was.
  expect((await $.tool.call(READ)).deny).toBe('a plugin withheld the result')
})

test('a turn that is interrupted after a request tells the model the request is gone', async ($, on) => {
  const appended = withConversation(on, [52_000, 52_000], [])
  withNote(on)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  // The model answers the notice with a request, and the turn is then
  // interrupted, which drops the request.
  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })

  expect(appended.length).toBe(2)
  // The notice names how the turn ended.
  expect(appended[1]).toContain('is canceled, because the turn that asked for it was interrupted')

  // The threshold notice already sent is not sent a second time.
  await step($, { ...STEP, index: 1 })
  expect(appended.length).toBe(2)
})

test('a measurement without a breakdown keeps the limit already held', async ($, on) => {
  const appended: string[] = []
  const sizes = [30_000, 42_000]
  let hasBreakdown = true
  withSession(on)
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: {
        window: 100_000,
        ...(hasBreakdown
          ? { breakdown: { isAutoCompactEnabled: true, autoCompactThreshold: 80_000 } }
          : {}),
      },
      rateLimits: [],
    } as never,
  }))
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('turn.step', async function* (_, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      usage: usageOf(sizes.shift() ?? 0),
    } as never
  })

  await $.session.start(START)
  await step($, STEP)
  expect(appended).toEqual([])

  // Measured again, as a reload does, and this answer lacks the breakdown.
  hasBreakdown = false
  await $.session.start(START)
  // 42k is past half of the 80k limit and short of half of the 100k window,
  // so a notice is sent only when the 80k limit was kept.
  await step($, { ...STEP, index: 1 })

  expect(appended.length).toBe(1)
})

test('a compaction the engine rejects is not tried again, and a notice resumes the work', async ($, on) => {
  withNote(on)
  withSession(on)
  let attempts = 0
  const submitted: string[] = []
  on('session.compact', () => {
    attempts += 1
    throw new Error('a turn is running')
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)
  // A later measurement finds nothing due.
  await $.session.measure(MEASURE)

  expect(attempts).toBe(1)
  expect(submitted.length).toBe(1)
  expect(submitted[0]).toContain('did not happen, because Claude Code could not carry it out')
  expect(submitted[0]).not.toContain('carry on')
  expect(submitted[0]).not.toContain('a turn is running')
})

test('a prompt submitted while the engine compacts is followed by the continuation', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  let attempts = 0
  const submitted: string[] = []
  on('session.compact', async () => {
    attempts += 1
    // E.g., a background task's notification arriving mid-compaction.
    await $.prompt.submit({ text: 'A background task finished.' } as never)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(attempts).toBe(1)
  expect(submitted.length).toBe(2)
  expect(submitted[0]).toBe('A background task finished.')
  expect(submitted[1]).toContain(`- \`/work/${PROGRESS}\``)
  expect(submitted[1]).toMatch(/carry on$/)
})

test('a rejected compaction that a prompt overtook is not tried again', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  let attempts = 0
  const submitted: string[] = []
  on('session.compact', async () => {
    attempts += 1
    await $.prompt.submit({ text: 'A background task finished.' } as never)
    throw new Error('a turn is running')
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  // One attempt: a second would compact a conversation that holds the prompt.
  expect(attempts).toBe(1)
  expect(submitted.length).toBe(2)
  // The test kit reports a stand-in that throws in its own words, so the
  // reason is not matched.
  expect(submitted[1]).toContain('did not happen, because Claude Code could not carry it out')
  expect(submitted[1]).not.toContain('carry on')
})

test('a reload does not restart a compaction that a prompt overtook, and the model is told', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  const logged: string[] = []
  withSession(on, logged)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 100_000 }, rateLimits: [] } as never,
  }))
  let attempts = 0
  const appended: string[] = []
  const submitted: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', async () => {
    attempts += 1
    await $.prompt.submit({ text: 'A background task finished.' } as never)
    // The module reloads while the engine is still compacting.
    await $.session.start(START)
    throw new Error('ended by the reload')
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(attempts).toBe(1)
  // The request is settled by the reload itself; the person and the model
  // are told, and the continuation is not submitted.
  expect(logged.some(line => line.includes('the mod was reloaded while the compaction was under way'))).toBe(true)
  expect(appended.length).toBe(1)
  expect(appended[0]).toContain('was cut short, because the mod was reloaded')
  // The model may have only a summary, so the notice lists the note files.
  expect(appended[0]).toContain(`/work/${PROGRESS}`)
  expect(submitted).toEqual(['A background task finished.'])
})

test('a /clear cancels the request and the model is not sent a notice', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  const appended: string[] = []
  const submitted: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('session.end', () => ({ sessionId: 's2' }) as never)

  await $.tool.call(ASK)
  // While the turn that asked is still running.
  await $.session.end({ reason: 'clear' } as never)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
  expect(appended).toEqual([])
  expect(submitted).toEqual([])
})

test('a refused second request removes the first', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  const second = await $.tool.call({ ...NOTES, notes: ['missing.md'] })
  expect(String(second.deny ?? second.text)).toContain('The compaction was not scheduled')
  // The refusal also says that the request the first call made is gone.
  expect(String(second.deny ?? second.text)).toContain(
    'The compaction that an earlier call in this turn scheduled is canceled as well',
  )

  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  // The model was last told that a compaction was not scheduled.
  expect(compacted).toEqual([])
})

test('after a compaction has run, the request is settled and notices are sent again', async ($, on) => {
  const clock = mock.clock(on)
  const appended = withConversation(on, [52_000, 10_000, 52_000], [])
  withNote(on)
  on('session.compact', () => COMPACTED)
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)
  await step($, { ...STEP, index: 1 })
  // A request left in state would hold this notice back.
  await step($, { ...STEP, index: 2 })

  expect(appended.length).toBe(2)
})

test('an older note with a finer time does not take the allowance from the newest', async ($, on) => {
  const clock = mock.clock(on)
  withTools(on)
  // The progress record was written by the call at 3,000 ms on a file system
  // that records whole seconds; the findings note is older and finer.
  withFiles(on, {
    [PROGRESS]: { size: 900, mtimeMs: 2000 },
    [FINDINGS]: { size: 400, mtimeMs: 2500 },
  })
  await clock.advance(3000)
  await $.tool.call({ tool: 'Bash', command: 'write the progress record' })

  const reply = await $.tool.call({ ...NOTES, notes: [PROGRESS, FINDINGS] })

  expect(String(reply.result)).toMatch(/scheduled/)
})

test('a dropped-request notice that is refused goes with the next tool result', async ($, on) => {
  withNote(on)
  withSession(on)
  withTools(on)
  // Stands for a plugin above the engine that refuses appended rows.
  on('session.append', () => ({ deny: 'rows are not accepted' }) as never)
  on('turn.complete', (_, e) => ({ text: e.answer }))

  // The model asks before any threshold notice was sent, and the turn is
  // then interrupted: there isn't a threshold notice to fall back on.
  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })

  const first = await $.tool.call(READ)
  expect(first.context?.length).toBe(1)
  expect(first.context?.[0]).toContain('is canceled, because the turn that asked for it was interrupted')

  // Sent once.
  expect((await $.tool.call(READ)).context).toBeUndefined()
})

test('a compaction from another source stands for the one the model asked for', async ($, on) => {
  withNote(on)
  withSession(on)
  const triggers: unknown[] = []
  const submitted: string[] = []
  on('session.compact', (_, e) => {
    triggers.push(e.trigger)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  // The engine compacts by itself before the asking turn has ended.
  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  // The mod did not compact a second time, and the work resumes as asked.
  expect(triggers).toEqual(['auto'])
  expect(submitted.length).toBe(1)
  expect(submitted[0]).toContain(`- \`/work/${PROGRESS}\``)
  expect(submitted[0]).not.toMatch(/did not happen/)
  expect(submitted[0]).toMatch(/carry on$/)
})

test('a compaction from another source while the request is due submits the continuation', async ($, on) => {
  withNote(on)
  withSession(on)
  const triggers: unknown[] = []
  const submitted: string[] = []
  on('session.compact', (_, e) => {
    triggers.push(e.trigger)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.prompt.submit(TYPED_DURING_TURN)
  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  // The request is still due, and the person's /compact arrives before
  // the measurement.
  await $.session.compact({ trigger: 'manual', messages: COMPACTED.messages } as never)
  // The typed prompt, then the continuation.
  expect(submitted.length).toBe(2)
  expect(submitted[1]).toMatch(/carry on$/)

  await $.session.measure(MEASURE)
  expect(triggers).toEqual(['manual'])
  expect(submitted.length).toBe(2)
})

test('a compaction from another source with nothing asked for submits nothing', async ($, on) => {
  withNote(on)
  withSession(on)
  const submitted: string[] = []
  on('session.compact', () => COMPACTED)
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })

  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)

  expect(submitted).toEqual([])
})

test('a turn that starts before a due compaction ran drops it, and the model is told', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('turn.start', (_, e) => ({ turnId: 't2' }) as never)

  await $.prompt.submit(TYPED_DURING_TURN)
  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  // The prompt typed while the asking turn ran starts its turn first.
  await $.turn.start({ text: 'typed earlier' } as never)
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
  expect(appended.length).toBe(1)
  expect(appended[0]).toContain('is canceled, because a new turn started before the compaction could start')
})

test('a /resume drops the request as a /clear does', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('session.end', () => ({ sessionId: 's2' }) as never)

  await $.tool.call(ASK)
  // While the turn that asked is still running.
  await $.session.end({ reason: 'resume' } as never)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
  expect(appended).toEqual([])
})

test('right after a compaction, a threshold already passed is taken as noticed and the person is told', async ($, on) => {
  const logged: string[] = []
  const appended = withConversation(on, [52_000, 52_000, 53_000, 72_000], [textOfTokens(1_000)], logged)
  on('session.compact', () => COMPACTED)
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  // The summary alone is past the first threshold. A notice for it could
  // only ask for a compaction that would not make the conversation smaller.
  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)
  await step($, { ...STEP, index: 1 })
  expect(appended.length).toBe(1)
  expect(logged.some(line => line.includes('already past a notice threshold right after a compaction (48% of context left)'))).toBe(true)
  // Nor does a tool result or a later response at that level send it.
  expect((await $.tool.call(READ)).context).toBeUndefined()
  await step($, { ...STEP, index: 2 })
  expect(appended.length).toBe(1)

  // The next threshold up still sends its notice.
  await step($, { ...STEP, index: 3 })
  expect(appended.length).toBe(2)
})

test('a tool result does not send a notice before the first response after a compaction', async ($, on) => {
  withSession(on)
  // The engine's own figure for the conversation, which a measurement can
  // supply before any response has reported one.
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 100_000, tokens: 49_000 }, rateLimits: [] } as never,
  }))
  on('session.measure', (_, e) => ({ changed: e.changed }) as never)
  on('session.compact', () => COMPACTED)
  on('tool.call', () => ({ result: {}, text: textOfTokens(6_000) }))
  await $.session.start(START)

  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)
  await $.session.measure(MEASURE)

  // 55k of 100k by the engine's figure and the estimate, with the first
  // response after the compaction still to come.
  expect((await $.tool.call(READ)).context).toBeUndefined()
})

test('a /resume does not hold back the notice of the conversation that follows', async ($, on) => {
  const appended = withConversation(on, [52_000, 52_000], [])
  on('session.end', () => ({ sessionId: 's2' }) as never)
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  await $.session.end({ reason: 'resume' } as never)
  // The conversation resumed in its place is itself past the threshold.
  await step($, { ...STEP, index: 1 })

  expect(appended.length).toBe(2)
})

test('the person is told when a compaction the model asked for has run', async ($, on) => {
  const clock = mock.clock(on)
  withNote(on)
  const logged: string[] = []
  withSession(on, logged)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 100_000 }, rateLimits: [] } as never,
  }))
  on('session.compact', () => COMPACTED)
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(logged).toEqual([
    'Context management: compacted the conversation as Claude asked. Claude resumes from the prompt it wrote.',
  ])
})

test('the person\'s line carries the engine\'s reason, which the model\'s notice leaves out', async ($, on) => {
  withNote(on)
  const logged: string[] = []
  withSession(on, logged)
  const submitted: string[] = []
  on('session.compact', () => ({ skip: 'a hook declined it at 912k tokens' }))
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(
    logged.filter(line =>
      line.includes(
        'did not compact as Claude asked, because Claude Code or another plugin declined it (reported as: a hook declined it at 912k tokens)',
      ),
    ).length,
  ).toBe(1)
  expect(submitted.length).toBe(1)
  expect(submitted[0]).not.toContain('912k')
})

test('the notice for a turn that did not end in an answer names how it ended', async ($, on) => {
  withNote(on)
  withSession(on)
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  const endings = [
    ['aborted', 'was interrupted before it ended'],
    ['refusal', 'ended in a refusal'],
    ['error', 'failed with an error'],
    // A reason the mod does not know is still reported, in general terms.
    ['max_tokens', 'did not end with your answer'],
  ] as const
  for (const [reason, wording] of endings) {
    expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
    await $.turn.complete({ ...TURN, reason } as never)
    expect(appended.at(-1)).toContain(`because the turn that asked for it ${wording}`)
  }
  expect(appended.length).toBe(endings.length)
})

test('a resume prompt that is dropped once is submitted a second time', async ($, on) => {
  withNote(on)
  withSession(on)
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', () => COMPACTED)
  let attempts = 0
  on('prompt.submit', (_, e) => {
    attempts += 1

    return attempts === 1 ? { drop: 'the session was busy' } : { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(attempts).toBe(2)
  expect(appended).toEqual([])
})

test('a resume prompt that cannot be submitted leaves the continuation in a notice', async ($, on) => {
  withNote(on)
  const logged: string[] = []
  withSession(on, logged)
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', () => COMPACTED)
  let attempts = 0
  on('prompt.submit', () => {
    attempts += 1
    throw new Error('prompts are not accepted')
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(attempts).toBe(2)
  // After the compaction the model has only the summary, so the notice
  // carries what the prompt would have.
  expect(appended.length).toBe(1)
  expect(appended[0]).toContain('could not be submitted')
  expect(appended[0]).toContain(`/work/${PROGRESS}`)
  expect(appended[0]).toContain('carry on')
  expect(logged.some(line => line.includes('could not be submitted'))).toBe(true)
  expect(logged.some(line => line.includes('sending any message resumes the work'))).toBe(true)
  // The line for a resumed session is not printed for one that did not resume.
  expect(logged.some(line => line.includes('Claude resumes from the prompt it wrote'))).toBe(false)
})

test('a did-not-run notice that cannot be submitted is appended, without the continuation', async ($, on) => {
  withNote(on)
  const logged: string[] = []
  withSession(on, logged)
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', () => ({ skip: 'declined' }))
  on('prompt.submit', () => ({ drop: 'prompts are not accepted' }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(appended.length).toBe(1)
  expect(appended[0]).toContain('did not happen, because Claude Code or another plugin declined it')
  expect(appended[0]).not.toContain('carry on')
  // One line about the request for the person, which does not say the
  // notice was sent as a prompt.
  const lines = logged.filter(line => line.includes('did not compact as Claude asked'))
  expect(lines.length).toBe(1)
  expect(lines[0]).toContain('could not be submitted as a prompt (prompts are not accepted)')
  expect(lines[0]).not.toContain('was sent a notice in place of its own prompt')
})

test('a subagent\'s events neither cancel nor settle the main conversation\'s request', async ($, on) => {
  withNote(on)
  withSession(on)
  withTools(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('turn.start', (_, e) => ({ turnId: e.turnId }) as never)

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  // A subagent started earlier goes on working while the main turn ends.
  expect((await $.tool.call({ ...READ, agentId: 'a1' })).context).toBeUndefined()
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted', agentId: 'a1' } as never)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.turn.start({ turnId: 't2', agentId: 'a1' } as never)
  await $.session.measure(MEASURE)

  expect(compacted).toEqual(['keep the plan'])
})

test('a subagent that calls the tool is told that only the main conversation compacts', async ($, on) => {
  withNote(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  const reply = await $.tool.call({ ...ASK, agentId: 'a1' })
  expect(String(reply.result)).toContain('Only the main conversation compacts through this tool')
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual([])
})

test('a turn that ends without an answer leaves a request that is already due', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.prompt.submit(TYPED_DURING_TURN)
  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  // Only the turn that asked settles a request; a second turn's end with
  // the request already due is not that turn's to settle.
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  await $.session.measure(MEASURE)

  expect(compacted).toEqual(['keep the plan'])
})

test('while a request is scheduled a threshold notice is held, and sent once the request is gone', async ($, on) => {
  const appended = withConversation(on, [45_000, 52_000, 53_000], [])
  withNote(on)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  await $.session.start(START)
  await step($, STEP)

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  // Past the threshold, with a compaction already asked for.
  await step($, { ...STEP, index: 1 })
  expect(appended).toEqual([])

  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  expect(appended.length).toBe(1)
  await step($, { ...STEP, index: 2 })

  expect(appended.length).toBe(2)
  expect(appended[1]).toContain("This notice doesn't ask you to compact before both conditions below hold")
})

test('a new request clears the owed notice of an earlier one', async ($, on) => {
  withNote(on)
  withSession(on)
  withTools(on)
  on('session.append', () => ({ deny: 'rows are not accepted' }) as never)
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  // The model asks again before any tool result could carry the news.
  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)

  const later = await $.tool.call(READ)
  // Only the news about the request that stands: this call canceled it.
  expect(later.context?.length).toBe(1)
  expect(later.context?.[0]).toContain('because this tool call finished after the request was accepted')
})

test('an owed notice is appended after the next response when no tool result came first', async ($, on) => {
  let isRefusing = true
  const appended = withConversation(on, [10_000], [], [], () => isRefusing)
  withNote(on)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  await $.session.start(START)

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  isRefusing = false
  await step($, STEP)

  expect(appended.filter(row => row.includes('was interrupted before it ended')).length).toBe(1)
})

test('a threshold notice that was refused is sent by a later response', async ($, on) => {
  let isRefusing = true
  const logged: string[] = []
  const appended = withConversation(on, [52_000, 53_000], [], logged, () => isRefusing)
  await $.session.start(START)

  await step($, STEP)
  expect(logged.some(line => line.includes('the notice was refused'))).toBe(true)
  isRefusing = false
  await step($, { ...STEP, index: 1 })

  expect(appended.filter(row => row.includes("This notice doesn't ask you to compact before both conditions below hold")).length).toBe(1)
})

test('a measurement that comes before the turn\'s end leaves the request for the turn\'s end', async ($, on) => {
  withNote(on)
  withSession(on)
  const order: string[] = []
  on('session.compact', () => {
    order.push('compact')

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    order.push('submit')

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.tool.call(ASK)
  // The turn that asked is still running, so nothing is due yet.
  await $.session.measure(MEASURE)
  expect(order).toEqual([])

  // No measurement follows: the turn's end carries the request out.
  await $.turn.complete({ ...TURN, reason: 'answer' })
  expect(order).toEqual(['compact', 'submit'])
})

test('a request made after a prompt typed during its turn waits for the measurement', async ($, on) => {
  withNote(on)
  withSession(on)
  const order: string[] = []
  on('session.compact', () => {
    order.push('compact')

    return COMPACTED
  })
  on('prompt.submit', (_, e) => {
    order.push(e.text === 'typed earlier' ? 'typed' : 'continuation')

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.prompt.submit(TYPED_DURING_TURN)
  await $.tool.call(ASK)
  // The typed prompt may be held to start the next turn, which would drop
  // the request, so the turn's end does not compact ahead of it.
  await $.turn.complete({ ...TURN, reason: 'answer' })
  expect(order).toEqual(['typed'])

  // The prompt was delivered into the turn: a new turn did not start, and
  // the measurement carries the request out.
  await $.session.measure(MEASURE)
  expect(order).toEqual(['typed', 'compact', 'continuation'])
})

test('a prompt typed during an earlier turn does not hold back a later turn\'s request', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.prompt.submit(TYPED_DURING_TURN)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, turnId: 't2', reason: 'answer' })

  expect(compacted).toEqual(['keep the plan'])
})

test('a turn\'s end the engine fails to handle makes the request due for the measurement', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', () => {
    throw new Error('the engine could not end the turn')
  })

  await $.tool.call(ASK)
  let isRejected = false
  try {
    await $.turn.complete({ ...TURN, reason: 'answer' })
  } catch {
    isRejected = true
  }
  // The failure is the engine's and is handed on; the mod does not compact
  // into a turn's end whose state it does not know.
  expect(isRejected).toBe(true)
  expect(compacted).toEqual([])

  await $.session.measure(MEASURE)
  expect(compacted).toEqual(['keep the plan'])
})

test('a response that used a server-side tool does not set the size from its summed usage', async ($, on) => {
  // The second response made two requests over a 30k conversation, so it
  // reports about twice that. Read as the size, 61k would pass the 50%
  // threshold of the 100k window.
  const logged: string[] = []
  const appended = withConversation(on, [30_000, 61_000, 33_000], [], logged, () => false, [1])
  await $.session.start(START)
  await step($, STEP)
  await step($, { ...STEP, index: 1 })

  expect(appended).toEqual([])
  expect(logged.filter(line => line.includes('context left'))).toEqual([])

  // The next response made by one request reports the size exactly.
  await step($, { ...STEP, index: 2 })
  expect(appended).toEqual([])
})

test('after a response that used a server-side tool, the size carried forward still counts', async ($, on) => {
  // 44k held and a 5.5k tool result estimated: 49.5k, under the threshold.
  // The summed response generated 1k, so the size carried forward is the
  // figure held, the estimate, and that output: 50.5k, which passes it.
  const appended = withConversation(
    on,
    [44_000, 94_000],
    [textOfTokens(5_500)],
    [],
    () => false,
    [1],
  )
  await $.session.start(START)
  await step($, STEP)
  expect((await $.tool.call(READ)).context).toBeUndefined()
  await step($, { ...STEP, index: 1 })

  expect(appended.length).toBe(1)
  expect(appended[0]).toContain("This notice doesn't ask you to compact before both conditions below hold")
})

test('a summed response right after a compaction leaves the thresholds to the next exact size', async ($, on) => {
  const logged: string[] = []
  const appended = withConversation(on, [52_000, 110_000, 56_000, 72_000], [], logged, () => false, [1])
  on('session.compact', () => COMPACTED)
  await $.session.start(START)
  await step($, STEP)
  expect(appended.length).toBe(1)

  await $.session.compact({ trigger: 'manual', messages: COMPACTED.messages } as never)
  // Summed: it neither sets a size nor settles which thresholds are passed.
  await step($, { ...STEP, index: 1 })
  expect(appended.length).toBe(1)
  // The exact size settles it: 56k is past the first threshold, which is
  // taken as noticed without a notice.
  await step($, { ...STEP, index: 2 })
  expect(appended.length).toBe(1)
  const linesBefore = logged.length
  // The next threshold still sends its notice.
  await step($, { ...STEP, index: 3 })
  expect(appended.length).toBe(2)
  expect(logged.length).toBeGreaterThan(linesBefore)
})

test('a summed response right after a compaction is not judged on a measured size either', async ($, on) => {
  const logged: string[] = []
  // The measurement after the compaction reports a size, as the engine's
  // does after a turn.
  let measured: number | undefined
  const appended = withConversation(
    on,
    [45_000, 62_000, 56_000, 72_000],
    [],
    logged,
    () => false,
    [1],
    () => measured,
  )
  on('session.measure', (_, e) => ({ changed: e.changed }) as never)
  on('session.compact', () => COMPACTED)
  await $.session.start(START)
  await step($, STEP)
  expect(appended).toEqual([])

  await $.session.compact({ trigger: 'manual', messages: COMPACTED.messages } as never)
  measured = 60_000
  await $.session.measure(MEASURE)
  // Summed, over a held size that is past the first threshold: it does not
  // send the notice that the exact figure after it withholds.
  await step($, { ...STEP, index: 1 })
  expect(appended).toEqual([])
  // The exact size settles it without a notice.
  await step($, { ...STEP, index: 2 })
  expect(appended).toEqual([])
  expect(logged.some(line => line.includes('right after a compaction'))).toBe(true)
  // The next threshold still sends its notice.
  await step($, { ...STEP, index: 3 })
  expect(appended.length).toBe(1)
})

test('a notification delivered into the turn before the request does not hold the compaction back', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))

  // A background task's notification that arrives while the turn runs is
  // read in that turn, unlike a typed prompt, which may be held.
  await $.prompt.submit({
    text: 'A background task finished.',
    turnId: TURN.turnId,
    origin: { kind: 'task-notification' },
  } as never)
  await $.tool.call(ASK)
  await $.turn.complete({ ...TURN, reason: 'answer' })

  expect(compacted).toEqual(['keep the plan'])
})

test('a request canceled after another source compacted tells the model it has a summary', async ($, on) => {
  withNote(on)
  const logged: string[] = []
  withSession(on, logged)
  const appended: string[] = []
  on('session.append', (_, e, next) => {
    appended.push(JSON.stringify(e.message.content))

    return next(e)
  })
  on('session.compact', () => COMPACTED)
  const submitted: string[] = []
  on('prompt.submit', (_, e) => {
    submitted.push(e.text)

    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  // The engine compacts by itself before the asking turn has ended, and the
  // person then interrupts the turn.
  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })

  expect(submitted).toEqual([])
  expect(appended.length).toBe(1)
  expect(appended[0]).toContain('is canceled, because the turn that asked for it was interrupted')
  expect(appended[0]).not.toContain('The conversation was not compacted')
  expect(appended[0]).toContain('so it now begins with a summary')
  expect(appended[0]).toContain(`/work/${PROGRESS}`)
  expect(logged.some(line => line.includes('Another source had compacted the conversation'))).toBe(true)
})

test('a tool call that cancels a request after another source compacted says so in its result', async ($, on) => {
  withNote(on)
  withSession(on)
  withTools(on)
  on('session.compact', () => COMPACTED)
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)

  const later = await $.tool.call(READ)
  expect(later.context?.length).toBe(1)
  expect(later.context?.[0]).toContain('because this tool call finished after the request was accepted')
  expect(later.context?.[0]).not.toContain('The conversation was not compacted')
  expect(later.context?.[0]).toContain(`/work/${PROGRESS}`)
  expect(later.context?.[0]).toContain('Carry on with the work.')
})

test('an owed notice is still delivered after a compaction from another source', async ($, on) => {
  withNote(on)
  withSession(on)
  withTools(on)
  // Stands for a plugin above the engine that refuses appended rows.
  on('session.append', () => ({ deny: 'rows are not accepted' }) as never)
  on('session.compact', () => COMPACTED)
  on('turn.complete', (_, e) => ({ text: e.answer }))

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  // The notice is owed when the engine compacts by itself.
  await $.session.compact({ trigger: 'auto', messages: COMPACTED.messages } as never)

  const first = await $.tool.call(READ)
  expect(first.context?.length).toBe(1)
  expect(first.context?.[0]).toContain('is canceled, because the turn that asked for it was interrupted')
})

test('a /clear discards an owed notice', async ($, on) => {
  withNote(on)
  withSession(on)
  withTools(on)
  on('session.append', () => ({ deny: 'rows are not accepted' }) as never)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('session.end', () => ({ sessionId: 's2' }) as never)

  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, isAborted: true, reason: 'aborted' })
  await $.session.end({ reason: 'clear' } as never)

  // The conversation that follows never held the request.
  expect((await $.tool.call(READ)).context).toBeUndefined()
})

test('a notes entry that is not a path, or a blank continuation, is refused', async ($, on) => {
  withNote(on)
  const refusal = async (call: Record<string, unknown>) => {
    const reply = await $.tool.call({ ...NOTES, ...call } as never)

    return String(reply.deny ?? reply.text)
  }

  // A listed entry is checked and not passed over, even beside a sound one.
  expect(await refusal({ notes: [PROGRESS, ''] })).toContain('has an entry that is not a path')
  expect(await refusal({ notes: [PROGRESS, '   '] })).toContain('has an entry that is not a path')
  expect(await refusal({ notes: [PROGRESS, 7] })).toContain('has an entry that is not a path')
  expect(await refusal({ notes: [PROGRESS], continuation: '   ' })).toMatch(/required/)
})

test('a subagent\'s turn that starts while a request is due does not drop it', async ($, on) => {
  withNote(on)
  withSession(on)
  const compacted: unknown[] = []
  on('session.compact', (_, e) => {
    compacted.push(e.instructions)

    return COMPACTED
  })
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('turn.start', (_, e) => ({ turnId: e.turnId }) as never)

  // The typed prompt leaves the request due at the turn's end.
  await $.prompt.submit(TYPED_DURING_TURN)
  expect(String((await $.tool.call(ASK)).result)).toMatch(/scheduled/)
  await $.turn.complete({ ...TURN, reason: 'answer' })
  expect(compacted).toEqual([])

  await $.turn.start({ turnId: 't2', agentId: 'a1' } as never)
  await $.session.measure(MEASURE)

  expect(compacted).toEqual(['keep the plan'])
})

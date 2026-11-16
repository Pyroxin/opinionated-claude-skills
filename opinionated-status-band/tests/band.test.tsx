import { expect, mock, test } from 'claude-code/testing'

// Each hook registered here stands for the engine beneath the mod: it
// answers what the band asks for when a session starts.
// `test` also accepts an options object in place of a body, so the body is
// picked out as the function among its second parameter's types.
type TestBody = Extract<Parameters<typeof test>[1], (...args: never[]) => unknown>
type On = Parameters<TestBody>[1]
const withSession = (on: On) => {
  mock.clock(on)
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      rateLimits: [{ kind: 'seven_day', percentUsed: 7 }],
      cost: { usd: 1.5 },
      context: {
        tokens: 50_000,
        window: 200_000,
        breakdown: { isAutoCompactEnabled: true, autoCompactThreshold: 160_000 },
      },
    } as never,
  }))
  on('session.model', () => ({ value: 'claude-test-1' }))
  on('session.turns', () => ({ value: 3 }))
  on('session.cwd', () => ({ value: '/work/project' }))
  on('session.repo', () => ({ value: null }))
  on('process.run', () => ({
    value: { exitCode: 0, stdout: 'main\n', stderr: '' } as never,
  }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
}
const START = { cwd: '/work/project', surface: 'terminal', isInteractive: true } as const
const BAND = {
  plugin: 'opinionated-status-band',
  component: 'AbovePrompt',
  requestId: 'band',
  props: {
    hasSurvey: false,
    isCollapsed: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 160,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

test('the band draws its segments on the terminal', async ($, on) => {
  withSession(on)
  await $.session.start(START)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })

  // 50k of a 160k auto-compaction threshold is 31% used, so 69% is left.
  expect(await ui.find({ type: 'Text', text: /50k\/160k/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /69% left/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /test-1/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /project/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /main/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\$1\.50 · 3 turns/ })).toBeDefined()
  await ui.unmount()
})

test('the band draws nothing of its own on other surfaces', async ($, on) => {
  withSession(on)
  await $.session.start(START)

  for (const surface of ['desktop', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })

    expect(await ui.find({ type: 'Text', text: /ctx/ })).toBeUndefined()
    await ui.unmount()
  }
})

test('the band yields to a survey', async ($, on) => {
  withSession(on)
  await $.session.start(START)

  const ui = await $.ui.mount({
    ...BAND,
    surface: 'terminal',
    props: { ...BAND.props, hasSurvey: true },
  })

  expect(await ui.find({ type: 'Text', text: /ctx/ })).toBeUndefined()
  await ui.unmount()
})

test('the band still draws when the session answers nothing about itself', async ($, on) => {
  // Every read fails. The band draws what it has, which is a placeholder
  // for the context, and the failure does not reach the session's start.
  mock.clock(on)
  const failing = () => {
    throw new Error('unavailable')
  }
  on('session.usage', failing)
  on('session.model', failing)
  on('session.turns', failing)
  on('session.cwd', failing)
  on('session.repo', failing)
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  const started = await $.session.start(START)
  expect(started.cwd).toBe('/work/project')

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /ctx/ })).toBeDefined()
  await ui.unmount()
})

// Stands for the model beneath the mod: each response reports the usage
// `responses` holds next, and lists a tool the API ran itself when that
// entry says so.
type StepUsage = { input: number; output: number; isSummed?: boolean }
const withModel = (on: On, responses: StepUsage[]) => {
  on('turn.step', async function* (_, e) {
    const { input, output, isSummed } = responses.shift() ?? { input: 0, output: 0 }

    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      usage: {
        input_tokens: input,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
        output_tokens: output,
      },
      ...(isSummed === true
        ? { serverToolUses: [{ id: 's1', name: 'advisor', input: {}, startedAt: 0, endedAt: 1 }] }
        : {}),
    } as never
  })
}
const STEP = { turnId: 't1', index: 0 as number, model: 'claude-test-1', messageCount: 1 }
// Runs one model step to its end. The test kit hands a step back as a
// stream, and the band measures once the stream has ended.
const step = async ($: Parameters<TestBody>[0], input: typeof STEP) => {
  const chunks = ($.turn.step(input) as unknown as AsyncIterable<unknown>)[Symbol.asyncIterator]()
  let chunk = await chunks.next()
  while (chunk.done !== true) chunk = await chunks.next()
}

test('the gauge shows what a response reports as used', async ($, on) => {
  withSession(on)
  withModel(on, [{ input: 78_000, output: 2_000 }])
  await $.session.start(START)
  await step($, STEP)

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /80k\/160k/ })).toBeDefined()
  await ui.unmount()
})

test('a response in which the API ran a tool adds its output and is not taken as a size', async ($, on) => {
  withSession(on)
  // The second response's usage is summed over two requests, each answered
  // over the conversation of about 80k: 161k in, 3k out.
  withModel(on, [
    { input: 78_000, output: 2_000 },
    { input: 161_000, output: 3_000, isSummed: true },
    { input: 84_000, output: 1_000 },
  ])
  await $.session.start(START)
  await step($, STEP)
  await step($, { ...STEP, index: 1 })

  // 80k held plus the 3k generated, and not the 164k sum.
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /83k\/160k/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /164k/ })).toBeUndefined()

  // The next response made by one request reports the size exactly.
  await step($, { ...STEP, index: 2 })
  expect(await ui.find({ type: 'Text', text: /85k\/160k/ })).toBeDefined()
  await ui.unmount()
})

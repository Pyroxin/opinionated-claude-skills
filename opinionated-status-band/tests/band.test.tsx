import { expect, mock, test } from 'claude-code/testing'

// Each hook registered here stands for the engine beneath the mod: it
// answers what the band asks for when a session starts.
type On = Parameters<Parameters<typeof test>[1]>[1]
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

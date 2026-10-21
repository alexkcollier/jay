import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

import { findAgent, groupsOf, parseAgents, parseWorktrees, phaseOf, summaryOf, transitions } from '../hooks/model'

const PLUGIN = 'wt-hub'
const HOME = '/Users/me'
const SHOP = '/Users/me/projects/acme/shop'
const FEATURE = '/Users/me/projects/acme/shop.feat-login'
const T0 = Date.UTC(2026, 9, 16, 15, 0)
const SELF = 'hub-0000'

const worktreeLines = [
  { client: 'acme', repo: 'shop', branch: 'master', path: SHOP, main: true, symbols: '^', task: '' },
  { client: 'acme', repo: 'shop', branch: 'feat/login', path: FEATURE, main: false, symbols: '↑', task: 'Fix the login' },
]
  .map(row => JSON.stringify(row))
  .join('\n')

type RawAgent = Record<string, unknown>

const hub: RawAgent = { sessionId: 'hub-0000', kind: 'interactive', name: 'hub', cwd: SHOP, status: 'busy', startedAt: T0 }
const worker = (state: string): RawAgent => ({
  sessionId: 'aaaa1111-2222', id: 'aaaa1111', kind: 'background', name: 'shop/login', cwd: FEATURE, status: 'busy', state, startedAt: T0,
})

function host(on: On, agents: { current: RawAgent[] }) {
  const calls: string[][] = []
  const toasts: string[] = []
  const sent: Array<{ to: unknown; text: string }> = []
  const files = new Map<string, string>()
  let status: string | undefined
  const opened: string[] = []
  on('process.run', (_$, e) => {
    calls.push([...e.argv])
    const [program = ''] = e.argv
    const ok = (stdout: string) => ({ value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } })
    if (program === '/bin/sh' && String(e.argv[2] ?? '').includes('command -v claude')) return ok(`${HOME}\t`)
    if (program.endsWith('/wt-all')) return ok(worktreeLines)
    if (program.endsWith('/claude')) return ok(JSON.stringify(agents.current))
    return ok('')
  })
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('ui.status', (_$, e) => {
    status = e.text
    return { value: undefined }
  })
  on('fs.write', (_$, e) => {
    files.set(e.path, e.text)
    return { value: undefined }
  })
  on('fs.read', (_$, e) => ({ value: files.get(e.path) ?? '' }))
  on('session.id', () => ({ value: SELF }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', () => ({ value: undefined }))
  on('session.send', (_$, e) => {
    sent.push({ to: e.to, text: e.text })
    return { isDelivered: true as const }
  })
  return { calls, toasts, sent, files, opened, status: () => status }
}

const wt = ($: Engine, args: string) =>
  $.command.run({ command: 'wt', args, origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 200 } })

describe('model', () => {
  test('phases follow the agent view fields', () => {
    expect(phaseOf('blocked', 'busy')).toBe('input')
    expect(phaseOf(null, 'waiting')).toBe('input')
    expect(phaseOf('working', 'busy')).toBe('working')
    expect(phaseOf(null, 'busy')).toBe('working')
    expect(phaseOf('working', 'idle')).toBe('waits')
    expect(phaseOf('blocked', 'idle')).toBe('input')
    expect(phaseOf('done', 'idle')).toBe('idle')
    expect(phaseOf('failed', 'idle')).toBe('failed')
  })

  test('an agent whose turn goes on while its process is idle waits, quietly', () => {
    const rows = parseWorktrees(worktreeLines)
    const busy = parseAgents(JSON.stringify([hub, worker('working')]))
    const waits = parseAgents(JSON.stringify([hub, { ...worker('working'), status: 'idle' }]))
    expect(waits.map(agent => agent.phase)).toEqual(['working', 'waits'])
    expect(summaryOf(waits, 'hub-0000')).toBe('◌ 1 waits')
    expect(transitions(busy, waits, rows, 'hub-0000', T0)).toEqual([])
    expect(transitions(waits, parseAgents(JSON.stringify([hub, worker('done')])), rows, 'hub-0000', T0).map(event => event.kind)).toEqual(['finished'])
  })

  test('bad input parses to nothing instead of throwing', () => {
    expect(parseAgents('not json')).toEqual([])
    expect(parseAgents('{"a":1}')).toEqual([])
    expect(parseWorktrees('nope\n{"path":""}\n')).toEqual([])
  })

  test('stopped agents are left out', () => {
    expect(parseAgents(JSON.stringify([{ ...worker('stopped') }]))).toEqual([])
  })

  test('transitions name the worktree and skip the hub itself', () => {
    const rows = parseWorktrees(worktreeLines)
    const before = parseAgents(JSON.stringify([hub, worker('working')]))
    const after = parseAgents(JSON.stringify([{ ...hub, status: 'waiting' }, worker('done')]))
    expect(transitions(before, after, rows, 'hub-0000', T0)).toEqual([
      { at: T0, sessionId: 'aaaa1111-2222', label: 'acme › shop · login', kind: 'finished' },
    ])
    const blocked = parseAgents(JSON.stringify([hub, worker('blocked')]))
    expect(transitions(before, blocked, rows, 'hub-0000', T0).map(event => event.kind)).toEqual(['input'])
  })

  test('groups hide an idle main checkout and keep agents with their worktree', () => {
    const rows = parseWorktrees(worktreeLines)
    const groups = groupsOf(rows, parseAgents(JSON.stringify([worker('working')])))
    expect(groups.map(group => group.rows.map(row => row.worktree.branch))).toEqual([['feat/login']])
    expect(groups[0]?.rows[0]?.agents.map(agent => agent.shortId)).toEqual(['aaaa1111'])
    expect(summaryOf(parseAgents(JSON.stringify([hub, worker('blocked')])), 'hub-0000')).toBe('✋ 1 need input')
  })

  test('agents are found by id, exact name, or the one name that holds the query', () => {
    const rows = parseAgents(JSON.stringify([hub, worker('working'), { ...worker('working'), sessionId: 'bbbb3333-4444', id: 'bbbb3333', name: 'shop/logout' }]))
    expect(findAgent(rows, 'aaaa1111')?.name).toBe('shop/login')
    expect(findAgent(rows, 'bbbb')?.name).toBe('shop/logout')
    expect(findAgent(rows, 'Shop/Login')?.shortId).toBe('aaaa1111')
    expect(findAgent(rows, 'logout')?.shortId).toBe('bbbb3333')
    expect(findAgent(rows, 'shop/log')).toBeUndefined()
    expect(findAgent(rows, 'nothing')).toBeUndefined()
  })
})

test('/wt go passes the whole name, without quotes, to wt-go', async ($, on) => {
  mock.clock(on, { now: T0 })
  const seen = host(on, { current: [] })
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await wt($, 'go "des-44 work"')
  expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/wt-go`, 'des-44 work'])
  await wt($, 'go des-44 work')
  expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/wt-go`, 'des-44 work'])
})

test('the hub polls, toasts state changes, draws the sidebar and reaches agents', async ($, on) => {
  const clock = mock.clock(on, { now: T0 })
  const agents = { current: [hub, worker('working')] }
  const seen = host(on, agents)
  const me = SELF

  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })

  const on1 = await wt($, '')
  expect(on1.text).toContain('Hub on.')
  expect(seen.opened).toEqual([])
  expect(seen.toasts).toEqual([])
  expect(seen.status()).toBe('● 1 working')

  agents.current = [hub, worker('blocked')]
  await clock.advance(3000)
  await clock.settle()
  expect(seen.toasts).toEqual(['✋ needs input: acme › shop · login'])
  expect(seen.status()).toBe('✋ 1 need input')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: PLUGIN,
      surface,
      component: 'Pane',
      requestId: 'wt-hub',
      props: { title: 'Worktrees', isFocused: true, bodyColumns: 48, placement: 'dock' } as never,
    })
    expect(await ui.find({ type: 'Text', text: /acme › shop/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Fix the login/ })).toBeDefined()
    await ui.press({ key: 'go:aaaa1111-2222' })
    expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/wt-go`, 'aaaa1111-2222'])
    await ui.press({ key: `open:${FEATURE}` })
    expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/wt-open`, FEATURE])
    await ui.unmount()
  }

  const msg = await wt($, 'msg aaaa1111 use the staging config')
  expect(msg.text).toBe('Sent to shop/login.')
  expect(seen.sent).toEqual([{ to: 'aaaa1111-2222', text: 'use the staging config' }])

  const off = await wt($, 'off')
  expect(off.text).toBe('Hub off.')
  expect(seen.status()).toBeUndefined()
  const polls = seen.calls.length
  await clock.advance(10000)
  await clock.settle()
  expect(seen.calls.length).toBe(polls)
})

test('/wt new passes the arguments through a shell to wt-new', async ($, on) => {
  mock.clock(on, { now: T0 })
  const seen = host(on, { current: [] })
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await wt($, 'new feat/x -t "Try it" -- write the tests')
  const call = seen.calls.find(argv => argv[0] === '/bin/sh' && String(argv[3] ?? '').endsWith('/wt-new'))
  expect(call?.[2]).toBe('exec "$0" feat/x -t "Try it" -- write the tests')
})

test('/wt turns the hub on with no dock pane; a finished agent toasts; /wt pane opens the dock', async ($, on) => {
  const clock = mock.clock(on, { now: T0 })
  const agents = { current: [hub, worker('working')] }
  const seen = host(on, agents)
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await wt($, '')
  expect(seen.status()).toBe('● 1 working')
  expect(seen.opened).toEqual([])
  agents.current = [hub, worker('done')]
  await clock.advance(3000)
  await clock.settle()
  expect(seen.toasts).toEqual(['✓ finished: acme › shop · login'])
  const pane = await wt($, 'pane')
  expect(pane.text).toBe('Worktree list opened in the dock.')
  expect(seen.opened).toEqual(['wt-hub'])
})

test('a headless session does not start the hub', async ($, on) => {
  mock.clock(on, { now: T0 })
  const seen = host(on, { current: [hub] })
  await $.session.start({ cwd: SHOP, surface: null, isInteractive: false })
  expect(seen.status()).toBeUndefined()
  expect(seen.calls.some(argv => argv[0]?.endsWith('/claude'))).toBe(false)
})

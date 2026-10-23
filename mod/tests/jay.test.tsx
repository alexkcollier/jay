import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

import { findAgent, groupsOf, matchAgents, nameOf, parseAgents, parseWorktrees, phaseOf, summaryOf, transitions } from '../hooks/model'

const PLUGIN = 'jay'
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
    if (program === '/bin/sh' && String(e.argv[2] ?? '').includes('"$HOME"')) return ok(HOME)
    if (program.endsWith('/jay-all')) return ok(worktreeLines)
    if (program.endsWith('/jay-agents')) return ok(JSON.stringify(agents.current))
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

const jay = ($: Engine, args: string) =>
  $.command.run({ command: 'jay', args, origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 200 } })

describe('model', () => {
  test('phases follow the agent view fields', () => {
    expect(phaseOf('blocked', 'busy')).toBe('input')
    expect(phaseOf(null, 'waiting')).toBe('input')
    expect(phaseOf('working', 'busy')).toBe('working')
    expect(phaseOf(null, 'busy')).toBe('working')
    expect(phaseOf('working', 'idle')).toBe('idle')
    expect(phaseOf('blocked', 'idle')).toBe('input')
    expect(phaseOf('done', 'idle')).toBe('idle')
    expect(phaseOf('failed', 'idle')).toBe('failed')
    // Its process is gone (no pid, no status): nobody waits for an answer.
    expect(phaseOf('blocked', null)).toBe('idle')
    expect(phaseOf('blocked', undefined)).toBe('idle')
  })

  test('a blocked agent that asks nothing gives no needs-input toast', () => {
    const rows = parseWorktrees(worktreeLines)
    // A /clear after its question: jay agents --json says idle.
    const cleared = parseAgents(JSON.stringify([hub, { ...worker('blocked'), status: 'idle', phase: 'idle' }]))
    // Its process is gone: no status.
    const detached = parseAgents(JSON.stringify([hub, { ...worker('blocked'), status: null }]))
    expect(transitions([], cleared, rows, 'hub-0000', T0)).toEqual([])
    expect(transitions([], detached, rows, 'hub-0000', T0)).toEqual([])
    expect(summaryOf(detached, 'hub-0000')).not.toContain('input')
  })

  test('the phase from jay agents --json wins: it knows what the user saw', () => {
    const rows = parseWorktrees(worktreeLines)
    const busy = parseAgents(JSON.stringify([hub, worker('working')]))
    const unread = parseAgents(JSON.stringify([hub, { ...worker('working'), status: 'idle', phase: 'unread' }]))
    expect(unread.map(agent => agent.phase)).toEqual(['working', 'unread'])
    expect(summaryOf(unread, 'hub-0000')).toBe('✓ 1 unread')
    expect(transitions(busy, unread, rows, 'hub-0000', T0).map(event => event.kind)).toEqual(['finished'])
    expect(parseAgents(JSON.stringify([{ ...worker('done'), phase: 'bogus' }]))[0]?.phase).toBe('idle')
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
    expect(summaryOf(parseAgents(JSON.stringify([hub, worker('blocked')])), 'hub-0000')).toBe('! 1 input')
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

  test('two agents with one name: the name finds neither, the id finds each, and both show the id', () => {
    const copy = { ...worker('working'), sessionId: 'cccc5555-6666', id: 'cccc5555' }
    const rows = parseAgents(JSON.stringify([hub, worker('working'), copy]))
    expect(matchAgents(rows, 'shop/login').map(agent => agent.shortId)).toEqual(['aaaa1111', 'cccc5555'])
    expect(findAgent(rows, 'shop/login')).toBeUndefined()
    expect(findAgent(rows, 'cccc5555')?.sessionId).toBe('cccc5555-6666')
    expect(rows.map(agent => nameOf(agent, rows))).toEqual(['hub', 'shop/login aaaa1111', 'shop/login cccc5555'])
    expect(matchAgents(rows, 'aaaa1111-2222').map(agent => agent.shortId)).toEqual(['aaaa1111'])
  })
})

test('/jay msg to a name that two agents share lists their ids and sends nothing', async ($, on) => {
  mock.clock(on, { now: T0 })
  const copy = { ...worker('working'), sessionId: 'cccc5555-6666', id: 'cccc5555' }
  const seen = host(on, { current: [hub, worker('working'), copy] })
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await jay($, 'refresh')
  const msg = await jay($, 'msg shop/login hello')
  expect(msg.text).toBe('Several agents match "shop/login": aaaa1111 shop/login, cccc5555 shop/login. Give an id.')
  expect(seen.sent).toEqual([])
  const one = await jay($, 'msg cccc5555 hello')
  expect(one.text).toBe('Sent to shop/login.')
  expect(seen.sent).toEqual([{ to: 'cccc5555-6666', text: 'hello' }])
})

test('/jay go passes the whole name, without quotes, to jay-go', async ($, on) => {
  mock.clock(on, { now: T0 })
  const seen = host(on, { current: [] })
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await jay($,'go "login-44 work"')
  expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/jay-go`, 'login-44 work'])
  await jay($,'go login-44 work')
  expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/jay-go`, 'login-44 work'])
})

test('the hub polls, toasts state changes, draws the sidebar and reaches agents', async ($, on) => {
  const clock = mock.clock(on, { now: T0 })
  const agents = { current: [hub, worker('working')] }
  const seen = host(on, agents)
  const me = SELF

  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })

  const on1 = await jay($,'')
  expect(on1.text).toContain('Hub on.')
  expect(seen.opened).toEqual([])
  expect(seen.toasts).toEqual([])
  expect(seen.status()).toBe('● 1 working')

  agents.current = [hub, worker('blocked')]
  await clock.advance(3000)
  await clock.settle()
  expect(seen.toasts).toEqual(['✋ needs input: acme › shop · login'])
  expect(seen.status()).toBe('! 1 input')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({
      plugin: PLUGIN,
      surface,
      component: 'Pane',
      requestId: 'jay',
      props: { title: 'Worktrees', isFocused: true, bodyColumns: 48, placement: 'dock' } as never,
    })
    expect(await ui.find({ type: 'Text', text: /acme › shop/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Fix the login/ })).toBeDefined()
    await ui.press({ key: 'go:aaaa1111-2222' })
    expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/jay-go`, 'aaaa1111-2222'])
    await ui.press({ key: `open:${FEATURE}` })
    expect(seen.calls.at(-1)).toEqual([`${HOME}/.local/bin/jay-open`, FEATURE])
    await ui.unmount()
  }

  const msg = await jay($,'msg aaaa1111 use the staging config')
  expect(msg.text).toBe('Sent to shop/login.')
  expect(seen.sent).toEqual([{ to: 'aaaa1111-2222', text: 'use the staging config' }])

  const off = await jay($,'off')
  expect(off.text).toBe('Hub off.')
  expect(seen.status()).toBeUndefined()
  const polls = seen.calls.length
  await clock.advance(10000)
  await clock.settle()
  expect(seen.calls.length).toBe(polls)
})

test('/jay new passes the arguments through a shell to jay-new', async ($, on) => {
  mock.clock(on, { now: T0 })
  const seen = host(on, { current: [] })
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await jay($,'new feat/x -t "Try it" -- write the tests')
  const call = seen.calls.find(argv => argv[0] === '/bin/sh' && String(argv[3] ?? '').endsWith('/jay-new'))
  expect(call?.[2]).toBe('exec "$0" feat/x -t "Try it" -- write the tests')
})

test('/jay turns the hub on with no dock pane; a finished agent toasts; /jay pane opens the dock', async ($, on) => {
  const clock = mock.clock(on, { now: T0 })
  const agents = { current: [hub, worker('working')] }
  const seen = host(on, agents)
  await $.session.start({ cwd: SHOP, surface: 'terminal', isInteractive: true })
  await jay($,'')
  expect(seen.status()).toBe('● 1 working')
  expect(seen.opened).toEqual([])
  agents.current = [hub, worker('done')]
  await clock.advance(3000)
  await clock.settle()
  expect(seen.toasts).toEqual(['✓ finished: acme › shop · login'])
  const pane = await jay($,'pane')
  expect(pane.text).toBe('Worktree list opened in the dock.')
  expect(seen.opened).toEqual(['jay'])
})

test('a headless session does not start the hub', async ($, on) => {
  mock.clock(on, { now: T0 })
  const seen = host(on, { current: [hub] })
  await $.session.start({ cwd: SHOP, surface: null, isInteractive: false })
  expect(seen.status()).toBeUndefined()
  expect(seen.calls.some(argv => argv[0]?.endsWith('/claude') || argv[0]?.endsWith('/jay-agents'))).toBe(false)
})

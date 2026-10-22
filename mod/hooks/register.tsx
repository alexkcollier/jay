import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AgentRow, HubEvent, WorktreeRow } from '../types'
import {
  ageOf,
  eventLine,
  findAgent,
  glyphOf,
  groupsOf,
  idOf,
  matchAgents,
  nameOf,
  parseAgents,
  parseWorktrees,
  shortBranch,
  summaryOf,
  transitions,
  unquote,
} from './model'

const PANE = 'jay'
const AGENTS_EVERY_MS = 3000
const WORKTREES_EVERY_MS = 30000

const isHub = atom({ plugin: 'jay', key: 'isHub' } as const, false)
const selfId = atom({ plugin: 'jay', key: 'selfId' } as const, '')
const worktrees = atom({ plugin: 'jay', key: 'worktrees' } as const, [] as WorktreeRow[])
const agents = atom({ plugin: 'jay', key: 'agents' } as const, [] as AgentRow[])
const events = atom({ plugin: 'jay', key: 'events' } as const, [] as HubEvent[])

const USAGE = [
  '/jay                      turn the hub on (status line, toasts)',
  '/jay pane                 show the worktree list in the dock',
  '/jay hub                  open the hub in its tab (a new one if needed): list, agent, review',
  '/jay off                  turn the hub off',
  '/jay new <branch> [-t "task"] [-n name] [-- prompt]   new worktree; with a prompt, a background agent',
  '/jay go <agent>           bring an agent in front: id, name or part of a name',
  '/jay open <branch|path>   select or open the worktree\'s Ghostty tab',
  '/jay msg <agent> <text>   send a message to an agent',
  '/jay refresh              reload worktrees and agents now',
].join('\n')

type Env = { home: string; claude: string }

let env: Env = { home: '', claude: '' }
let timers: Array<{ cancel: () => void }> = []

const bin = (name: string) => `${env.home}/.local/bin/${name}`

async function run($: EngineInterface, argv: string[], timeoutMs = 30000) {
  try {
    return await $.process.run(argv, { timeoutMs })
  } catch (error) {
    return { exitCode: 1, stdout: '', stderr: String(error), isStdoutTruncated: false, isStderrTruncated: false }
  }
}

async function shell($: EngineInterface, program: string, args: string, timeoutMs = 30000) {
  return run($, ['/bin/sh', '-c', `exec "$0" ${args}`, bin(program)], timeoutMs)
}

async function refreshWorktrees($: EngineInterface) {
  const { exitCode, stdout } = await run($, [bin('jay-all'), '--json'], 60000)
  if (exitCode === 0) await update($, worktrees, () => parseWorktrees(stdout))
}

async function refreshAgents($: EngineInterface) {
  // With each agent's phase (the list's rule); `claude agents` alone when jay-agents fails.
  let { exitCode, stdout } = await run($, [bin('jay-agents'), '--json'], 10000)
  if (exitCode !== 0) ({ exitCode, stdout } = await run($, [env.claude || `${env.home}/.local/bin/claude`, 'agents', '--json', '--all'], 10000))
  if (exitCode !== 0) return
  const next = parseAgents(stdout)
  const before = await read($, agents)
  const known = await read($, worktrees)
  const me = await read($, selfId)
  const isFirst = before.length === 0
  const fresh = isFirst ? [] : transitions(before, next, known, me, await $.clock.now())
  await update($, agents, () => next)
  if (fresh.length > 0) {
    await update($, events, list => [...fresh, ...list].slice(0, 20))
    for (const event of fresh) $.ui.toast(eventLine(event), { timeoutMs: event.kind === 'input' ? 10000 : 5000 })
  }
  $.ui.status(summaryOf(next, me))
}

async function readEnv($: EngineInterface) {
  const { stdout } = await run($, [
    '/bin/sh',
    '-c',
    'printf "%s\\t%s" "$HOME" "$(command -v claude)"',
  ])
  const [home = '', claude = ''] = stdout.split('\t')
  env = { home, claude: claude.trim() }
}

async function startHub($: EngineInterface) {
  if (timers.length > 0) return
  await refreshWorktrees($)
  await refreshAgents($)
  timers = [
    $.clock.every(AGENTS_EVERY_MS, () => refreshAgents($)),
    $.clock.every(WORKTREES_EVERY_MS, () => refreshWorktrees($)),
  ]
}

async function stopHub($: EngineInterface) {
  for (const timer of timers) timer.cancel()
  timers = []
  $.ui.status(undefined)
}

const openPane = ($: EngineInterface) => $.ui.open({ id: PANE, title: 'Worktrees' })

async function go($: EngineInterface, query: string) {
  const agent = findAgent(await read($, agents), query)
  const { exitCode, stderr } = await run($, [bin('jay-go'), agent?.sessionId ?? query])
  return exitCode === 0 ? `Brought ${agent?.name ?? query} in front.` : stderr.trim() || `jay go ${query} failed.`
}

async function openWorktree($: EngineInterface, target: string) {
  const { exitCode, stderr } = await run($, [bin('jay-open'), target])
  return exitCode === 0 ? `Opened ${target}.` : stderr.trim() || `jay open ${target} failed.`
}


export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await readEnv($)
    const id = await $.session.id()
    await update($, selfId, () => id)
    await $.command.register({
      name: 'jay',
      description: 'jay, the worktree hub: sidebar of worktrees and agents; new, go, open, msg',
      argumentHint: '[off | new <branch> [-- prompt] | go <agent> | open <branch> | msg <agent> <text> | refresh]',
    })
    if (e.isInteractive && (await read($, isHub))) await startHub($)
    return started
  })

  on('session.end', async ($, e, next) => {
    if (await read($, isHub)) await stopHub($)
    return next(e)
  })

  on('command.run', { command: 'jay' }, async ($, e) => {
    const args = e.args.trim()
    const [verb = '', ...rest] = args.split(/\s+/)
    const tail = args.slice(verb.length).trim()

    switch (verb) {
      case '': {
        await update($, isHub, () => true)
        await startHub($)
        return { text: `Hub on. ${summaryOf(await read($, agents), await read($, selfId))}.` }
      }
      case 'pane': {
        await update($, isHub, () => true)
        await startHub($)
        await openPane($)
        return { text: 'Worktree list opened in the dock.' }
      }
      case 'hub': {
        const { exitCode, stderr } = await run($, [bin('jay')])
        return { text: exitCode === 0 ? 'Hub tab in front.' : stderr.trim() || 'jay failed.' }
      }
      case 'off': {
        await update($, isHub, () => false)
        await stopHub($)
        await $.ui.close({ id: PANE })
        return { text: 'Hub off.' }
      }
      case 'refresh': {
        await refreshWorktrees($)
        await refreshAgents($)
        return { text: summaryOf(await read($, agents), await read($, selfId)) }
      }
      case 'new': {
        if (!tail) return { text: USAGE }
        const { exitCode, stdout, stderr } = await shell($, 'jay-new', tail, 600000)
        await refreshWorktrees($)
        await refreshAgents($)
        return { text: exitCode === 0 ? stdout.trim() || 'Worktree ready.' : `jay new failed:\n${stderr.trim()}` }
      }
      case 'go':
        return { text: tail ? await go($, unquote(tail)) : USAGE }
      case 'open':
        return { text: tail ? await openWorktree($, tail) : USAGE }
      case 'msg': {
        const [query = '', ...words] = rest
        const found = matchAgents(await read($, agents), query)
        if (found.length > 1) {
          const ids = found.map(one => `${idOf(one)} ${one.name}`).join(', ')
          return { text: `Several agents match "${query}": ${ids}. Give an id.` }
        }
        const agent = found[0]
        if (!agent || words.length === 0) return { text: agent ? USAGE : `No agent matches "${query}".` }
        const sent = await $.session.send({ to: { sessionId: agent.sessionId }, text: words.join(' ') })
        return { text: sent.isDelivered ? `Sent to ${agent.name}.` : `Not delivered to ${agent.name}: ${sent.reason}` }
      }
      default:
        return { text: USAGE }
    }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const me = await read($, selfId)
    const list = await read($, agents)
    const groups = groupsOf(await read($, worktrees), list)
    const recent = (await read($, events)).slice(0, 4)
    const now = await $.clock.now()
    const width = Math.max(20, e.props.bodyColumns - 4)

    return (
      <Box flexDirection="column">
        <Text bold>{summaryOf(list, me)}</Text>
        {groups.map(group => (
          <Box key={group.key} flexDirection="column" marginTop={1}>
            <Text bold color="claude">
              {group.client} › {group.repo}
            </Text>
            {group.rows.map(({ worktree, agents: mine }) => (
              <Box key={`wt:${worktree.path || group.key}`} flexDirection="column">
                {worktree.path ? (
                  <Button key={`open:${worktree.path}`} plain onPress={() => void openWorktree($, worktree.path)}>
                    {shortBranch(worktree.branch, width)} <Text dimColor>{worktree.symbols}</Text>
                  </Button>
                ) : (
                  <Text dimColor>{worktree.branch}</Text>
                )}
                {worktree.task ? (
                  <Text dimColor wrap="truncate-end">
                    {'  '}
                    {worktree.task}
                  </Text>
                ) : null}
                {mine.map(agent => (
                  <Button key={`go:${agent.sessionId}`} plain onPress={() => void go($, agent.sessionId)}>
                    {'  '}
                    <Text color={{ input: 'warning', failed: 'error', unread: 'suggestion', working: 'success', idle: 'inactive' }[agent.phase]} bold={agent.phase === 'input' || agent.phase === 'unread'} dimColor={agent.phase === 'working'}>
                      {glyphOf(agent.phase)}
                    </Text>{' '}
                    {agent.sessionId === me ? `${nameOf(agent, list)} (this)` : nameOf(agent, list)}{' '}
                    <Text dimColor>
                      {agent.kind === 'background' ? 'bg ' : ''}
                      {ageOf(agent.startedAt, now)}
                    </Text>
                  </Button>
                ))}
              </Box>
            ))}
          </Box>
        ))}
        {recent.length > 0 ? (
          <Box flexDirection="column" marginTop={1}>
            {recent.map(event => (
              <Text key={`ev:${event.sessionId}:${event.at}`} dimColor wrap="truncate-end">
                {ageOf(event.at, now)} {eventLine(event)}
              </Text>
            ))}
          </Box>
        ) : null}
      </Box>
    )
  })
}

import type { AgentRow, HubEvent, Phase, WorktreeRow } from '../types'

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const text = (value: unknown) => (typeof value === 'string' ? value : '')

const PHASES: readonly Phase[] = ['input', 'failed', 'unread', 'working', 'idle']

// The phase comes from `jay agents --json` (jay_agent_phases in jay-lib.sh), the rule of the list
// and jay all, which also knows what the user saw (unread) and which blocked agent asks nothing
// (new, or a /clear after its question). Without it, this fallback: state working with status idle
// (an agent that waits for its workers) is not working, and a blocked agent with no process (no
// status) does not need input: nobody waits for an answer.
export function phaseOf(state: unknown, status: unknown, phase?: unknown): Phase {
  if (PHASES.includes(phase as Phase)) return phase as Phase
  if (state === 'failed') return 'failed'
  if ((state === 'blocked' && status !== null && status !== undefined) || status === 'waiting') return 'input'
  if ((state === 'working' && status !== 'idle') || ((state === null || state === undefined) && status === 'busy')) return 'working'
  return 'idle'
}

export function parseAgents(json: string): AgentRow[] {
  let raw: unknown
  try {
    raw = JSON.parse(json)
  } catch {
    return []
  }
  if (!Array.isArray(raw)) return []
  return raw.filter(isRecord).flatMap(entry => {
    const sessionId = text(entry.sessionId)
    const cwd = text(entry.cwd)
    if (!sessionId || !cwd) return []
    if (entry.state === 'stopped') return []
    return [
      {
        sessionId,
        shortId: text(entry.id) || null,
        kind: entry.kind === 'background' ? 'background' : 'interactive',
        name: text(entry.name) || sessionId.slice(0, 8),
        cwd,
        phase: phaseOf(entry.state, entry.status, entry.phase),
        startedAt: typeof entry.startedAt === 'number' ? entry.startedAt : 0,
      } satisfies AgentRow,
    ]
  })
}

export function parseWorktrees(ndjson: string): WorktreeRow[] {
  return ndjson.split('\n').flatMap(line => {
    if (!line.trim()) return []
    let raw: unknown
    try {
      raw = JSON.parse(line)
    } catch {
      return []
    }
    if (!isRecord(raw) || !text(raw.path)) return []
    return [
      {
        client: text(raw.client),
        repo: text(raw.repo),
        branch: text(raw.branch),
        path: text(raw.path),
        isMain: raw.main === true,
        symbols: text(raw.symbols),
        task: text(raw.task),
      } satisfies WorktreeRow,
    ]
  })
}

export function ownerOf(cwd: string, worktrees: readonly WorktreeRow[]) {
  let best: WorktreeRow | undefined
  for (const worktree of worktrees) {
    const isInside = cwd === worktree.path || cwd.startsWith(`${worktree.path}/`)
    if (isInside && (!best || worktree.path.length > best.path.length)) best = worktree
  }
  return best
}

export function shortBranch(branch: string, width = 34) {
  const tail = branch.split('/').slice(-1)[0] ?? branch
  return tail.length > width ? `${tail.slice(0, width - 1)}…` : tail
}

export function labelOf(agent: AgentRow, worktrees: readonly WorktreeRow[]) {
  const owner = ownerOf(agent.cwd, worktrees)
  if (!owner) return agent.name
  return `${owner.client} › ${owner.repo} · ${shortBranch(owner.branch)}`
}

export function transitions(
  before: readonly AgentRow[],
  after: readonly AgentRow[],
  worktrees: readonly WorktreeRow[],
  selfId: string,
  at: number,
): HubEvent[] {
  const previous = new Map(before.map(agent => [agent.sessionId, agent]))
  return after.flatMap(agent => {
    if (agent.sessionId === selfId) return []
    const was = previous.get(agent.sessionId)
    const label = labelOf(agent, worktrees)
    const event = (kind: HubEvent['kind']): HubEvent[] => [{ at, sessionId: agent.sessionId, label, kind }]
    if (!was) return agent.phase === 'input' ? event('input') : []
    if (agent.phase === was.phase) return []
    if (agent.phase === 'input') return event('input')
    if (agent.phase === 'failed') return event('failed')
    if ((agent.phase === 'unread' || agent.phase === 'idle') && was.phase === 'working') return event('finished')
    return []
  })
}

export type Group = {
  key: string
  client: string
  repo: string
  rows: Array<{ worktree: WorktreeRow; agents: AgentRow[] }>
}

const PHASE_ORDER: Record<Phase, number> = { input: 0, failed: 1, unread: 2, working: 3, idle: 4 }

export function groupsOf(worktrees: readonly WorktreeRow[], agents: readonly AgentRow[]): Group[] {
  const byPath = new Map<string, AgentRow[]>()
  const loose: AgentRow[] = []
  for (const agent of agents) {
    const owner = ownerOf(agent.cwd, worktrees)
    if (!owner) {
      loose.push(agent)
      continue
    }
    byPath.set(owner.path, [...(byPath.get(owner.path) ?? []), agent])
  }

  const groups = new Map<string, Group>()
  for (const worktree of worktrees) {
    const mine = (byPath.get(worktree.path) ?? []).sort(
      (a, b) => PHASE_ORDER[a.phase] - PHASE_ORDER[b.phase] || b.startedAt - a.startedAt,
    )
    if (worktree.isMain && mine.length === 0) continue
    const key = `${worktree.client}/${worktree.repo}`
    const group = groups.get(key) ?? { key, client: worktree.client, repo: worktree.repo, rows: [] }
    group.rows.push({ worktree, agents: mine })
    groups.set(key, group)
  }

  const ordered = [...groups.values()].sort((a, b) => a.key.localeCompare(b.key))
  if (loose.length > 0) {
    ordered.push({
      key: 'other',
      client: 'Other',
      repo: 'no worktree',
      rows: [
        {
          worktree: { client: 'Other', repo: '', branch: 'outside a known repo', path: '', isMain: false, symbols: '', task: '' },
          agents: loose,
        },
      ],
    })
  }
  return ordered
}

export function summaryOf(agents: readonly AgentRow[], selfId: string) {
  const others = agents.filter(agent => agent.sessionId !== selfId)
  const count = (phase: Phase) => others.filter(agent => agent.phase === phase).length
  const parts = [
    count('input') && `! ${count('input')} input`,
    count('failed') && `✗ ${count('failed')} failed`,
    count('unread') && `✓ ${count('unread')} unread`,
    count('working') && `● ${count('working')} working`,
    count('idle') && `○ ${count('idle')} idle`,
  ].filter(Boolean)
  return parts.length > 0 ? parts.join(' · ') : 'No other agents'
}

export function glyphOf(phase: Phase) {
  return { input: '!', failed: '✗', unread: '✓', working: '●', idle: '○' }[phase]
}

export function ageOf(startedAt: number, now: number) {
  const minutes = Math.max(0, Math.round((now - startedAt) / 60000))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.round(minutes / 60)
  return hours < 48 ? `${hours}h` : `${Math.round(hours / 24)}d`
}

export const unquote = (value: string) => value.replace(/^(["'])(.*)\1$/, '$2')

// The agents a query names: id or session id (exact, then prefix), then the exact name, then
// the names that hold the query, in any case. Two agents can share a name when one was made
// outside the hub (the hub gives each new agent its own, see jay_unique_name).
export function matchAgents(agents: readonly AgentRow[], query: string) {
  const same = agents.filter(agent => agent.shortId === query || agent.sessionId === query)
  if (same.length > 0) return same.slice(0, 1)
  const prefix = agents.filter(agent => agent.sessionId.startsWith(query))
  if (prefix.length > 0) return prefix
  const wanted = query.toLowerCase()
  const exact = agents.filter(agent => agent.name.toLowerCase() === wanted)
  return exact.length > 0 ? exact : agents.filter(agent => agent.name.toLowerCase().includes(wanted))
}

// The one agent a query names. Several: undefined, and jay-go lists them.
export function findAgent(agents: readonly AgentRow[], query: string) {
  const found = matchAgents(agents, query)
  return found.length === 1 ? found[0] : undefined
}

export const idOf = (agent: AgentRow) => agent.shortId ?? agent.sessionId.slice(0, 8)

// The agent's name, with its id after it when another agent in the list has the same name.
export function nameOf(agent: AgentRow, agents: readonly AgentRow[]) {
  const wanted = agent.name.toLowerCase()
  const shared = agents.some(other => other.sessionId !== agent.sessionId && other.name.toLowerCase() === wanted)
  return shared ? `${agent.name} ${idOf(agent)}` : agent.name
}

export function eventLine(event: HubEvent) {
  const verb = { input: '✋ needs input', finished: '✓ finished', failed: '✗ failed' }[event.kind]
  return `${verb}: ${event.label}`
}

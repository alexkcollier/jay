import type { AgentRow, HubEvent, Phase, WorktreeRow } from '../types'

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

const text = (value: unknown) => (typeof value === 'string' ? value : '')

export function phaseOf(state: unknown, status: unknown): Phase {
  if (state === 'failed') return 'failed'
  if (state === 'blocked' || status === 'waiting') return 'input'
  if (state === 'working' || ((state === null || state === undefined) && status === 'busy')) return 'working'
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
        phase: phaseOf(entry.state, entry.status),
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
    if (agent.phase === 'idle' && was.phase === 'working') return event('finished')
    return []
  })
}

export type Group = {
  key: string
  client: string
  repo: string
  rows: Array<{ worktree: WorktreeRow; agents: AgentRow[] }>
}

const PHASE_ORDER: Record<Phase, number> = { input: 0, failed: 1, working: 2, idle: 3 }

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
    count('input') && `✋ ${count('input')} need input`,
    count('failed') && `✗ ${count('failed')} failed`,
    count('working') && `● ${count('working')} working`,
    count('idle') && `${count('idle')} idle`,
  ].filter(Boolean)
  return parts.length > 0 ? parts.join(' · ') : 'No other agents'
}

export function glyphOf(phase: Phase) {
  return { input: '✋', failed: '✗', working: '●', idle: '○' }[phase]
}

export function ageOf(startedAt: number, now: number) {
  const minutes = Math.max(0, Math.round((now - startedAt) / 60000))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.round(minutes / 60)
  return hours < 48 ? `${hours}h` : `${Math.round(hours / 24)}d`
}

export const unquote = (value: string) => value.replace(/^(["'])(.*)\1$/, '$2')

// Id or session id (prefix), then the exact name, then the one agent whose name holds the
// query, in any case. Several left: undefined, and wt-go picks or lists them.
export function findAgent(agents: readonly AgentRow[], query: string) {
  const byId = agents.find(agent => agent.shortId === query || agent.sessionId.startsWith(query))
  if (byId) return byId
  const wanted = query.toLowerCase()
  const exact = agents.filter(agent => agent.name.toLowerCase() === wanted)
  const named = exact.length > 0 ? exact : agents.filter(agent => agent.name.toLowerCase().includes(wanted))
  return named.length === 1 ? named[0] : undefined
}

export function eventLine(event: HubEvent) {
  const verb = { input: '✋ needs input', finished: '✓ finished', failed: '✗ failed' }[event.kind]
  return `${verb}: ${event.label}`
}

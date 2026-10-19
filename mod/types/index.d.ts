export type Phase = 'working' | 'input' | 'idle' | 'failed'

export type AgentRow = {
  sessionId: string
  shortId: string | null
  kind: 'interactive' | 'background'
  name: string
  cwd: string
  phase: Phase
  startedAt: number
}

export type WorktreeRow = {
  client: string
  repo: string
  branch: string
  path: string
  isMain: boolean
  symbols: string
  task: string
}

export type HubEvent = {
  at: number
  sessionId: string
  label: string
  kind: 'input' | 'finished' | 'failed'
}

declare module 'claude-code' {
  interface PluginState {
    'wt-hub': {
      isHub: boolean
      selfId: string
      worktrees: WorktreeRow[]
      agents: AgentRow[]
      events: HubEvent[]
    }
  }
}

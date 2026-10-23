# The list: rows and signs

[README](../README.md) · [Working in the hub](working.md) · [Keys](keys.md#list) ·
[Orchestrators](orchestrators.md#the-signs)

## Rows

The list shows each repo with a `.git` folder 1–2 levels under `$JAY_ROOTS` (default
`~/Documents/projects`; more roots with `:`). It shows only the Claude agents whose folder is a
root or is under one, and the hub Claude: an agent in `~/Downloads` or in `~/Documents/projects-old`
has no row and no count.

- `<root>/<client>/<repo>` goes under an orange heading for its client.
- `<root>/<repo>` goes under "Other" at the bottom.
- Under each repo (bold): its worktrees, the main checkout first (with a home sign); under each
  worktree, its agents. A repo row acts as its main checkout (`N`, `o`, click).
- A removed worktree that still has agents shows as a dim `<branch> (gone)` row of its repo.
  `d` on it removes those agents.
- Agents in no repo (but in a root, say the root itself) show under "no repo" at the bottom,
  with their folder.
- A main checkout without an agent is idle, and so is a repo with only an idle main checkout:
  both are dim. `a` hides the idle repos. The main checkout row of a repo that shows always
  stays, also when it is idle: it is the anchor of the repo's other rows (home sign, git state,
  `n` for an orchestrator).
- A worktree row: branch (last part, cut to the width), the git signs (always shown), then the
  task note in the room left.
- In a worktree that two or more agents share, each agent row ends with that agent's own task
  note (dim, in the room left; `jay new -t`). See
  [Shared worktrees](orchestrators.md#shared-worktrees).
- The hub Claude has its own row at the top, "◆ hub", not one in its folder.

Agent rows update every few seconds, git signs every 30 s.

## Signs

The status line's middle part shows the agent counts, with these signs (the list has no counts
row). The `?` footer has the Signs legend, with the
real glyphs. The Octicons are Nerd Font private-use glyphs, so this file names them by code
point.

| Sign | Meaning |
|---|---|
| `▸` (bold cyan, agent name cyan) | the agent in the middle column |
| `◆ hub` row (cyan) | the hub Claude, with its state sign |
| `◇` cyan, before the name | the repo's orchestrator: the oldest agent with the orchestrator prompt in its main checkout (also when it is in a worktree it entered) |
| `◇` yellow, before the name | a second agent with the orchestrator prompt in the same main checkout; remove it (`d`) |
| `n: orchestrator` (dim, at the end of the main checkout row) | the repo has two or more workers (agents in its other worktrees, not stopped) and no orchestrator: `n` on this row starts one. It goes when an orchestrator runs or fewer than two workers are left; a narrow list cuts it ([When to start one](orchestrators.md#when-to-start-one)) |
| `↻` (dim, after the name) | the agent runs an older Claude Code than the installed one; the list respawns it at a quiet moment ([Claude Code updates](working.md#claude-code-updates)). The status line's counts end with their count, `↻ 2` |
| `⇡` (dim, after the name; on the "◆ hub" row) | the orchestrator or the hub Claude has an older prompt than the one jay gives now (`/clear` and a respawn keep the old one); `c` on the row offers a fresh context with the current prompt ([A newer prompt: renew](orchestrators.md#a-newer-prompt-renew)) |
| `→ feat` (dim, after the age) | the agent from the main checkout is in that worktree now (`EnterWorktree`); it shows under its main checkout |
| `home gone` yellow, after the age | the folder the agent came from is gone, so it cannot wake; a pick continues it as a copy in the worktree it is in ([When the folder an agent came from goes](working.md#when-the-folder-an-agent-came-from-goes)) |
| `lost` red, after the age | the folder it came from and the worktree it was in are gone; a pick offers a copy in the main checkout, or removal |
| `!` bold yellow | agent needs input: it asks you something, or it waits for a permission. Not after a `/clear` that came after its question, and not when its process is gone (Enter on the row opens it again) |
| `✗` red | agent failed |
| `✓` bold magenta | done, unread: a turn ended after you last saw the agent |
| `●` dim green | agent works: its process is busy |
| `○` dim | idle: you saw it since its last turn, it is in the middle column now, it waits for its first prompt, or you ran `/clear` in it |
| `bg 12m` (dim, after the name) | background agent; age (m, h, d) |
| Octicon home (U+F46D), before the branch | the main checkout |
| Octicon diff (U+F440), yellow | uncommitted changes |
| `↑N` cyan | commits to push (the branch is on the remote) |
| `↓N` cyan | commits to pull (the branch is on the remote) |
| `+N` green | commits not in the default branch (the branch is not on the remote) |
| Octicon alert (U+F421), red | a merge into the default branch would conflict |
| Octicon check (U+F42E), dim | safe to remove: the branch is empty or integrated (its name is dim too) |
| Octicon git-merge (U+F419), red | conflicts now, or a rebase or merge in progress |

## Agent states

The agents sort in the order of their state signs in the table (`!`, `✗`, `✓`, `●`, `○`). An
agent whose turn goes on while its process is idle (state `working`, status `idle`: it waits
for workers it started) does not work: it is unread or idle. You see an agent when it comes
into or leaves the middle column, when `jay go` shows it, and when its turn ends while its own
Ghostty tab is in front. The Stop hook (`jay-notify`) records when a turn ends; not while the
agent has background tasks, because its turn goes on when they end. An agent with no turn since
this record started is idle. An agent that does not run (the list stopped it after
`JAY_AUTO_STOP` minutes idle, or Claude retired it) has no sign of its own: it keeps the sign of
its last turn, and a pick wakes it ([Idle agents stop](working.md#idle-agents-stop)). An agent
with no process does not need input (`!`), also when Claude still calls it blocked. The list,
`jay all`, `jay agents` and the mod use one rule
(`jay_agent_phases` in `lib/jay-lib.sh`). `c` and `d` use it too.

"On the remote" means the branch has a tracking branch, or `origin/<branch>` exists (as for a PR
pushed without `-u`). The list uses local refs only; it does not fetch.

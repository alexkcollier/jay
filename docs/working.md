# Working in the hub

[README](../README.md) · [Orchestrators](orchestrators.md) · [Review](review.md) ·
[Tasks](tasks.md) · [Keys](keys.md) · [Signs](signs.md)

- [What the hub supports](#what-the-hub-supports)
- [Start the hub](#start-the-hub)
- [Start agents in the background](#start-agents-in-the-background)
- [Pick agents and worktrees](#pick-agents-and-worktrees)
- [The middle column](#the-middle-column)
- [The hub Claude](#the-hub-claude)
- [Open your editor](#open-your-editor)
- [Notices](#notices)
- [Remove and prune](#remove-and-prune)
- [Tidy the list](#tidy-the-list)
- [Quit](#quit)

## What the hub supports

- Background agents first: `c` starts Claude as a background agent and attaches the terminal, so
  the hub can show the same agent. Plain `claude` (interactive) shows in the list too, but only
  in its own terminal; `b` moves it to the background.
- New agents from the list, in a worktree (`n`) or in a new worktree (`N`). An agent on a main
  checkout is an orchestrator: it gives each change to a worker in a new worktree
  ([Orchestrators](orchestrators.md)).
- Review by turn: hooks save the worktree after each agent turn as hidden commits. Review opens
  on the newest turn, and new turns come in by themselves ([Review](review.md)).
- Git state of each worktree at a glance: changes, commits to push or pull, merge conflicts,
  safe to remove ([Signs](signs.md)).
- Removal of agents and worktrees after a confirm (a worktree goes with its idle agents), and
  automatic prune of dead agents.
- macOS notices when an agent finishes a turn or needs input, with a click that shows the agent.
- Your editor on any file of the worktree (`O` in files).
- Dev servers in a tasks tab per worktree: their state and ports in the bar, their output
  readable by agents (`hub-run`), no port or repo config ([Tasks](tasks.md)).

## Start the hub

`wt hub` goes to the hub's Ghostty tab when the hub runs in one. Else it opens the hub in this
terminal: it attaches to a hub that answers, or it starts a fresh hub. It opens a new Ghostty tab
only when it has no terminal (an agent, a script, `/wt hub`) or runs inside another zellij
session. `--here` and `--tab` choose. See [Commands](commands.md).

## Start agents in the background

Use `c` in place of plain `claude`:

```sh
cd ~/Documents/projects/acme/shop
c                            # idle background agent, attached here
c "fix the login redirect"   # with a first prompt
```

`c` runs `claude --bg` and attaches this terminal (`claude attach`). The hub can show the same
agent. Ctrl+Z, ← or closing the tab leaves the agent running.

Plain `claude` is an interactive session of its terminal. The list shows it, but the middle
column cannot: it only says where the session runs. To move it to the background, wait until it
is idle, then press `b` on its row. After a confirm, the session ends in its tab and goes on as a
background agent with the same conversation and session id (`claude --bg --resume`). Its turn
chain stays. Its tab goes back to the shell.

From the list:

- `n` on a worktree or agent row: a new idle background agent in that worktree. On a main
  checkout, the agent is the repo's orchestrator (see [Orchestrators](orchestrators.md)). When
  the repo has one already, the hub shows that one.
- `N` on a repo, worktree or agent row: the list asks for a branch, makes a new worktree of that
  repo (`wt new <branch> --agent`) and starts an idle agent in it.

The new agent shows in the middle column, with the focus there. Type its first prompt. Agents
started by the list are named `<repo>/<branch>`.

From a shell: `wt new <branch> -- <prompt>` makes the worktree and starts the agent with a prompt.

`claude --bg` has no trust prompt: in a repo where Claude never ran, it fails with "Workspace not
trusted". Claude keeps the trust per repo, under its main checkout, for all its worktrees; a
trusted parent folder does not count. So `n`, `N` and `c` ask first, in one key (`y`), and write
the trust into `~/.claude.json` as the trust prompt of `claude` would. `wt new` does not ask.

## Pick agents and worktrees

Click a row or press Enter on it.

| Row | What the hub shows | Focus after the pick |
|---|---|---|
| background agent | the agent in the middle column; review on its turns, in its worktree | middle column |
| interactive agent | a note in the middle column (`o` goes to its tab); review on its turns | middle column |
| worktree | review (and files, when open) on that worktree | Enter: review (also a hidden one). Click: stays in the list |
| repo | the same as its main checkout | the same as a worktree |
| ◆ hub | the hub Claude in the middle column; review does not change | middle column |

▸ beside an agent marks the agent in the middle column. A pick made elsewhere (a notice click,
`wt go`, a new agent) moves the list's cursor to that agent.

A click on a pane that does not have the focus only gives it the focus (zellij). Click again to
pick.

## The middle column

You type to the agent here, as in any `claude attach`.

- Leave the agent: Ctrl+Z, or ←. In `claude attach`, ← opens Claude's agent view; in the hub the
  list is that view, so the pane stops it. The agent keeps running.
- After you leave, the pane says "You left this agent". Enter opens it again. A pick of an agent
  opens that agent.
- When `claude attach` fails at once (for example, the agent's worktree is gone), its error stays
  on screen. Enter tries again.
- The pane never closes.

## The hub Claude

A background agent named `hub`, for work across agents and repos: ask it to start agents (`wt
new`), to send a prompt to an agent, to tell you what the agents did, or to answer a question
that needs several repos. It starts in the first `WT_ROOTS` folder (the other roots are added
folders), with a short system prompt about the hub's commands (`wtl_hub_claude_prompt` in
`lib/wt-lib.sh`). It works in no worktree, so a pick of it does not change review.

- A fresh hub opens on it, with the focus in the middle column. The "◆ hub" row at the top of
  the list, or `wt go hub` from anywhere, shows it again.
- It is started the first time the hub needs it. Its id is in `~/.local/state/wt-hub-claude`.
  It is like any background agent: it keeps running when you leave it, and a stopped one opens
  again on a pick.
- It knows the orchestrators (`wt agents --orchestrators`). It sends work for a repo to the
  orchestrator of that repo (SendMessage). For a repo without one, it starts workers itself
  (`wt new`), or it tells you to press `n` on the repo's main checkout row. See
  [The hub Claude and orchestrators](orchestrators.md#the-hub-claude-and-orchestrators).
- `c` on the "◆ hub" row gives it a fresh context (see
  [Fresh context](orchestrators.md#fresh-context)). To start a new hub Claude, `claude rm <id>`:
  the next pick starts a new one.

## Open your editor

`wt-edit <file or folder>` (and `O` in files) opens the project of that path: its git root, or
outside git its folder (the file's folder). A file opens in a buffer.

- The editor is `$WT_EDITOR`, else `$VISUAL`, else `$EDITOR`, else `nvim`.
- A terminal editor runs in a new Ghostty tab in the project: `<editor> .` or
  `<editor> <file>`. When the editor quits, the tab's shell stays in the project.
- A GUI editor (`code`, `code-insiders`, `cursor`, `windsurf`, `zed`, `subl`, `idea`,
  `webstorm`, `pycharm`, `goland`, `rubymine`, `fleet`) gets `<editor> <project> [file]` and
  opens its own window.
- `WT_EDITOR_GUI=1` or `0` overrides that guess.

## Notices

The `claude-notify` hook posts a macOS notice:

- **✓ Turn finished** (Stop): the first line of the agent's last message, or its line that starts
  with `result:`, `needs input:` or `failed:`. No notice while the agent has background tasks.
- **✋ Needs input** (Notification: a permission prompt, a question, or an agent that needs input),
  with a sound.

The title is `<icon> <headline> · <client> › <repo>`; the subtitle is the branch and the task
note. macOS groups the notices of one agent.

There is no notice when Ghostty is the front app and its selected tab shows the agent: the
agent's own tab (`claude attach`, `c`, its zellij session, or an interactive session's terminal),
or the hub's tab. The hub's tab counts for every agent, whatever pane has the focus, but only
while the hub shows its "hub" tab: on a tasks tab the list is not on screen, so notices come.

A click on a notice runs `wt go <session>`: Ghostty comes to the front and shows the agent. A
background agent opens in the hub's middle column when the hub runs; else in its `claude attach`
tab (a new one if needed). An interactive session goes to its own tab. The click's output goes
to `~/.local/state/claude-notify.log`.

## Remove and prune

`d` on a row removes it after a confirm. It never forces.

- **Background agent**: `claude rm <id>`. It deletes the session and the worktree that Claude
  made for it, if any. Unpushed commits stop the removal. The transcript stays.
- **Interactive agent**: not removed. Close it in its tab, or `b` first.
- **Worktree**: `wt remove`, then `claude rm` for each idle background agent in it, then its tasks
  tab closes (the confirm names the agents and the tasks that run). The list never removes a
  main checkout. An agent that works, an interactive session, or an agent that came into the
  worktree with `EnterWorktree` (an orchestrator, say) stops the removal (the list names it).
  The branch is deleted only when it is merged. Uncommitted changes stop the removal, and then
  the agents and the tasks tab stay. A dim check sign and a dim name mark a worktree that is safe
  to remove.
- **Removed worktree** (a dim `(gone)` row): `claude rm` for each of its agents, with the same
  rules.

Dead agents are background agents whose folder is gone (a removed worktree) and that do not run
now. An agent that came into the worktree with `EnterWorktree` is not dead. The list removes
them by itself every 10 minutes, with plain `claude rm`, and logs each one in
`~/.local/state/wt-hub-prune.log`. `claude rm` keeps an agent when its recorded worktree is
still on disk (no WorktreeRemove hook here) or has unpushed work. After that, the list prunes the
turn chains of gone agents (`claude-turn-snapshot --prune`). `p` prunes the dead agents now,
after a confirm.

Idle background agents stay until you remove them.

## Tidy the list

- `a` hides the idle repos and idle main checkouts (dim rows), and shows them again. A last row
  says how many are hidden.
- `h` / `l` make the list narrower or wider. A mouse drag on the border works too. The hub keeps
  the width (`wt-hub-sidebar.pct`, 10–60 %) for its next fresh start.
- `r` reloads the list: fresh git signs now, and the list starts again as the newest version of
  `wt-sidebar` (new keys apply). Else git signs update every 30 s.

## Quit

Quit the hub: Ctrl g, then Ctrl q. The bar shows this hint when you press Ctrl g. The agents keep
running. Closing the hub's Ghostty tab only detaches it: `wt hub` attaches it again. The list has
no quit key.

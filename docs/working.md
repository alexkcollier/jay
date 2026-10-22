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
- [When the folder an agent came from goes](#when-the-folder-an-agent-came-from-goes)
- [Claude Code updates](#claude-code-updates)
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
  readable by agents (`jay run`), no port or repo config ([Tasks](tasks.md)).

## Start the hub

`jay` goes to the hub's Ghostty tab when the hub runs in one. Else it opens the hub in this
terminal: it attaches to a hub that answers, or it starts a fresh hub (the zellij session
`jay`). It opens a new Ghostty tab only when it has no terminal (an agent, a script,
`/jay hub`) or runs inside another zellij session. `--here` and `--tab` choose. See
[Commands](commands.md).

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
  repo (`jay new <branch> --agent`) and starts an idle agent in it.

The new agent shows in the middle column, with the focus there. Type its first prompt.

From a shell: `jay new <branch> -- <prompt>` makes the worktree and starts the agent with a prompt.

### Agent names

The hub gives each agent a name that no other agent has:

- An agent that the hub starts (`n`, `N`, `jay new`, `c`) is named `<repo>/<branch>` (`c` outside a
  repo: the folder's name; `c --name <name>`: that name).
- When another agent has that name, the new agent gets `<name>-2`, then `<name>-3`, ... All
  agents that `claude agents --all` lists count, also stopped and done ones. An agent that
  `claude rm` removed does not. Names match in any case.
- `b` (an interactive session goes on in the background) keeps the session's name: the session
  goes on under its own id, so no second agent comes.
- The hub Claude is `hub`, or `hub-2` when another agent has the name `hub`.

`jay_unique_name` in `lib/jay-lib.sh` does this. Two agents can still have one name when they
come from outside the hub: `claude --bg --name <name>`, or `claude --bg --resume <id>` while that
session runs (a copy). Then:

- The list and `jay agents` show the short id after the name, in both rows.
- `jay go <name>` and `/jay msg <name>` do not pick one: they say that several agents match and
  list their ids. Give the id. A pick in the list, a notice click and the mod's rows always use
  the id.

`claude --bg` has no trust prompt: in a repo where Claude never ran, it fails with "Workspace not
trusted". Claude keeps the trust per repo, under its main checkout, for all its worktrees; a
trusted parent folder does not count. So `n`, `N` and `c` ask first, in one key (`y`), and write
the trust into `~/.claude.json` as the trust prompt of `claude` would. `jay new` does not ask.

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
`jay go`, a new agent) moves the list's cursor to that agent.

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
- Type skills and slash commands here, in the agent that must run them. A skill that changes a
  branch (a commit, a push, a pull request skill) goes to the worker of that branch, not to an
  orchestrator: the orchestrator tells you which worker is ready for which command. See
  [Skills and slash commands](orchestrators.md#skills-and-slash-commands).

## The hub Claude

A background agent named `hub` (`hub-2` when another agent has that name), for work across agents and repos: ask it to start agents (`jay
new`), to send a prompt to an agent, to tell you what the agents did, or to answer a question
that needs several repos. It starts in the first `JAY_ROOTS` folder (the other roots are added
folders), with a short system prompt about the hub's commands (`jay_hub_claude_prompt` in
`lib/jay-lib.sh`). It works in no worktree, so a pick of it does not change review.

- A fresh hub opens on it, with the focus in the middle column. The "◆ hub" row at the top of
  the list, or `jay go hub` from anywhere, shows it again.
- It is started the first time the hub needs it. Its id is in `~/.local/state/jay/hub-claude`.
  When that file is lost, the hub takes on the newest agent with the hub Claude's prompt, and does
  not start a second one.
  It is like any background agent: it keeps running when you leave it, and a stopped one opens
  again on a pick.
- It knows the orchestrators (`jay agents --orchestrators`). It sends work for a repo to the
  orchestrator of that repo (SendMessage). For a repo without one, it starts workers itself
  (`jay new`), or it tells you to press `n` on the repo's main checkout row. See
  [The hub Claude and orchestrators](orchestrators.md#the-hub-claude-and-orchestrators).
- `c` on the "◆ hub" row gives it a fresh context (see
  [Fresh context](orchestrators.md#fresh-context)). To start a new hub Claude, `claude rm <id>`:
  the next pick starts a new one. A hub Claude started before the rename keeps its old prompt
  (with `wt new`, `hub-run`): the shims run those commands. A new hub Claude gets the new
  prompt.

## Open your editor

`jay edit <file or folder>` (and `O` in files) opens the project of that path: its git root, or
outside git its folder (the file's folder). A file opens in a buffer.

- The editor is `$JAY_EDITOR`, else `$VISUAL`, else `$EDITOR`, else `nvim`.
- A terminal editor runs in a new Ghostty tab in the project: `<editor> .` or
  `<editor> <file>`. When the editor quits, the tab's shell stays in the project.
- A GUI editor (`code`, `code-insiders`, `cursor`, `windsurf`, `zed`, `subl`, `idea`,
  `webstorm`, `pycharm`, `goland`, `rubymine`, `fleet`) gets `<editor> <project> [file]` and
  opens its own window.
- `JAY_EDITOR_GUI=1` or `0` overrides that guess.

## Notices

The `jay-notify` hook posts a macOS notice:

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

A click on a notice runs `jay go <session>`: Ghostty comes to the front and shows the agent. A
background agent opens in the hub's middle column when the hub runs; else in its `claude attach`
tab (a new one if needed). An interactive session goes to its own tab. The click's output goes
to `~/.local/state/jay/notify.log`.

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
  to remove. Agents that came from this worktree and are in another one now go on there first
  ([When the folder an agent came from goes](#when-the-folder-an-agent-came-from-goes)).
- **Removed worktree** (a dim `(gone)` row): `claude rm` for each of its agents, with the same
  rules.

Dead agents are background agents whose folder is gone (a removed worktree) and that do not run
now. An agent that came into the worktree with `EnterWorktree` is not dead. The list removes
them by itself every 10 minutes, with plain `claude rm`, and logs each one in
`~/.local/state/jay/prune.log`. `claude rm` keeps an agent when its recorded worktree is
still on disk (no WorktreeRemove hook here) or has unpushed work. After that, the list prunes the
turn chains of gone agents (`jay snapshot --prune`). `p` prunes the dead agents now,
after a confirm.

Idle background agents stay until you remove them.

## When the folder an agent came from goes

A background agent that went into another worktree (`EnterWorktree`) keeps the folder it
started in as its home. Claude wakes a stopped agent in its home, also when the agent was in the
other worktree. When the home is gone, the agent cannot wake: `claude attach <id>` says
"Couldn't wake <id> — Workspace not trusted. <home> could not be resolved on disk". The same
occurs with `claude --bg --resume <session id>` without options: it wakes the same agent. With
options (`--name`, `--model`), `claude --bg --resume` starts a copy: a new agent with a new id
and the same conversation. The home of the copy is the folder where it starts.

Where such an agent is now: `worktreePath` in its `state.json` when `EnterWorktree` made the
worktree. When it entered a worktree that was there already (with its path), `worktreePath` is
empty. Then the list uses the folder from `claude agents` while the agent runs, else the last
folder in its transcript.

- `d` on its home: the confirm names each such agent and the worktree it is in
  (`shop/two → ~/…/shop.b`). With `y`, each one goes on first as a copy in its worktree. An agent
  that runs stops first; one that works or waits for input stops the removal. Then the worktree
  goes, then the old entries. Thus no agent is left that cannot wake.
- In the list, a yellow `home gone` after the age marks such an agent, under the worktree it is
  in. Enter or a click on it (when it does not run) asks: `y` continues it there as a copy; `h`
  only hides the old entry (when you continued it already, say with `claude --bg --resume`
  and options). An agent that runs works on, but it cannot wake after it stops.
- A red `lost` marks one whose worktree is gone too (under the `(gone)` row of its home). A pick
  offers `m`, a copy in the repo's main checkout, or `x`, `claude rm` (the transcript stays).
- `jay go <id>` on such an agent says what to do, and exits 1. `jay go --repair <id>` continues
  it: in its worktree, or in the main checkout when that worktree is gone too.
- The copy has a new id, so its turn chain starts again. Its name is the old one when the old
  entry goes at once, else `<name>-2` (two agents never share a name).
- The old entry: `claude rm` deletes the worktree that Claude recorded for the agent
  (`worktreePath`) when git can remove it. That is the worktree where the copy works now. Thus
  the list removes the old entry only when no recorded worktree of it is on disk. Else the entry
  stays, hidden from the list (a mark `~/.local/state/jay/replaced/<old id>` with the new id). It
  goes with that worktree: `d` on the worktree, or the prune after the worktree is gone. For a
  worktree from a WorktreeCreate hook (worktrunk), `claude rm` and the agent view (ctrl+x) keep
  the entry while the worktree is on disk.

## Claude Code updates

An update puts a new `claude` binary in place (see
[Claude Code and its updates](install.md#claude-code-and-its-updates)). New agents and new
`claude attach` clients use it at once. A background agent that runs keeps the binary it
started with. A dim `↻` after its name marks such an agent, and the first row of the list (and
the bar) counts them.

With `JAY_AUTO_RESPAWN=idle` (the default), the list moves each such agent to the new binary at
a quiet moment, at most once a minute, with `claude respawn <id>`. Each respawn goes into
`~/.local/state/jay/prune.log`. With `JAY_AUTO_RESPAWN=off`, only `jay respawn` does it:

- `jay respawn`: the agents on an old binary, and why each one waits.
- `jay respawn --idle`: the list's step, now.
- `jay respawn <id or name>`: one agent, or the reason why not.
- `jay respawn --force <id>`: one agent, also when it is not quiet.

What a respawn does (tested with Claude Code 2.1.308, from that version to the same one):

- It keeps the id, the name, the conversation, the system prompt (`respawnFlags`), the folder and
  the worktree the agent entered, its crons (CronCreate) and a wakeup (ScheduleWakeup, `/loop`).
  A `claude attach` client stays connected and shows the new process. It takes about 1 s.
- It ends a turn that runs. The turn does not continue: the agent then waits like a new one.
- It stops the agent's Monitor tasks, and the agent loses the `notify_when_idle` subscriptions
  it holds: a notice that it waits for does not come. A background Bash command runs on, but the
  agent may not know it now.
- It fails when the folder that Claude wakes the agent in is gone. The old process runs on.

So an agent respawns only when all of these are true:

- Its phase is idle or unread (`○`, `✓`), and its process is idle.
- It has no background tasks, crons or wakeups (`inFlight` in its `state.json`).
- It is not in the middle column, and no `claude attach` shows it: a draft in its input box
  would go.
- The folder that Claude wakes it in is on disk, and no copy replaced it.
- The list did not respawn it in the last 10 minutes.
- An orchestrator: no other agent of its repo works or waits. The hub Claude: no other agent
  works or waits. Both can wait for idle notices from those agents.

`--force` keeps only these checks: no turn runs or waits for an answer, the folder is there, no
copy replaced it. An agent that asked you something at the end of its turn (`!`) waits until you
answer it; `jay respawn --force <id>` moves it now.

An agent that does not run (stopped, or retired by Claude after some hours idle) has no `↻`:
it wakes on the new binary. Claude's daemon also restarts itself after an update of the native
install and respawns some idle agents itself. The hub reads the version that an agent runs from
its process: the path of the binary under Claude's `claude bg-pty-host` process. `cliVersion` in
`state.json` is the version of the agent's last turn; a respawn does not change it.

## Tidy the list

- `a` hides the idle repos and idle main checkouts (dim rows), and shows them again. A last row
  says how many are hidden.
- `h` / `l` make the list narrower or wider. A mouse drag on the border works too. The hub keeps
  the width (`sidebar.pct`, 10–60 %) for its next fresh start.
- `r` reloads the list: fresh git signs now, and the list starts again as the newest version of
  `jay-sidebar` (new keys apply). Else git signs update every 30 s.

## Quit

Quit the hub: Ctrl g, then Ctrl q. The bar shows this hint when you press Ctrl g. The agents keep
running. Closing the hub's Ghostty tab only detaches it: `jay` attaches it again. The list has
no quit key.

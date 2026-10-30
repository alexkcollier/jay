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
- [Idle agents stop](#idle-agents-stop)
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
- One status line at the top of each tab: where you are, the agent counts, the tasks, the time
  (in both hubs).
- Dev servers in a tasks tab per worktree: their state in the status line (with the project that owns
  each one), their ports in `jay run ls` and their pane titles, their output readable by agents
  (`jay run`), no port or repo config ([Tasks](tasks.md)). Ctrl g `t` picks any task.
- Two multiplexers: tmux (the default) or zellij (`JAY_MUX=zellij`), with the same layout and
  keys ([tmux or zellij](install.md#tmux-or-zellij-jay_mux)).

## Start the hub

`jay` goes to the hub's Ghostty tab when the hub runs in one. Else it opens the hub in this
terminal: it attaches to a hub that answers, or it starts a fresh hub (the session `jay` on
jay's own tmux server, `tmux -L jay`). It opens a new Ghostty tab only when it has no terminal
(an agent, a script, `/jay hub`) or runs inside another tmux or zellij session. `--here` and
`--tab` choose. See [Commands](commands.md).

`JAY_MUX=zellij jay` does the same for the zellij hub (the zellij session `jay`), beside a tmux
hub if one runs. Without `JAY_MUX`, jay and the scripts use the hub that runs: see
[tmux or zellij](install.md#tmux-or-zellij-jay_mux).

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

Press Enter on a row, or double-click it. A single click only selects the row (the cursor moves
there; the keys `d`, `n`, `N`, `c`, `b`, `o` then act on it).

| Row | What the hub shows | Focus after the pick |
|---|---|---|
| background agent | the agent in the middle column; review on its turns, in its worktree | middle column |
| interactive agent | a note in the middle column (`o` goes to its tab); review on its turns | middle column |
| worktree | review (and files, when open) on that worktree | review (also a hidden one) |
| repo | the same as its main checkout | the same as a worktree |
| ◆ hub | the hub Claude in the middle column; review does not change | middle column |

▸ beside an agent marks the agent in the middle column. A pick made elsewhere (a notice click,
`jay go`, a new agent) moves the list's cursor to that agent.

A click on a pane that does not have the focus only gives it the focus (zellij): from another
column, the first click in the list only focuses it. In the tmux hub one click focuses the list
and selects the row.

A pick shows "Opening <name>..." in the middle column at once; the agent's screen follows in
about half a second (also for a long conversation: `claude attach` draws the end of it). An
agent that the list stopped wakes first, in some seconds. A pick (or `o`) that takes longer than
half a second, as at a hub start, goes on in the background, and the list reloads when it ends:
the list keeps its mouse.

Every 4 s the list makes its rows again, in the background, and compares them with the rows it
shows (`sidebar.<pid>.rows`). It reloads only when they changed (an agent's sign, a new row), and
after a pick. fzf drops a key that comes during a reload; a tick with no change does not reload,
so such a loss is rare now. When a key in the list seems to do nothing, press it again.

## The middle column

You type to the agent here, as in any `claude attach`.

- Leave the agent: Ctrl+Z, or ←. In `claude attach`, ← opens Claude's agent view; in the hub the
  list is that view, so the pane stops it. The agent keeps running.
- After you leave, the pane says "You left this agent". Enter opens it again. When the agent is
  gone by then (`claude agents` does not list it, or a copy replaced it), Enter opens the agent
  that took its place: the new agent of a `jay renew`, the copy, or for the hub Claude the
  current one (a pick of "◆ hub" does the same). With no such agent, the pane says that the agent
  is gone, and you pick another one. A pick of an agent opens that agent. A pick of the agent the pane should show opens it again whenever the pane
  does not show it (Claude's agent view, another agent opened from there, an error): the pick
  looks at the `claude attach` that really runs under the pane, not only at the pane's target.
- A background agent that does not run and has no transcript yet (it never got a prompt, then
  it stopped, or the background service went off) cannot open with `claude attach`: Claude says
  "there is nothing to resume". The pane wakes it first (`jay wake`, see
  [Idle agents stop](#idle-agents-stop)): same id, name and options. Then it attaches. An agent
  with a transcript only attaches: `claude attach` continues its conversation. The transcript:
  `linkScanPath` in the agent's `state.json`, else `<session id>.jsonl` in any folder of
  `~/.claude/projects` (`jay_transcript` in `lib/jay-lib.sh`). An agent made with a first prompt
  (`intent` in its `state.json`) whose transcript is gone is not woken: the wake would run that
  prompt again.
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
  again on a pick. A hub Claude that stopped before its first prompt has no transcript: the pick
  wakes it first (see [The middle column](#the-middle-column)).
- It knows the orchestrators (`jay agents --orchestrators`). It sends work for a repo to the
  orchestrator of that repo (SendMessage). A repo has none by default: then it plans the work
  and starts the workers itself (`jay new`): every change and every in-depth task, also a
  read-only one, goes to a worker, and the worker reports back to it (SendMessage). For long
  parallel work in one repo, it tells you to press `n` on the repo's main checkout row. See
  [The hub Claude and orchestrators](orchestrators.md#the-hub-claude-and-orchestrators).
- `c` on the "◆ hub" row gives it a fresh context (see
  [Fresh context](orchestrators.md#fresh-context)). `/clear` keeps its prompt: when jay's prompt
  is newer (a dim `⇡` on the row), `c` also offers a new hub Claude with the current prompt and
  the same name (`jay renew hub`; see
  [A newer prompt: renew](orchestrators.md#a-newer-prompt-renew)).

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
  - **Backup branches**: local branches under `backup/` that an agent made for the branch (a
    safety ref before a rebase, say). The confirm names them, and they go with the branch: when
    `wt remove` deletes it, `git branch -D` deletes them too, each only while it still points at
    the commit the confirm showed. When the branch stays (not merged), they stay. A backup
    belongs to the branch when its name is `backup/<key>` or starts with `backup/<key>` and one
    of `-` `_` `.` `/`; the keys are the branch name, its last path part, and the ticket-like
    start of that part (letters-digits): for `someone/acme-185-fix-thing`,
    `backup/someone/acme-185-fix-thing`, `backup/acme-185-fix-thing-old` and
    `backup/acme-185-pre-rebase`. Never a branch that a worktree has checked out, and never a
    name that fits a key of another worktree's branch as well (as long a key or longer):
    `backup/acme-185-pre-rebase` stays while another worktree has `acme-185` too.
    `~/.local/state/jay/prune.log` keeps each deleted backup's commit, with the
    `git branch <name> <commit>` that brings it back.
  - **Stale remote-tracking ref**: when the branch had an upstream (`origin/<branch>`) and the
    remote deleted the branch after the merge (GitHub does), its ref goes after the removal:
    `git ls-remote` asks the remote for that one branch, and when it has none,
    `git update-ref -d` drops that one ref. Never a `git fetch --prune` of the repo: other stale
    refs stay. It runs in the background (the list never waits on the network), with no
    terminal and no prompt, for at most `JAY_FETCH_TIMEOUT` seconds (20). When the remote
    still has the branch, the ref stays. When it does not answer, the ref stays and prune.log
    says why; a dropped ref is in prune.log too.
- **Removed worktree** (a dim `(gone)` row): `claude rm` for each of its agents, with the same
  rules.

From a shell or an agent, `jay rm <id or name>` stops a background agent and deletes it, and
`jay rm --self` lets an agent remove itself when its turn ends (after `wt remove` of its
worktree, say). It refuses the hub Claude, orchestrators and an agent in a turn unless
`--force`, and an agent whose recorded worktree is on disk ([Commands](commands.md)).

Dead agents are background agents whose folder is gone (a removed worktree) and that do not run
now. An agent that came into the worktree with `EnterWorktree` is not dead. The list removes
them by itself every 10 minutes, with plain `claude rm`, and logs each one in
`~/.local/state/jay/prune.log`. `claude rm` keeps an agent when its recorded worktree is
still on disk (no WorktreeRemove hook here) or has unpushed work. After that, the list prunes the
turn chains of gone agents (`jay snapshot --prune`), and runs `git worktree prune` in the hub's
repos (the repos of `jay all`): git then drops the entries of worktrees whose folder is gone,
and nothing else. `p` does the `git worktree prune` at once, and prunes the dead agents after a
confirm.

### Scratch worktrees

To compare revisions side by side (screenshots, two dev servers), an agent can make a copy in
its job folder (`$CLAUDE_JOB_DIR/tmp/<name>`). The prompts of `jay new`, the hub Claude and the
orchestrators say how: a plain copy (`git archive <rev> | tar -x -C ...`), and a worktree
(`git worktree add --detach`) only when git must work in it, which the agent removes before its
report. A git worktree under a job folder (`~/.claude/jobs/<id>/`) is a scratch worktree: its
row is dim, with the name of its folder and "scratch of <agent>" (the job's short id when no
agent of the list has that job), under the row of that agent when the agent shows in the same
repo, else in its place. It has no git signs. `jay rm` removes an agent's scratch worktrees with
the agent ([Commands](commands.md)); when a job folder goes another way, the list's
`git worktree prune` drops the entries.

Idle background agents stay in the list until you remove them. Their process stops after
`JAY_AUTO_STOP` minutes idle (see [Idle agents stop](#idle-agents-stop)); the row stays.

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

## Idle agents stop

Each background agent that runs is a full Claude Code process (350–600 MB). The list stops an
agent (`claude stop <id>`) that was idle for `JAY_AUTO_STOP` minutes (default 15, `off`: never)
and that nothing needs, at most once a minute. Each stop goes into
`~/.local/state/jay/prune.log`. The agent keeps its conversation and its row. It does not run
then, as an agent that Claude retired after some hours idle: a pick in the list, `jay go` or
`claude attach` wakes it in some seconds. `jay wake <id or name>` wakes it without opening it
and without a turn (`claude respawn`), and says `"<name>" (<id>) runs again: SendMessage reaches
it now.` In the list a stopped agent looks as before: its row and its sign (`○`, `✓`) stay.
`JAY_AUTO_STOP` is a setting in `~/.config/jay/config` ([Settings](install.md#settings)).

An agent stops only when all of these are true:

- Its process runs and is idle, its state is done or idle, and no turn runs. An agent that asks
  you something (`!`, also a permission prompt), that waits for its first prompt, that failed, or
  that says it works (an agent that waits for an idle notice from another agent says so) stays.
- It has no background tasks, crons or wakeups (`inFlight` in its `state.json`), and no child
  process other than `caffeinate`: a Bash command that runs in the background (a test run, a
  dev server) keeps it.
- It is not in the middle column of a hub (zellij or tmux), and no `claude attach` shows it.
- It is not the hub Claude and not an orchestrator: they wait for reports and idle notices.
- The folder that Claude wakes it in is on disk (else it could not wake), and no copy replaced
  it.
- Its last change (`updatedAt` in its `state.json`: a turn, a respawn), its start (a wake) and
  the last time you saw it in the hub or its turn ended are `JAY_AUTO_STOP` minutes ago or more.
- The list did not try to stop it in the last 10 minutes (`~/.local/state/jay/stopped/<id>`).

A stopped agent is not reachable for other agents (tested with Claude Code 2.1.309):

- SendMessage to it fails at once: "No agent named X is reachable". The message does not wait
  in a queue, and it does not wake the agent. The sender runs `jay wake X`, then sends again
  (see [Orchestrators](orchestrators.md#a-worker-that-does-not-run)).
- An idle notice (`notify_when_idle`) that it waits for does not come, also not after it wakes.
  The rule keeps this case out: an agent that waits for a notice says it works.
- An agent subscribed to it gets a notice at the stop: "X has exited before going idle; it will
  not process further messages at that address". A subscription to an agent that is idle fires
  at once, so after 15 idle minutes none is left.

Limits: the list sees background work only as child processes of the agent: a process that
left its tree (`nohup`, a double fork) does not count, and a stdio MCP server would keep the
agent running. A Monitor, cron or wakeup counts only through `inFlight`.

## Claude Code updates

An update puts a new `claude` binary in place (see
[Claude Code and its updates](install.md#claude-code-and-its-updates)). New agents and new
`claude attach` clients use it at once. A background agent that runs keeps the binary it
started with. A dim `↻` after its name marks such an agent, and the status line's agent counts
end with their number (`↻ 2`).

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

- `a` hides the idle repos (dim rows), and shows them again. A last row says how many are
  hidden. The main checkout row of a repo stays while the repo shows other rows, also when it is
  idle: the repo's home sign, git state and `n` are on it.
- `-` / `+` (or `=`, `+` without Shift) make the list narrower or wider. A mouse drag on the
  border works too. The hub keeps the width (`sidebar.pct`, 10–60 %) for its next fresh start.
- `r` reloads the list: fresh git signs now, and the list starts again as the newest version of
  `jay-sidebar` (new keys apply). Else git signs update every 30 s.

## Quit

The tmux hub (the default): Ctrl g, then `q` detaches this terminal; the hub, its tasks and the
agents run on, and `jay` attaches again. `tmux -L jay kill-server` ends the hub: its tasks stop,
the agents keep running. Ctrl g, Ctrl q does nothing there.

The zellij hub: Ctrl g, then Ctrl q quits it. The status line shows "Ctrl g" while zellij waits
for the key. The agents keep running.

In both, closing the hub's Ghostty tab only detaches it: `jay` attaches it again. The list has
no quit key, and fzf's own (Esc, Ctrl-C, Ctrl-G, Ctrl-Q, Ctrl-D) do nothing there.

The list, the middle column and review cannot be lost. Their programs start again when they end
(the list says "The list ended" and comes back; the tmux hub also starts a killed program again
in its pane). A pane that was closed, or that zellij holds after its program was killed, comes
back with `jay` (run it in any terminal while the hub runs), in its column at its saved width;
also the whole hub tab. In the tmux hub, Ctrl g `1` `2` `3` bring back the missing pane too.

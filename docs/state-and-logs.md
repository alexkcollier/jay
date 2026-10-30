# State and logs

[README](../README.md) · [Troubleshooting](troubleshooting.md) · [Commands](commands.md)

In `~/.local/state/jay/`:

| File | What |
|---|---|
| `layout.kdl` | the layout that `jay` writes at a fresh start (zellij hub) |
| `agent.target`, `review.target`, `files.target` | what each hub pane shows; a pick writes it |
| `agent.pane`, `review.pane`, `files.pane` | the zellij pane id and pid of each pane's `jay-pane` |
| `tmux/` | the same pane state (`agent.target`, `agent.pane`, ...) for the tmux hub: each hub keeps its own, so both can run side by side |
| `hub.lock/` | held while a pick moves the hub's panes (taken over after 5 s) |
| `hub-claude` | the short id of the hub Claude (`hub-claude.lock/` while it starts) |
| `review.mode` | `turns` or `commits` |
| `review.hidden` | there while review is hidden (Ctrl g `v`): its share of the width, and 1 when files was open (tmux: also its columns and the window's) |
| `sidebar.cols` | the list's width in columns (a drag, `-`, `+`); it stays when the window changes its size |
| `sidebar.pct` | an older version's share of the width: the list changes it to `sidebar.cols` once |
| `sidebar.hide-idle` | there while `a` hides idle repos |
| `orchestrate.<n>` | a pick started the orchestrator of a repo in `JAY_ORCHESTRATE` (one file per main checkout); for a minute, a second pick does not start another one |
| `worktrees.ndjson` | cache of `jay all --json` (refreshed after 30 s) |
| `sidebar.<pid>.sock`, `.count`, `.sum`, `.help`, `.restart`, `.rows`, `.rows.tick` | a running list: its fzf socket, row count, agent counts, `?` state, `r` flag, the rows it shows, and the rows its tick made (a reload only when they differ) |
| `sidebar.late.<pid>` | there while a pick or `o` that took over half a second goes on in the background; the list reloads when it ends |
| `turns/<id>.worktree`, `<id>.prompt`, `<id>.live` | the worktree of each turn chain; the prompt of the current turn; the time of the last live snapshot |
| `lazygit/views/<id>` | the view repo of a turn chain for lazygit review (`JAY_REVIEW=lazygit`) |
| `lazygit/state/` | the state of the hub's lazygit (its recent repos) |
| `ended/<id>`, `seen/<id>` | empty files; the time of each is when the agent's last turn ended (Stop hook; not while the agent has background tasks) and when you last saw the agent (unread sign); removed after 14 days |
| `prune.stamp` | time of the last automatic prune |
| `prune.log` | each agent the list pruned, each turn chain removed, each respawn (`jay respawn` and the list's: the versions and Claude's answer), each idle agent the list stopped (its idle minutes and Claude's answer), each `jay wake`, each `jay rm` (the stop, the scratch worktrees, the removal, with Claude's answers), and each entry that `git worktree prune` dropped |
| `stopped/<id>` | an agent that the list stopped (or tried to); its time is when (the 10-minute rule; for 2 minutes the respawn step leaves it: it wakes on the new version); removed after 14 days |
| `stop.stamp` | time of the list's last stop step (at most one each minute) |
| `respawned/<id>` | the version an agent was respawned onto; its time is when (the 10-minute rule); removed after 14 days |
| `renewed/<id>` | an agent that `jay renew` started in place of an older one: the old agent's creation time (ms), which ranks the orchestrators, then the old agent's id and the ids that it renewed (Enter in a middle column left on an old id opens this agent); removed 14 days after `claude agents` no longer lists the agent |
| `respawn.stamp` | time of the list's last respawn step (at most one each minute) |
| `claude-version` | the installed Claude Code version, under the binary's path and mtime (`claude --version` runs again after an update) |
| `notify.log` | one line per notify hook call, and the output of notice clicks |
| `tasks/<pid>.exit`, `<pid>.again`, `<pid>.stopping` | the exit code of a `jay run` pane whose command ended; a restart request; a restart that still stops the old run (the pane waits for it, at most 30 s; no output is stored) |
| `tasks/started` | a record of each task that `jay run` started (by hub server and pane id): who started it and its command line; after a hub restart, its tasks are `gone` for a day |
| `tasks/zdotdir/` | the launcher's zsh startup files: they load yours, then add its Enter |
| `tasks/console-<pane>.line` | the line the launcher typed into a console, while it runs (its name in the bar, `restart`) |
| `tasks/idle-<pane>` | when an extra console came to its prompt (it closes after 10 minutes) |
| `tasks/launcher.history` | the launcher's history, for a shell other than zsh |

The lines of `prune.log` for a stop, a wake and a `jay rm` (`<id>` is the short id, then the
agent's name, then Claude's answer on one line; "rm after its turn" for an agent that removes
itself, when the process that waits for the end of its turn starts):

```text
2026-10-23 14:05:12 a1b2c3d4 (shop/fix-login): stop after 17 min idle: <claude stop's output>
2026-10-23 14:31:40 a1b2c3d4 (shop/fix-login): wake: <claude respawn's output>
2026-10-23 15:02:07 a1b2c3d4 (shop/fix-login): rm after its turn: a process waits for the end of the turn
2026-10-23 15:02:16 a1b2c3d4 (shop/fix-login): stop for rm: <claude stop's output>
2026-10-23 15:02:16 a1b2c3d4 (shop/fix-login): scratch worktree /Users/<you>/.claude/jobs/a1b2c3d4/tmp/base: removed
2026-10-23 15:02:16 a1b2c3d4 (shop/fix-login): git worktree prune in /Users/<you>/Documents/projects/acme/shop: <git's output>
2026-10-23 15:02:17 a1b2c3d4 (shop/fix-login): rm: <claude rm's output>
2026-10-23 15:10:02 git worktree prune in /Users/<you>/Documents/projects/acme/shop: Removing worktrees/v1: gitdir file points to non-existent location
```

The last line is the list's prune (every 10 minutes, and `p`). A scratch worktree line says
"removed", or git's error when `git worktree remove --force` failed.

Before the rename, these files had other names directly in `~/.local/state` (`wt-hub-*`,
`wt-worktrees.ndjson`, `wt-turns/`, `hub-tasks/`, `claude-notify.log`, `wt-hub/`). `./install.sh`
moves them and leaves a symlink at each old path until `./install.sh --no-compat`. See
[Coming from wt-hub](install.md#coming-from-wt-hub).

Elsewhere:

- `refs/wt-turns/<id>/{base,head,live}` in each repo: the turn chains. These refs keep the old
  name: they live in each repo, and a new name would lose the old chains.
- The task note: worktrunk's state variable `task` (`wt task`, `jay new -t`). Each agent's own
  note from `jay new -t`: `~/.local/state/jay/notes/<short id>`, one line. `jay renew` moves it
  to the new id. The list's prune removes it 14 days after `claude agents` no longer lists the
  agent.
- `~/.local/share/jay/`: `zjstatus-v0.25.0.wasm` (the bar), `mod/` (the mod, with
  `--with-mod`), `installed.txt` (the files `install.sh` installed), `no-compat` (there after
  `./install.sh --no-compat`).
- `~/.claude/jobs/<id>/state.json`: Claude's own state of each background agent. The hub reads
  `respawnFlags` (the orchestrator or hub Claude prompt: `⇡` when it is not jay's now; the
  options of a copy or a renewed agent), `cwd` and `worktreePath` (a
  worktree it entered), `linkScanPath` and `resumeSessionId` (its transcript, whose last cwd
  tells where an agent is that does not run) and `needs` (an agent that waits for its first
  prompt) there. For a respawn: `tempo` (`active` while a turn runs), `inFlight` (background
  tasks, crons, wakeups), `createdAt` (it ranks orchestrators: a respawn changes `startedAt`)
  and `cliVersion` (the version of the last turn; only when the process does not tell it).
- `~/.local/state/jay/replaced/<old id>`: an old agent entry that a copy replaced (the file has
  the new id); the list hides it and removes it when its recorded worktree is gone.
- `~/.claude.json`: Claude's folder trust, which `n`, `N` and `c` can write.

Settings: `~/.config/jay/config`, and the variables that only the environment sets
(`JAY_SESSION`, the timeouts, the tmux socket): see [Settings](install.md#settings).

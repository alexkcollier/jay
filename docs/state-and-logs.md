# State and logs

[README](../README.md) · [Troubleshooting](troubleshooting.md) · [Commands](commands.md)

In `~/.local/state/jay/`:

| File | What |
|---|---|
| `layout.kdl` | the layout that `jay` writes at a fresh start |
| `agent.target`, `review.target`, `files.target` | what each hub pane shows; a pick writes it |
| `agent.pane`, `review.pane`, `files.pane` | the zellij pane id and pid of each pane's `jay-pane` |
| `hub.lock/` | held while a pick moves the hub's panes (taken over after 5 s) |
| `hub-claude` | the short id of the hub Claude (`hub-claude.lock/` while it starts) |
| `review.mode` | `turns` or `commits` |
| `review.hidden` | there while review is hidden (Ctrl g `v`): its share of the width, and 1 when files was open |
| `sidebar.pct` | the list's share of the width |
| `sidebar.hide-idle` | there while `a` hides idle rows |
| `worktrees.ndjson` | cache of `jay all --json` (refreshed after 30 s) |
| `sidebar.<pid>.sock`, `.count`, `.sum`, `.help`, `.restart` | a running list: its fzf socket, row count, agent counts, `?` state, `r` flag |
| `turns/<id>.worktree`, `<id>.prompt`, `<id>.live` | the worktree of each turn chain; the prompt of the current turn; the time of the last live snapshot |
| `lazygit/views/<id>` | the view repo of a turn chain for lazygit review (`JAY_REVIEW=lazygit`) |
| `lazygit/state/` | the state of the hub's lazygit (its recent repos) |
| `ended/<id>`, `seen/<id>` | empty files; the time of each is when the agent's last turn ended (Stop hook; not while the agent has background tasks) and when you last saw the agent (unread sign); removed after 14 days |
| `prune.stamp` | time of the last automatic prune |
| `prune.log` | each agent the list pruned, each turn chain removed, and each respawn (`jay respawn` and the list's: the versions and Claude's answer) |
| `respawned/<id>` | the version an agent was respawned onto; its time is when (the 10-minute rule); removed after 14 days |
| `respawn.stamp` | time of the list's last respawn step (at most one each minute) |
| `claude-version` | the installed Claude Code version, under the binary's path and mtime (`claude --version` runs again after an update) |
| `notify.log` | one line per notify hook call, and the output of notice clicks |
| `tasks/<pid>.exit`, `<pid>.again` | the exit code of a `jay run` pane whose command ended; a restart request (no output is stored) |
| `tasks/started` | a record of each task that `jay run` started (by hub server and pane id): who started it and its command line; after a hub restart, its tasks are `gone` for a day |
| `tasks/zdotdir/` | the launcher's zsh startup files: they load yours, then add its Enter |
| `tasks/console-<pane>.line` | the line the launcher typed into a console, while it runs (its name in the bar, `restart`) |
| `tasks/idle-<pane>` | when an extra console came to its prompt (it closes after 10 minutes) |
| `tasks/launcher.history` | the launcher's history, for a shell other than zsh |

Before the rename, these files had other names directly in `~/.local/state` (`wt-hub-*`,
`wt-worktrees.ndjson`, `wt-turns/`, `hub-tasks/`, `claude-notify.log`, `wt-hub/`). `./install.sh`
moves them and leaves a symlink at each old path until `./install.sh --no-compat`. See
[Coming from wt-hub](install.md#coming-from-wt-hub).

Elsewhere:

- `refs/wt-turns/<id>/{base,head,live}` in each repo: the turn chains. These refs keep the old
  name: they live in each repo, and a new name would lose the old chains.
- The task note: worktrunk's state variable `task` (`wt task`, `jay new -t`).
- `~/.local/share/jay/`: `zjstatus-v0.25.0.wasm` (the bar), `mod/` (the mod, with
  `--with-mod`), `installed.txt` (the files `install.sh` installed), `no-compat` (there after
  `./install.sh --no-compat`).
- `~/.claude/jobs/<id>/state.json`: Claude's own state of each background agent. The hub reads
  `respawnFlags` (the orchestrator prompt, the options of a copy), `cwd` and `worktreePath` (a
  worktree it entered), `linkScanPath` and `resumeSessionId` (its transcript, whose last cwd
  tells where an agent is that does not run) and `needs` (an agent that waits for its first
  prompt) there. For a respawn: `tempo` (`active` while a turn runs), `inFlight` (background
  tasks, crons, wakeups), `createdAt` (it ranks orchestrators: a respawn changes `startedAt`)
  and `cliVersion` (the version of the last turn; only when the process does not tell it).
- `~/.local/state/jay/replaced/<old id>`: an old agent entry that a copy replaced (the file has
  the new id); the list hides it and removes it when its recorded worktree is gone.
- `~/.claude.json`: Claude's folder trust, which `n`, `N` and `c` can write.

Settings: `~/.config/jay/config` ([Settings](install.md#settings)). Environment variables
only: `JAY_SESSION` (default `jay`), `JAY_ZELLIJ_TIMEOUT` (default 5 s).

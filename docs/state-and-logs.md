# State and logs

[README](../README.md) · [Troubleshooting](troubleshooting.md) · [Commands](commands.md)

In `~/.local/state/`:

| File | What |
|---|---|
| `wt-hub-layout.kdl` | the layout that `wt hub` writes at a fresh start |
| `wt-hub-agent.target`, `wt-hub-review.target`, `wt-hub-files.target` | what each hub pane shows; a pick writes it |
| `wt-hub-agent.pane`, `wt-hub-review.pane`, `wt-hub-files.pane` | the zellij pane id and pid of each pane's `wt-hub-pane` |
| `wt-hub.lock/` | held while a pick moves the hub's panes (taken over after 5 s) |
| `wt-hub-claude` | the short id of the hub Claude |
| `wt-hub-review.mode` | `turns` or `commits` |
| `wt-hub-review.hidden` | there while review is hidden (Ctrl g `v`): its share of the width, and 1 when files was open |
| `wt-hub-sidebar.pct` | the list's share of the width |
| `wt-hub-sidebar.hide-idle` | there while `a` hides idle rows |
| `wt-worktrees.ndjson` | cache of `wt all --json` (refreshed after 30 s) |
| `wt-sidebar.<pid>.sock`, `.count`, `.sum`, `.help`, `.restart` | a running list: its fzf socket, row count, agent counts, `?` state, `r` flag |
| `wt-turns/<id>.worktree`, `<id>.prompt`, `<id>.live` | the worktree of each turn chain; the prompt of the current turn; the time of the last live snapshot |
| `wt-hub/lazygit/views/<id>` | the view repo of a turn chain for lazygit review (`WT_REVIEW=lazygit`) |
| `wt-hub/lazygit/state/` | the state of the hub's lazygit (its recent repos) |
| `wt-hub/ended/<id>`, `wt-hub/seen/<id>` | empty files; the time of each is when the agent's last turn ended (Stop hook; not while the agent has background tasks) and when you last saw the agent (unread sign); removed after 14 days |
| `wt-hub-prune.stamp` | time of the last automatic prune |
| `wt-hub-prune.log` | each agent the list pruned, and each turn chain removed |
| `claude-notify.log` | one line per notify hook call, and the output of notice clicks |
| `hub-tasks/<pid>.exit`, `<pid>.again` | the exit code of a `hub-run` pane whose command ended; a restart request (no output is stored) |
| `hub-tasks/started` | a record of each task that `hub-run` started (by hub server and pane id): who started it and its command line; after a hub restart, its tasks are `gone` for a day |
| `hub-tasks/zdotdir/` | the launcher's zsh startup files: they load yours, then add its Enter |
| `hub-tasks/console-<pane>.line` | the line the launcher typed into a console, while it runs (its name in the bar, `restart`) |
| `hub-tasks/idle-<pane>` | when an extra console came to its prompt (it closes after 10 minutes) |
| `hub-tasks/launcher.history` | the launcher's history, for a shell other than zsh |

Elsewhere:

- `refs/wt-turns/<id>/{base,head,live}` in each repo: the turn chains.
- The task note: worktrunk's state variable `task` (`wt task`, `wt new -t`).
- `~/.local/share/wt-hub/`: `zjstatus-v0.25.0.wasm` (the bar), `mod/` (the mod, with
  `--with-mod`), `installed.txt` (the files `install.sh` installed).
- `~/.claude/jobs/<id>/state.json`: Claude's own state of each background agent. The hub reads
  `respawnFlags` (the orchestrator prompt), `cwd` and `worktreePath` (a worktree it entered) and
  `needs` (an agent that waits for its first prompt) there.
- `~/.claude.json`: Claude's folder trust, which `n`, `N` and `c` can write.

Settings: `~/.config/wt-hub/config` ([Settings](install.md#settings)). Environment variables
only: `WT_HUB_SESSION` (default `hub`), `WT_ZELLIJ_TIMEOUT` (default 5 s).

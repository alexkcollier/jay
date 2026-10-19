# wt-hub

Personal worktree and agent hub: one zellij session ("hub") with a live list of worktrees and
Claude agents across `~/Documents/projects`, the picked agent, and a review column (tuicr on the
agent's turns, yazi for files). Built on [worktrunk](https://github.com/max-sixty/worktrunk).

## Layout

| Path | Installed as | What |
|---|---|---|
| `bin/` | `~/.local/bin/<name>` (symlinks) | `wt-hub`, `wt-sidebar`, `wt-hub-pane`, `wt-go`, `wt-open`, `wt-new`, `wt-all`/`wt-pick`, `wt-agents`, `wt-setup`, `wt-hub-edit`, `claude-notify`, `claude-turn-snapshot` |
| `lib/wt-lib.sh` | `~/.local/lib/wt-lib.sh` | shared helpers (Ghostty, zellij, hub panes) |
| `mod/` | `~/mods/wt-hub` (folder marketplace `alex-wt-hub`) | Claude Code mod: `/wt`, toasts, status line |
| `config/worktrunk/config.toml` | `~/.config/worktrunk/config.toml` | worktree path, `pre-start = "wt-setup"`, Task column, aliases |
| `config/zellij/wt-hub.kdl` | `~/.config/zellij/layouts/wt-hub.kdl` | saved hub layout (`wt hub` writes its own copy) |
| `config/claude-settings-hooks.json` | merged into `~/.claude/settings.json` by hand | Stop / UserPromptSubmit / Notification hooks |

## Use

- `wt hub` — open the hub tab (starts it fresh when it is not running or does not answer).
- In the list: click / Enter picks, `v` review, `e` files, `o` own tab, `x` close viewer,
  `h`/`l` width, `r` reload, `q` quit.
- `wt go <agent>` — show an agent (id or name) in the hub.
- `wt new <branch> [-- prompt]` — new worktree, with a prompt a background agent.

State lives in `~/.local/state/` (`wt-hub.json`, `wt-hub-target`, `wt-hub-sidebar.pct`,
`wt-turns/`).

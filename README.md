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
| `config/tuicr/config.toml` | `~/.config/tuicr/config.toml` | `q_quits`: in the hub's review pane `q` goes back (the pane starts tuicr again) |
| `config/zellij/wt-hub.kdl` | `~/.config/zellij/layouts/wt-hub.kdl` | saved hub layout (`wt hub` writes its own copy) |
| `config/claude-settings-hooks.json` | merged into `~/.claude/settings.json` by hand | Stop / UserPromptSubmit / Notification hooks |

## Use

- `wt hub` — open the hub tab (starts it fresh when it is not running or does not answer).
- In the list: a pick of an agent (or "◆ hub") always moves the focus to the middle column; on a
  worktree, Enter moves it to review and a click keeps it in the list. ▸ (left) marks the agent in the
  middle column. `n` new idle agent in the row's worktree, `N` new worktree (asks the branch) +
  idle agent (`wt new -a`); type the first prompt in the middle column. `v` review, `e` files, `o` own tab, `x` close
  viewer, `d` remove the agent (`claude rm`) or worktree (`wt remove`) after a confirm, `h`/`l`
  width, `a` hide/show idle repos, `r` reload, `?` all keys, `q` quit.
- The list has a heading for each repo with a `.git` folder 1–2 levels under `$WT_ROOTS`
  (default `~/Documents/projects`; `<root>/<repo>` or `<root>/<client>/<repo>`). Under it: the
  main checkout, then the linked worktrees. A main checkout without an agent is idle, and so is a
  repo with only an idle main checkout: both are dim, and `a` hides them until you press `a` again.
- Panes (in `~/.config/zellij/config.kdl`, all sessions): `Ctrl g` then `h`/`l` column left/right,
  `1`/`2`/`3` list/middle/right column, `;` last pane.
- One pane per column: a picked agent covers the hub Claude, files (yazi) cover review. Leave
  the top program (detach, `q` in yazi), `x`, or the "◆ hub" row, and the pane under it comes back.
- `wt go <agent>` — show an agent (id or name) in the hub.
- `wt new <branch> [-- prompt]` — new worktree, with a prompt a background agent.

The bar at the bottom is [zjstatus](https://github.com/dj95/zjstatus) v0.25.0 (agent counts sent by
the list, the zellij mode when not locked, tabs, time). Install it once; without it `wt hub` uses
zellij's compact bar:

```sh
mkdir -p ~/.local/share/wt-hub && curl -fL -o ~/.local/share/wt-hub/zjstatus-v0.25.0.wasm \
  https://github.com/dj95/zjstatus/releases/download/v0.25.0/zjstatus.wasm
shasum -a 256 ~/.local/share/wt-hub/zjstatus-v0.25.0.wasm  # 282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe
```

On its first start zellij asks for its permissions in the bar: click the bar and press `y`.

State lives in `~/.local/state/` (`wt-hub.json`, `wt-hub-<role>.target|.pane`, `wt-hub-sidebar.pct`,
`wt-hub-sidebar.hide-idle`,
`wt-turns/`).

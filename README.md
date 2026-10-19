# wt-hub

Personal worktree and agent hub: one zellij session ("hub") with a live list of worktrees and
Claude agents across `~/Documents/projects`, the picked agent, and a review column (tuicr on the
agent's turns, yazi for files). Built on [worktrunk](https://github.com/max-sixty/worktrunk).

## Layout

| Path | Installed as | What |
|---|---|---|
| `bin/` | `~/.local/bin/<name>` (symlinks) | `wt-hub`, `wt-sidebar`, `wt-hub-pane`, `wt-go`, `wt-open`, `wt-new`, `wt-all`/`wt-pick`, `wt-agents`, `wt-setup`, `wt-hub-edit`, `wt-hub-keys`, `claude-notify`, `claude-turn-snapshot` |
| `lib/wt-lib.sh` | `~/.local/lib/wt-lib.sh` | shared helpers (Ghostty, zellij, hub panes) |
| `mod/` | `~/mods/wt-hub` (folder marketplace `alex-wt-hub`) | Claude Code mod: `/wt`, toasts, status line |
| `config/worktrunk/config.toml` | `~/.config/worktrunk/config.toml` | worktree path, `pre-start = "wt-setup"`, Task column, aliases |
| `config/tuicr/config.toml` | `~/.config/tuicr/config.toml` | `q_quits`: in the hub's review pane `q` goes back (the pane starts tuicr again) |
| `config/zellij/wt-hub.kdl` | `~/.config/zellij/layouts/wt-hub.kdl` | saved hub layout (`wt hub` writes its own copy) |
| `config/claude-settings-hooks.json` | merged into `~/.claude/settings.json` by hand | Stop / UserPromptSubmit / Notification hooks |

## Install

The repo must stay at `~/Documents/projects/wt-hub`: the install is symlinks into it, so an edit
is live at once. Every step can run again safely.

1. Tools (macOS, Homebrew): `brew install worktrunk zellij fzf jq tuicr`. Versions in use:
   worktrunk 0.80, zellij 0.45.1, fzf 0.74 (the list needs `--footer`), jq 1.7, tuicr 0.27.
   `mise use -g yazi` (the hub panes find it in `~/.local/share/mise/shims`). `wt-hub-keys` runs
   on `/usr/bin/python3` (Xcode Command Line Tools); the zellij timeout wrapper uses `perl`.
2. Links. A new script in `bin/` needs this step too:

   ```sh
   cd ~/Documents/projects/wt-hub
   mkdir -p ~/.local/bin ~/.local/lib ~/mods ~/.config/worktrunk ~/.config/tuicr ~/.config/zellij/layouts
   for f in bin/*; do [ -f "$f" ] && ln -sfn "$PWD/$f" ~/.local/bin/; done
   ln -sfn "$PWD/lib/wt-lib.sh" ~/.local/lib/wt-lib.sh
   ln -sfn "$PWD/mod" ~/mods/wt-hub
   ln -sfn "$PWD/config/worktrunk/config.toml" ~/.config/worktrunk/config.toml
   ln -sfn "$PWD/config/tuicr/config.toml" ~/.config/tuicr/config.toml
   ln -sfn "$PWD/config/zellij/wt-hub.kdl" ~/.config/zellij/layouts/wt-hub.kdl
   ```

   `ln -sfn` replaces a file of the same name in place: look first if one is not a link
   (`ls -l ~/.config/worktrunk/config.toml`). `~/.local/bin` must be on PATH.
3. Claude Code: add the hooks in `config/claude-settings-hooks.json` to the `hooks` in
   `~/.claude/settings.json` (merge by hand, keep the hooks that are there). Then the mod and
   worktrunk's plugin:

   ```sh
   claude plugin marketplace add ~/mods/wt-hub && claude plugin install wt-hub@alex-wt-hub
   claude plugin marketplace add max-sixty/worktrunk && claude plugin install worktrunk@worktrunk
   ```
4. Pane keys: in `~/.config/zellij/config.kdl` (not in this repo), in the `keybinds` block, with
   `Ctrl g` in `locked` set to `SwitchToMode "normal"`:

   ```kdl
   normal {
       bind "h" { MoveFocus "left"; SwitchToMode "locked"; }
       bind "l" { MoveFocus "right"; SwitchToMode "locked"; }
       bind "1" { MoveFocus "left"; MoveFocus "left"; SwitchToMode "locked"; }
       bind "2" { MoveFocus "left"; MoveFocus "left"; MoveFocus "right"; SwitchToMode "locked"; }
       bind "3" { MoveFocus "right"; MoveFocus "right"; SwitchToMode "locked"; }
       bind ";" { FocusLastPane; SwitchToMode "locked"; }
   }
   ```
5. The bar at the bottom is [zjstatus](https://github.com/dj95/zjstatus) v0.25.0 (agent counts
   sent by the list, the zellij mode when not locked, tabs, time). Without it `wt hub` uses
   zellij's compact bar:

   ```sh
   mkdir -p ~/.local/share/wt-hub && curl -fL -o ~/.local/share/wt-hub/zjstatus-v0.25.0.wasm \
     https://github.com/dj95/zjstatus/releases/download/v0.25.0/zjstatus.wasm
   shasum -a 256 ~/.local/share/wt-hub/zjstatus-v0.25.0.wasm  # 282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe
   ```

   On its first start zellij asks for its permissions in the bar: click the bar and press `y`.
6. Check: `ls -l ~/.local/bin | grep projects/wt-hub/bin` shows each `bin/` script as a link
   into this repo; `wt hub` opens the hub.

## Use

- `wt hub` — open the hub tab (starts it fresh when it is not running or does not answer).
- In the list: a pick of an agent (or "◆ hub") always moves the focus to the middle column; on a
  worktree, Enter moves it to review and a click keeps it in the list. ▸ (left) marks the agent in the
  middle column. `n` new idle agent in the row's worktree, `N` new worktree (asks the branch) +
  idle agent (`wt new -a`); type the first prompt in the middle column. `v` review, `e` files, `o` own tab,
  `t` review turns ⇄ commits, `d` remove the agent (`claude rm`) or worktree (`wt remove`) after a confirm, `h`/`l`
  width, `a` hide/show idle repos, `r` reload, `?` all keys, `q` quit.
- The list shows each repo with a `.git` folder 1–2 levels under `$WT_ROOTS` (default
  `~/Documents/projects`): `<root>/<client>/<repo>` under a heading for its client,
  `<root>/<repo>` under "Other" at the bottom (with the agents outside every worktree). A repo row
  is the repo with its main checkout (`n` starts an agent there); its agents and linked worktrees
  go under it. A repo with only its main checkout and no agent is idle: dim, and `a` hides it until
  you press `a` again.
- Panes (in `~/.config/zellij/config.kdl`, all sessions): `Ctrl g` then `h`/`l` column left/right,
  `1`/`2`/`3` list/middle/right column, `;` last pane.
- One pane per column: a picked agent covers the hub Claude, files (yazi) cover review. Leave
  the top program (detach, `q` in yazi) or pick the "◆ hub" row, and the pane under it comes back.
- Review (tuicr) has two modes; the pane title starts with the mode. **turns**: the agent's turn
  chain, one commit per turn plus "between turns" commits for your own edits, opened on the last
  turn. **commits**: merge-base with `origin/HEAD`/`main`/`master` up to `HEAD`. `t` in tuicr (in
  NORMAL or SELECT mode) or in the list toggles the mode; `q` in tuicr goes back to its start.
- Turn chains: the `claude-turn-snapshot` hooks (UserPromptSubmit, Stop) save the worktree at each
  turn as hidden commits under `refs/wt-turns/<agent8>/{base,head}`. They never touch the branch,
  the index or the files. A chain stays with its agent after a resume or `/clear`.
- `wt go <agent>` — show an agent (id or name) in the hub.
- `wt new <branch> [-- prompt]` — new worktree, with a prompt a background agent.

State lives in `~/.local/state/` (`wt-hub.json`, `wt-hub-<role>.target|.pane`, `wt-hub-sidebar.pct`,
`wt-hub-sidebar.hide-idle`, `wt-hub-review.mode`, `wt-turns/` with the worktree of each chain).

Open items and known faults: [TODO.md](TODO.md).

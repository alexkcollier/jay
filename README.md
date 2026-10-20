# wt-hub

Personal worktree and agent hub: one zellij session ("hub") with a live list of worktrees and
Claude agents across `~/Documents/projects`, the picked agent, and a review column (tuicr on the
agent's turns, yazi for files). Built on [worktrunk](https://github.com/max-sixty/worktrunk).

## Layout

| Path | Installed as | What |
|---|---|---|
| `bin/` | `~/.local/bin/<name>` (symlinks) | `c`, `wt-hub`, `wt-sidebar`, `wt-hub-pane`, `wt-go`, `wt-open`, `wt-new`, `wt-all`/`wt-pick`, `wt-agents`, `wt-setup`, `wt-edit`, `wt-hub-keys`, `claude-notify`, `claude-turn-snapshot` |
| `lib/wt-lib.sh` | `~/.local/lib/wt-lib.sh` | shared helpers (Ghostty, zellij, hub panes) |
| `mod/` | `~/mods/wt-hub` (folder marketplace `alex-wt-hub`) | Claude Code mod: `/wt`, toasts, status line in any interactive session that turns it on (the hub no longer runs a Claude) |
| `config/worktrunk/config.toml` | `~/.config/worktrunk/config.toml` | worktree path, `pre-start = "wt-setup"`, Task column, aliases |
| `config/yazi/keymap.toml` | `~/.config/wt-hub/yazi/` (folder link) | hub-only yazi keys: `e` back to review, `o` open in your editor (`wt-edit`) |
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
   mkdir -p ~/.local/bin ~/.local/lib ~/mods ~/.config/worktrunk ~/.config/tuicr ~/.config/zellij/layouts ~/.config/wt-hub
   for f in bin/*; do [ -f "$f" ] && ln -sfn "$PWD/$f" ~/.local/bin/; done
   ln -sfn "$PWD/lib/wt-lib.sh" ~/.local/lib/wt-lib.sh
   ln -sfn "$PWD/mod" ~/mods/wt-hub
   ln -sfn "$PWD/config/worktrunk/config.toml" ~/.config/worktrunk/config.toml
   ln -sfn "$PWD/config/tuicr/config.toml" ~/.config/tuicr/config.toml
   ln -sfn "$PWD/config/yazi" ~/.config/wt-hub/yazi
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

- `wt hub` — go to the hub's Ghostty tab when it has one, else open the hub in this terminal
  (fresh when it is not running or does not answer). A new tab only without a terminal (an
  agent, `/wt hub`) or from inside another zellij session; `--tab` / `--here` choose.
  Quit the hub: `Ctrl g`, then `Ctrl q` (the agents keep running). Closing its tab only
  detaches it; `wt hub` attaches it again.
- In the list: a pick of an agent always moves the focus to the middle column; on a
  worktree, Enter moves it to review and a click keeps it in the list. ▸ (beside the agent) marks the agent in the
  middle column. An interactive agent (not `bg`) runs in its own terminal: the middle column
  only says so, review shows its turns, `o` goes to its Ghostty tab, and `b` (idle only, after a
  confirm) ends it there and continues it as a background agent with the same conversation
  (`claude --bg --resume`). `n` new idle agent in the row's worktree, `N` new worktree (asks the branch) +
  idle agent (`wt new -a`); type the first prompt in the middle column. `o` own tab,
  `d` remove the agent (`claude rm`) or worktree (`wt remove`) after a confirm, `h`/`l`
  width, `a` hide/show idle repos, `p` prune dead agents, `?` all keys (one per line, then the
  pane moves and the signs under their own headings). `r` reload this agent list: the git signs at once (else
  every 30 s; agent rows every few seconds), and the list starts again as the newest version of
  `wt-sidebar`, so new keys apply. The list has no quit key.
- The list shows each repo with a `.git` folder 1–2 levels under `$WT_ROOTS` (default
  `~/Documents/projects`): `<root>/<client>/<repo>` under a heading for its client,
  `<root>/<repo>` under "Other" at the bottom. Under each repo: its worktrees, the main checkout
  first, and under each worktree its agents. An agent whose worktree was removed shows under a dim
  "<branch> (gone)" row of its repo; agents in no repo show under "no repo" at the bottom. The
  list prunes the dead agents (background, folder gone, not running) with plain `claude rm`
  every 10 minutes (log `~/.local/state/wt-hub-prune.log`), and `p` does it now after a confirm.
  Their transcripts stay. `claude rm` also removes the worktree Claude recorded for the agent,
  which can differ from its folder; it keeps the agent when that worktree is on disk without a
  WorktreeRemove hook, or has unpushed work. A repo row acts as its main checkout (`N`, `o`, click). A main
  checkout without an agent is idle, and so
  is a repo with only an idle main checkout: both are dim, and `a` hides them until you press `a`
  again.
- Git signs after each worktree (Nerd Font Octicons, and plain `↑ ↓ +` for counts; legend at
  the end of `?`): uncommitted changes (yellow); when the branch is on the remote (its tracking
  branch, else `origin/<branch>`, as for a PR) the commits to push `↑N` / to pull `↓N` (cyan),
  else the commits not in the default branch `+N` (green); a merge into the
  default branch would conflict (red), safe to remove (dim check; the branch is empty or
  integrated, and its name is dim), conflicts now or a rebase/merge in progress (red). The signs
  always show: a long branch name is cut to the list's width, and the task note shows only in the
  room left.
- Panes (in `~/.config/zellij/config.kdl`, all sessions): `Ctrl g` then `h`/`l` column left/right,
  `1`/`2`/`3` list/middle/right column, `;` last pane.
- One pane per column: the middle column always shows the picked agent (`claude attach`); there
  is no hub Claude. Leave the agent (Ctrl+Z, or ←: Claude's agent view, which the list replaces
  here) and it keeps running; Enter or a new pick opens it again. When an agent cannot be
  opened (its worktree is gone), its error stays in the middle column. Files (yazi) cover
  review; `q` in yazi brings review back.
- macOS notices (claude-notify): none while Ghostty is in front with a tab that shows the agent
  selected: its own tab (`claude attach`/`c`, its zellij session, an interactive session's
  terminal) or the hub, whose list shows every agent. A click brings Ghostty to the front and
  shows the agent in the hub (or its own tab); the click's output goes to `claude-notify.log`.
- Review ⇄ files: `e` in tuicr (NORMAL or SELECT mode) shows files over review, `e` (or `q`) in
  yazi goes back. tuicr keeps running under yazi. tuicr's own `e` (exclude filter) is not
  available in the hub; its `i` (include filter) and `:` commands still work. The pane title
  ends with the pane's keys (`e files · t commits`, `e review · o editor`). `o` in yazi opens the hovered
  file or folder in your editor, in its project: `wt-edit <path>` (below).
- Review (tuicr) has two modes; the pane title starts with the mode. **turns**: the agent's turn
  chain, one commit per turn plus "between turns" commits for your own edits, opened on the last
  turn. **commits**: merge-base with `origin/HEAD`/`main`/`master` up to `HEAD`. `t` in tuicr (in
  NORMAL or SELECT mode) toggles the mode; `q` in tuicr goes back to its start. The list's keys
  act in the list only, so it has no key for review's mode or for files. New turns (in commits
  mode, new commits) come in by themselves: tuicr starts again on the newest turn, but not
  while you type a comment or a `:`/`/` prompt (it waits until you are back in NORMAL).
- Turn chains: the `claude-turn-snapshot` hooks (UserPromptSubmit, Stop) save the worktree at each
  turn as hidden commits under `refs/wt-turns/<agent8>/{base,head}`. They never touch the branch,
  the index or the files. A chain stays with its agent after a resume or `/clear`.
- `c [claude --bg options] [prompt]` — Claude in this folder as a background agent, shown in this
  terminal (`claude --bg`, then `claude attach`). Use it in place of plain `claude`: the hub can
  show the agent too, and Ctrl+Z or closing the tab leaves it running. Plain `claude` stays an
  interactive session of its terminal, which the hub cannot show.
- `wt-edit <file or folder>` — open it in your editor, in its project (git root; outside git its
  folder). A folder opens the project; a file opens the project with the file in a buffer.
  Editor: `$WT_EDITOR`, else `$VISUAL`, else `$EDITOR`, else nvim. A terminal editor runs in a
  new Ghostty tab in the project (`<editor> .` or `<editor> <file>`); a GUI editor (VS Code,
  Cursor, Zed, Sublime, JetBrains) gets `<editor> <project> [file]`. `WT_EDITOR_GUI=1|0`
  overrides the guess.
- `wt go <agent>` — show an agent (id or name) in the hub.
- `wt new <branch> [-- prompt]` — new worktree, with a prompt a background agent.

State lives in `~/.local/state/` (`wt-hub-<role>.target|.pane`, `wt-hub-sidebar.pct`,
`wt-hub-sidebar.hide-idle`, `wt-hub-review.mode`, `wt-turns/` with the worktree of each chain).

Open items and known faults: [TODO.md](TODO.md).

# wt-hub

Alex's worktree and agent hub. One zellij session, "hub", shows three columns: a live list of the
worktrees and Claude agents across `~/Documents/projects`, the picked agent, and a review of that
agent's work (tuicr on its turns, or yazi on its files). Built on
[worktrunk](https://github.com/max-sixty/worktrunk) and Claude Code background agents.

This repo is the live install: `~/.local/bin`, `~/.local/lib`, `~/mods/wt-hub` and the configs are
symlinks into it, so an edit is live at once. Open items and known faults: [TODO.md](TODO.md).
Rules for edits: [CLAUDE.md](CLAUDE.md).

- [What the hub is](#what-the-hub-is)
- [Requirements](#requirements)
- [Install](#install)
- [How to work in the hub](#how-to-work-in-the-hub)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [The list: rows and signs](#the-list-rows-and-signs)
- [Commands](#commands)
- [State and logs](#state-and-logs)
- [Troubleshooting](#troubleshooting)
- [Repo layout](#repo-layout)

## What the hub is

```
┌ worktrees ─────────────┬ shop/fix-login ────────────┬ turns · shop   e files · t commits ───┐
│ ● 1 working  ○ 2 idle  │                            │                                        │
│                        │  the picked agent:         │  review of the agent's turns (tuicr)   │
│ acme                   │  claude attach <id>        │                                        │
│  shop                  │                            │            e ⇅ e / q                   │
│   main                 │  type to the agent here    │                                        │
│   fix-login  ↑2        │                            │  files of the worktree (yazi),         │
│     ▸ ● shop/fix-login │  Ctrl+Z or ←: leave it     │  over review                           │
│                        │  (it keeps running)        │                                        │
│ ⏎ open  n new  d remove│                            │                                        │
│ ? all keys and signs   │                            │                                        │
├────────────────────────┴────────────────────────────┴────────────────────────────────────────┤
│ ◆ hub  ● 1 working  ○ 2 idle                                                    hub │ 14:05 │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
  list (wt-sidebar, fzf)    agent viewer (wt-hub-pane agent)   review ⇄ files (wt-hub-pane review/files)
```

- **List** (left, about 22 % of the width). Every repo, worktree and agent, grouped by client.
  Agent rows update every few seconds, git signs every 30 s. A pick here drives the other two
  columns.
- **Agent viewer** (middle). `claude attach` on the picked background agent. You talk to the agent
  here. The pane title is the agent's name. There is no "hub Claude": this pane only shows agents.
- **Review** (right). tuicr on the picked agent's turns (one commit per turn), or on the branch's
  commits. **Files** (yazi in the same worktree) opens over review and closes back to it.
- **Bar** (bottom, zjstatus). `◆ hub`, the agent counts from the list, the zellij mode when it is
  not locked, the tabs and the time.

The hub supports:

- Background agents first: `c` starts Claude as a background agent and attaches the terminal, so
  the hub can show the same agent. Plain `claude` (interactive) shows in the list too, but only
  in its own terminal; `b` moves it to the background.
- New agents from the list, in a worktree (`n`) or in a new worktree (`N`).
- Review by turn: hooks save the worktree after each agent turn as hidden commits. Review opens
  on the newest turn, and new turns come in by themselves.
- Git state of each worktree at a glance: changes, commits to push or pull, merge conflicts,
  safe to remove.
- Removal of agents and worktrees after a confirm, and automatic prune of dead agents.
- macOS notices when an agent finishes a turn or needs input, with a click that shows the agent.
- Your editor on any file of the worktree (`O` in files).

## Requirements

Versions installed now (2026-10-20). The hub is macOS only: it drives Ghostty tabs through
AppleScript and reads the front app with `lsappinfo`.

| Tool | Version now | From | Used for |
|---|---|---|---|
| macOS | 27.0.1 | | `osascript`, `lsappinfo`, `stat -f`, `cp -c` |
| Ghostty | 1.3.2 (1.3+) | ghostty.org | tabs through AppleScript: `wt hub`, `wt go`, `wt open`, `wt-edit`, notices |
| zellij | 0.45.1 | `brew install zellij` | the hub session; the scripts use 0.45 behavior (see CLAUDE.md) |
| zjstatus | 0.25.0 | GitHub release, `~/.local/share/wt-hub/zjstatus-v0.25.0.wasm` | the bar; without it the hub uses zellij's compact bar |
| worktrunk (`wt`) | 0.80.0 | `brew install worktrunk` | worktrees, `wt list` data, task notes, `wt remove`; `wt <name>` runs `wt-<name>` from PATH |
| fzf | 0.74.1 (0.74+) | `brew install fzf` | the list (`--footer`, `transform-footer`, `--listen`, `--id-nth`) |
| jq | 1.7.1 | `/usr/bin/jq` (macOS); brew's works too | all JSON |
| tuicr | 0.27.0 | `brew install tuicr` | review |
| yazi | 26.9.1 (26.x) | `mise use -g yazi`; the panes find it in `~/.local/share/mise/shims` | files |
| terminal-notifier | 3.1.0 | `brew install terminal-notifier`; path `/opt/homebrew/bin/terminal-notifier` | notices |
| Nerd Font | | Ghostty's built-in font has the Nerd Font symbols; FiraMono Nerd Font is installed | the Octicons in the git signs |
| Claude Code | 2.1.304 | `~/.local/bin/claude` | `claude --bg`, `claude attach`, `claude agents --json --all`, `claude rm`, `claude --bg --resume`, hooks, the mod |
| git | 2.54.0 (Apple) | Xcode Command Line Tools | worktrees, turn chains |
| bash | 3.2.57 (`/bin/bash`) | macOS | every script (`#!/usr/bin/env bash` finds `/bin/bash`) |
| python3 | 3.9.6 (`/usr/bin/python3`) | Xcode Command Line Tools | `wt-hub-keys` |
| perl | 5.34.1 | macOS | the 5 s timeout around every zellij call |
| curl | 8.7.1 | macOS | the list's fzf socket |

## Install

The repo must stay at `~/Documents/projects/wt-hub`: the install is symlinks into it. Every step
can run again safely.

1. Tools (macOS, Homebrew):

   ```sh
   brew install worktrunk zellij fzf tuicr terminal-notifier
   mise use -g yazi
   ```

   jq comes with macOS (`/usr/bin/jq`). `wt-hub-keys` runs on `/usr/bin/python3` (Xcode Command
   Line Tools); the zellij timeout wrapper uses `perl`.
2. Links. A new script in `bin/` needs this step too (the loop links every file in `bin/`,
   `wt-pick` included):

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
4. Pane keys: in `~/.config/zellij/config.kdl` (not in this repo). The hub expects
   `default_mode "locked"`, `bind "Ctrl g" { SwitchToMode "normal"; }` in `locked`, and
   `Ctrl q` (`Quit`) and `Ctrl g` (back to locked) in the other modes. Add these binds to the
   `normal` block of `keybinds`:

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
5. The bar is [zjstatus](https://github.com/dj95/zjstatus) v0.25.0. Without it `wt hub` uses
   zellij's compact bar:

   ```sh
   mkdir -p ~/.local/share/wt-hub && curl -fL -o ~/.local/share/wt-hub/zjstatus-v0.25.0.wasm \
     https://github.com/dj95/zjstatus/releases/download/v0.25.0/zjstatus.wasm
   shasum -a 256 ~/.local/share/wt-hub/zjstatus-v0.25.0.wasm  # 282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe
   ```

   On its first start zellij asks for its permissions in the bar: click the bar and press `y`.
6. Check: `ls -l ~/.local/bin | grep projects/wt-hub/bin` shows each `bin/` script as a link
   into this repo; `wt hub` opens the hub. The first click on a notice (or the first `wt hub`
   from a script) can make macOS ask for permission to control Ghostty: allow it.

## How to work in the hub

### Start the hub

`wt hub` goes to the hub's Ghostty tab when the hub runs in one. Else it opens the hub in this
terminal: it attaches to a hub that answers, or it starts a fresh hub. It opens a new Ghostty tab
only when it has no terminal (an agent, a script, `/wt hub`) or runs inside another zellij
session. `--here` and `--tab` choose. See [Commands](#commands).

### Start agents in the background

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

- `n` on a worktree or agent row: a new idle background agent in that worktree.
- `N` on a repo, worktree or agent row: the list asks for a branch, makes a new worktree of that
  repo (`wt new <branch> --agent`) and starts an idle agent in it.

The new agent shows in the middle column, with the focus there. Type its first prompt. Agents
started by the list are named `<repo>/<branch>`.

From a shell: `wt new <branch> -- <prompt>` makes the worktree and starts the agent with a prompt.

### Pick agents and worktrees

Click a row or press Enter on it.

| Row | What the hub shows | Focus after the pick |
|---|---|---|
| background agent | the agent in the middle column; review on its turns, in its worktree | middle column |
| interactive agent | a note in the middle column (`o` goes to its tab); review on its turns | middle column |
| worktree | review (and files, when open) on that worktree | Enter: review. Click: stays in the list |
| repo | the same as its main checkout | the same as a worktree |

▸ beside an agent marks the agent in the middle column. A pick made elsewhere (a notice click,
`wt go`, a new agent) moves the list's cursor to that agent.

A click on a pane that does not have the focus only gives it the focus (zellij). Click again to
pick.

### The middle column

You type to the agent here, as in any `claude attach`.

- Leave the agent: Ctrl+Z, or ←. In `claude attach`, ← opens Claude's agent view; in the hub the
  list is that view, so the pane stops it. The agent keeps running.
- After you leave, the pane says "You left this agent". Enter opens it again. A pick of an agent
  opens that agent.
- When `claude attach` fails at once (for example, the agent's worktree is gone), its error stays
  on screen. Enter tries again.
- The pane never closes.

### Review by turn

The hooks of `claude-turn-snapshot` (UserPromptSubmit, Stop) save the worktree at each turn as a
hidden commit chain per agent: `refs/wt-turns/<id>/base` and `refs/wt-turns/<id>/head`. They never
touch the branch, the index or the files.

- The base is `HEAD` at the agent's first snapshot.
- Each Stop adds a commit `turn · <prompt>`, with the agent's result line as its body.
- Each UserPromptSubmit adds a commit `between turns · edits made outside the agent` when you
  changed files between two turns.
- A turn with no change adds no commit.
- `<id>` is the background agent's short id, else the first 8 characters of the session id. A
  background agent keeps its chain after a resume or `/clear`.

Review has two modes. The pane title starts with the mode, and `t` in tuicr toggles it. The mode
stays for the next picks (`~/.local/state/wt-hub-review.mode`).

- **turns**: the picked agent's chain. A worktree pick opens the newest chain of that worktree.
  With no chain, tuicr's own picker opens. A chain opens on its newest turn (the pane types `(`
  into tuicr). Press `(` to see all turns.
- **commits**: the branch's own commits, from its merge-base with `origin/HEAD` (else `main`,
  else `master`) up to `HEAD`. A branch with no commits of its own opens tuicr's picker.

New turns come in by themselves. The pane looks at the chain head every 2 s (commits mode: at
`HEAD`). When it moves, tuicr starts again on the newest turn. It does not do this while you type
a comment or a `:` or `/` prompt; it waits until tuicr is back in NORMAL or SELECT mode.

`q` in tuicr means "back": tuicr starts again at its start (the picker, or the newest turn).
When tuicr quits less than 2 s after its start, the pane says so and waits for Enter.

The list's keys act in the list only. The list has no key for review's mode or for files.

### Files

`e` in tuicr (NORMAL or SELECT mode) opens files: yazi in the review's worktree, over review.
tuicr keeps running under it. `e` or `q` in yazi closes files, and review comes back. A new pick
moves files to the new worktree.

In files:

- `o` opens the hovered file in this pane (yazi's own open).
- `O` opens the hovered file or folder in your editor, in its project, in a new tab (`wt-edit`).
- `W` is yazi's "open with" menu (yazi's own `O`).

### Open your editor

`wt-edit <file or folder>` (and `O` in files) opens the project of that path: its git root, or
outside git its folder (the file's folder). A file opens in a buffer.

- The editor is `$WT_EDITOR`, else `$VISUAL`, else `$EDITOR`, else `nvim`.
- A terminal editor runs in a new Ghostty tab in the project: `<editor> .` or
  `<editor> <file>`. When the editor quits, the tab's shell stays in the project.
- A GUI editor (`code`, `code-insiders`, `cursor`, `windsurf`, `zed`, `subl`, `idea`,
  `webstorm`, `pycharm`, `goland`, `rubymine`, `fleet`) gets `<editor> <project> [file]` and
  opens its own window.
- `WT_EDITOR_GUI=1` or `0` overrides that guess.

### Notices

The `claude-notify` hook posts a macOS notice:

- **✓ Turn finished** (Stop): the first line of the agent's last message, or its line that starts
  with `result:`, `needs input:` or `failed:`. No notice while the agent has background tasks.
- **✋ Needs input** (Notification: a permission prompt, a question, or an agent that needs input),
  with a sound.

The title is `<icon> <headline> · <client> › <repo>`; the subtitle is the branch and the task
note. macOS groups the notices of one agent.

There is no notice when Ghostty is the front app and its selected tab shows the agent: the
agent's own tab (`claude attach`, `c`, its zellij session, or an interactive session's terminal),
or the hub's tab. The hub's tab counts for every agent, whatever pane has the focus.

A click on a notice runs `wt go <session>`: Ghostty comes to the front and shows the agent. A
background agent opens in the hub's middle column when the hub runs; else in its `claude attach`
tab (a new one if needed). An interactive session goes to its own tab. The click's output goes
to `~/.local/state/claude-notify.log`.

### Remove and prune

`d` on a row removes it after a confirm. It never forces.

- **Background agent**: `claude rm <id>`. It deletes the session and the worktree that Claude
  made for it, if any. Unpushed commits stop the removal. The transcript stays.
- **Interactive agent**: not removed. Close it in its tab, or `b` first.
- **Worktree**: `wt remove`. The list never removes a main checkout. Agents in the worktree must
  go first (the list names them). The branch is deleted only when it is merged. Uncommitted
  changes stop the removal. A dim check sign and a dim name mark a worktree that is safe to
  remove.

Dead agents are background agents whose folder is gone (a removed worktree) and that do not run
now. The list removes them by itself every 10 minutes, with plain `claude rm`, and logs each one
in `~/.local/state/wt-hub-prune.log`. `claude rm` keeps an agent when its recorded worktree is
still on disk (no WorktreeRemove hook here) or has unpushed work. After that, the list prunes the
turn chains of gone agents (`claude-turn-snapshot --prune`). `p` prunes the dead agents now,
after a confirm.

Idle background agents stay until you remove them.

### Tidy the list

- `a` hides the idle repos and idle main checkouts (dim rows), and shows them again. A last row
  says how many are hidden.
- `h` / `l` make the list narrower or wider. A mouse drag on the border works too. The hub keeps
  the width (`wt-hub-sidebar.pct`, 10–60 %) for its next fresh start.
- `r` reloads the list: fresh git signs now, and the list starts again as the newest version of
  `wt-sidebar` (new keys apply). Else git signs update every 30 s.

### Quit

Quit the hub: Ctrl g, then Ctrl q. The bar shows this hint when you press Ctrl g. The agents keep
running. Closing the hub's Ghostty tab only detaches it: `wt hub` attaches it again. The list has
no quit key.

## Keyboard shortcuts

### List

| Key | Action |
|---|---|
| Enter | open the row; the focus moves (agent: middle column; worktree: review) |
| click, double-click | open the row; an agent moves the focus, a worktree keeps it in the list |
| `n` | new idle background agent in this row's worktree |
| `N` | new worktree of this row's repo (asks the branch) + idle agent |
| `o` | the row's own Ghostty tab: an interactive agent's tab, else the worktree's zellij session (`wt open`) |
| `d` | remove the agent or worktree (asks first) |
| `b` | an idle interactive session goes on as a background agent (asks first) |
| `a` | hide / show idle repos and main checkouts |
| `p` | prune dead agents now (asks first) |
| `r` | reload the list (fresh git signs; starts the newest `wt-sidebar`) |
| `j` / `k`, ↓ / ↑, wheel | move |
| `h` / `l` | narrower / wider |
| `?` | all keys and signs (press again: fewer keys) |
| `q`, Esc | nothing (the list belongs to the hub) |

### Agent viewer (middle column)

| Key | Action |
|---|---|
| any key | goes to the agent (`claude attach`) |
| Ctrl+Z | leave the agent; it keeps running |
| ← | leave the agent (Claude's agent view is stopped; the list is that view) |
| Enter (after you left) | open the agent again |
| Enter (after a failed attach) | try again |

### Review (tuicr)

`wt-hub-keys` runs tuicr and takes `t` and `e` while tuicr's status line shows NORMAL or SELECT.
In a comment, a `:` or `/` prompt or a paste, they go to tuicr.

| Key | Action |
|---|---|
| `t` | toggle turns ⇄ commits (from `wt-hub-keys`) |
| `e` | show files (yazi) over review (from `wt-hub-keys`) |
| `q` | back: tuicr starts again at its start (`q_quits`, `config/tuicr/config.toml`) |
| `(` | newest turn; press again for all turns (tuicr) |
| `i`, `:` | tuicr's include filter and commands |
| `?` | tuicr's own key help |
| Enter (after "tuicr closed") | open tuicr again |

tuicr's own `e` (exclude filter) is not available in the hub.

### Files (yazi)

From `config/yazi/keymap.toml` (hub only: `YAZI_CONFIG_HOME=~/.config/wt-hub/yazi`). The other
keys are yazi's own (yazi's help: `~` or F1).

| Key | Action |
|---|---|
| `e` | back to review |
| `q` | quit yazi: back to review |
| `o` | open the hovered file in this pane (yazi's open) |
| `O` | open the hovered file or folder in your editor, in its project, in a new tab (`wt-edit`) |
| `W` | open with... (yazi's "open with" menu) |

### Panes (zellij, every session)

The hub runs zellij in locked mode. Ctrl g goes to normal mode; these keys act once and go back
to locked mode.

| Keys | Action |
|---|---|
| Ctrl g, `1` / `2` / `3` | list / middle / right column |
| Ctrl g, `h` / `l` | pane to the left / right |
| Ctrl g, `;` | last pane |
| Ctrl g, Ctrl q | quit the hub (the agents keep running) |
| Ctrl g, Ctrl g / Esc / Enter | back to locked mode |
| Ctrl g, `p` `t` `r` `s` `m` `o` | zellij's pane, tab, resize, scroll, move and session modes |

### Pane titles

The titles show the keys of the panes that tuicr and yazi fill:

- review: `turns · <repo>   e files · t commits` (or `commits · <repo>   e files · t turns`)
- files: `files · <repo>   e review · o open here · O editor tab · W open with`
- middle: the agent's name

## The list: rows and signs

The list shows each repo with a `.git` folder 1–2 levels under `$WT_ROOTS` (default
`~/Documents/projects`; more roots with `:`).

- `<root>/<client>/<repo>` goes under an orange heading for its client.
- `<root>/<repo>` goes under "Other" at the bottom.
- Under each repo (bold): its worktrees, the main checkout first; under each worktree, its agents.
  A repo row acts as its main checkout (`N`, `o`, click).
- A removed worktree that still has agents shows as a dim `<branch> (gone)` row of its repo.
- Agents in no repo show under "no repo" at the bottom, with their folder.
- A main checkout without an agent is idle, and so is a repo with only an idle main checkout:
  both are dim. `a` hides them.
- A worktree row: branch (last part, cut to the width), the git signs (always shown), then the
  task note in the room left.

The first row and the bar show the agent counts. The `?` footer has the Signs legend, with the
real glyphs. The Octicons are Nerd Font private-use glyphs, so this file names them by code
point.

| Sign | Meaning |
|---|---|
| `▸` (bold cyan, agent name cyan) | the agent in the middle column |
| `!` yellow | agent needs input |
| `✗` red | agent failed |
| `●` green | agent works |
| `○` dim | agent is idle |
| `bg 12m` (dim, after the name) | background agent; age (m, h, d) |
| Octicon diff (U+F440), yellow | uncommitted changes |
| `↑N` cyan | commits to push (the branch is on the remote) |
| `↓N` cyan | commits to pull (the branch is on the remote) |
| `+N` green | commits not in the default branch (the branch is not on the remote) |
| Octicon alert (U+F421), red | a merge into the default branch would conflict |
| Octicon check (U+F42E), dim | safe to remove: the branch is empty or integrated (its name is dim too) |
| Octicon git-merge (U+F419), red | conflicts now, or a rebase or merge in progress |

"On the remote" means the branch has a tracking branch, or `origin/<branch>` exists (as for a PR
pushed without `-u`). The list uses local refs only; it does not fetch.

## Commands

All of these are in `~/.local/bin`. worktrunk runs `wt-<name>` for `wt <name>`, so `wt hub` and
`wt-hub` are the same. `-h` shows each script's header.

| Command | What it does |
|---|---|
| `wt hub [--here \| --tab \| --print-layout]` | Go to the hub's Ghostty tab, else open the hub in this terminal (attach, or a fresh start). A new tab without a terminal or inside another zellij session. `--here`: this terminal. `--tab`: a new tab. `--print-layout`: print the zellij layout. |
| `c [claude --bg options] [prompt]` | Claude in this folder as a background agent, attached here. Use it in place of `claude`. |
| `wt go <agent>` | Bring an agent in front: id, session id (or its start), name, or a part of a name (any case). Several name matches: the live ones win; still several is an error that lists them. A background agent opens in the hub when the hub runs (from anywhere, also from an agent), else in a `claude attach` tab. An interactive one: its own tab (or zellij pane). |
| `wt new <branch\|pr:N> [-b base] [-t "task"] [-a] [-- prompt...]` | Make (or reuse) the worktree and store the task note. With a prompt, or `-a` for an idle one, start a background agent there. Without `-t`, the first line of the prompt (60 characters) is the task note. |
| `wt-edit <file or folder>` | Open it in your editor, in its project. See [Open your editor](#open-your-editor). |
| `wt open [branch\|path]` | Select the Ghostty tab of the worktree's zellij session (named `<repo>.<branch>`), or open a tab that attaches to it (made with your default layout when new). |
| `wt all [-a]` | Worktrees of every repo, grouped by client, with agent counts and task notes. `-a`: also repos with only a main checkout and no agent. |
| `wt all --json` | One JSON object per worktree (the list's data; implies `-a`). |
| `wt pick [-a]` | The same list in fzf, with git status and log in a preview. Enter: `wt open` on the row. Ctrl-A: `wt agents` for that worktree. |
| `wt agents [path]` | Claude sessions (all, or one worktree) in fzf, the ones that need input first. Enter: `wt go`. |
| `wt setup [path]` | The worktrunk `pre-start` hook: in a new worktree, copy the ignored files (`.worktreeinclude` through `wt step copy-ignored`, else the ignored `.env*` files of the main checkout) and install the dependencies (pnpm, bun, yarn, npm or uv, from the lock file). It puts back a lock file that the install changed. Safe to run again. |
| `wt task [text]` | worktrunk alias: set the worktree's task note, or show it. |
| `claude-turn-snapshot --list [path]` | The turn chains of a worktree: id, age, last subject. |
| `claude-turn-snapshot --prune [--dry-run]` | Remove the chains of agents that `claude agents --all` no longer lists, when their worktree is gone or their last turn is older than 7 days. It does nothing without an agent list or the worktree cache. |

Hooks and internal commands (not for hand use): `claude-notify` (Stop, Notification),
`claude-turn-snapshot` (UserPromptSubmit, Stop), `wt-sidebar` (the list), `wt-hub-pane
agent|review|files` (the panes), `wt-hub-keys` (tuicr's `t` and `e`).

### The mod (`/wt` in Claude Code)

`mod/` is a Claude Code mod for any interactive session. The hub itself does not need it.

| Command | What it does |
|---|---|
| `/wt` | turn the hub features on: status line with agent counts, toasts when an agent needs input or finishes |
| `/wt pane` | the worktree list in the dock |
| `/wt hub` | `wt hub` (its tab, or a new tab) |
| `/wt off` | turn them off |
| `/wt new <branch> [-t "task"] [-- prompt]` | `wt new` |
| `/wt go <agent>` | `wt go` |
| `/wt open <branch\|path>` | `wt open` |
| `/wt msg <agent> <text>` | send a message to an agent |
| `/wt refresh` | reload worktrees and agents now |

Check the mod after an edit: `cd mod && claude plugin test . && claude plugin validate .`. Edits
apply at the next session start or after `/reload-plugins`.

## State and logs

In `~/.local/state/`:

| File | What |
|---|---|
| `wt-hub-layout.kdl` | the layout that `wt hub` writes at a fresh start |
| `wt-hub-agent.target`, `wt-hub-review.target`, `wt-hub-files.target` | what each hub pane shows; a pick writes it |
| `wt-hub-agent.pane`, `wt-hub-review.pane`, `wt-hub-files.pane` | the zellij pane id and pid of each pane's `wt-hub-pane` |
| `wt-hub.lock/` | held while a pick moves the hub's panes (taken over after 5 s) |
| `wt-hub-review.mode` | `turns` or `commits` |
| `wt-hub-sidebar.pct` | the list's share of the width |
| `wt-hub-sidebar.hide-idle` | there while `a` hides idle rows |
| `wt-worktrees.ndjson` | cache of `wt all --json` (refreshed after 30 s) |
| `wt-sidebar.<pid>.sock`, `.count`, `.sum`, `.help`, `.restart` | a running list: its fzf socket, row count, agent counts, `?` state, `r` flag |
| `wt-turns/<id>.worktree`, `<id>.prompt` | the worktree of each turn chain; the prompt of the current turn |
| `wt-hub-prune.stamp` | time of the last automatic prune |
| `wt-hub-prune.log` | each agent the list pruned, and each turn chain removed |
| `claude-notify.log` | one line per notify hook call, and the output of notice clicks |

Elsewhere:

- `refs/wt-turns/<id>/{base,head}` in each repo: the turn chains.
- The task note: worktrunk's state variable `task` (`wt task`, `wt new -t`).
- `~/.local/share/wt-hub/zjstatus-v0.25.0.wasm`: the bar.

Environment variables: `WT_ROOTS` (project roots, `:`-separated; default `~/Documents/projects`),
`WT_HUB_SESSION` (default `hub`), `WT_ZELLIJ_TIMEOUT` (default 5 s), `WT_EDITOR`,
`WT_EDITOR_GUI`.

## Troubleshooting

- **The hub does not answer** (keys do nothing, a pick hangs): run `wt hub` in a terminal. It
  reuses a hub only when `zellij action list-clients` answers. Else it kills the hub's server,
  deletes the session and starts a fresh hub from the layout. The agents keep running; pick them
  again. Every zellij call in the scripts stops after 5 s (`WT_ZELLIJ_TIMEOUT`), so a stuck
  server cannot stop the list or a hook for long.
- **The list does not update**: press `r` in the list. It starts again as the newest
  `wt-sidebar` with fresh git signs.
- **No notices**: run `/opt/homebrew/bin/terminal-notifier -diagnose`. Look at
  `~/.local/state/claude-notify.log`: a line for each hook call means the hook runs. Remember the
  rule: no notice while Ghostty is in front with the agent's tab or the hub's tab selected.
- **A notice click does nothing**: look at the end of `claude-notify.log` for the output of
  `wt go`.
- **Review shows tuicr's picker**: the agent has no turn chain yet (no finished turn with a
  change), or the branch has no commits of its own (commits mode).
- **The middle column shows an old agent or an error**: pick the agent again, or press Enter in
  the middle column.

## Repo layout

```
bin/
  c                      Claude as a background agent, attached here
  claude-notify          hook (Stop, Notification): macOS notice; a click runs wt go
  claude-turn-snapshot   hook (UserPromptSubmit, Stop): turn chains; --list, --prune
  wt-agents              wt agents: Claude sessions in fzf
  wt-all                 wt all: worktrees of every repo; --json for the list
  wt-pick -> wt-all      wt pick: the same in fzf, Enter opens
  wt-edit                open a file or folder in your editor, in its project
  wt-go                  wt go: bring an agent in front (hub, tab or pane)
  wt-hub                 wt hub: start, attach or go to the hub; writes its layout
  wt-hub-keys            pty wrapper around tuicr: t (toggle mode), e (files)
  wt-hub-pane            a hub pane (agent | review | files) that follows its target
  wt-new                 wt new: worktree, task note, background agent
  wt-open                wt open: the worktree's zellij session in a Ghostty tab
  wt-setup               worktrunk pre-start hook: ignored files, dependencies
  wt-sidebar             the list (fzf): rows, keys, remove, prune, new agents
lib/
  wt-lib.sh              shared helpers: zellij timeout, Ghostty tabs, hub panes and targets
config/
  claude-settings-hooks.json   hooks to merge into ~/.claude/settings.json
  tuicr/config.toml            q_quits: q in review goes back
  worktrunk/config.toml        worktree path <repo>.<branch>, pre-start wt-setup, Task column, aliases
  yazi/keymap.toml             hub-only yazi keys: e, O, W
  zellij/wt-hub.kdl            a saved hub layout (wt hub writes its own copy)
mod/
  .claude-plugin/              plugin.json, marketplace.json (marketplace alex-wt-hub)
  hooks/hooks.json             loads register.tsx
  hooks/register.tsx           /wt command, status line, toasts, dock pane
  hooks/model.ts               parsing and grouping of worktrees and agents
  types/index.d.ts             row and event types
  tests/wt-hub.test.tsx        mod tests
  tsconfig.json
CLAUDE.md                rules for edits in this repo
TODO.md                  Alex's hub to-do list and decisions
```

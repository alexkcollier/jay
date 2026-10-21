# wt-hub

A worktree and agent hub for macOS. One zellij session, "hub", shows three columns: a live list
of the worktrees and Claude agents across your projects, the picked agent, and a review of that
agent's work (tuicr on its turns, or yazi on its files). Built on
[worktrunk](https://github.com/max-sixty/worktrunk) and Claude Code background agents.

Install with `./install.sh` ([Install](#install)). Open items and known faults:
[docs/open-items.md](docs/open-items.md). Rules for edits: [CLAUDE.md](CLAUDE.md).

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
┌ worktrees ─────────────┬ shop/fix-login ────────────┬ turns · shop   e files · t commits ────┐
│ ● 1 working  ○ 2 idle  │                            │                                        │
│ ◆ hub ○                │  the picked agent:         │  review of the agent's turns (tuicr)   │
│ acme                   │  claude attach <id>        │                                        │
│  shop                  │                            │            e ⇅ e / q                   │
│   main                 │  type to the agent here    │                                        │
│   fix-login  ↑2        │                            │  files of the worktree (yazi),         │
│     ▸ ● shop/fix-login │  Ctrl+Z or ←: leave it     │  over review                           │
│                        │  (it keeps running)        │                                        │
│ ⏎ open  n new  d remove│                            │                                        │
│ ? all keys and signs   │                            │                                        │
├────────────────────────┴────────────────────────────┴────────────────────────────────────────┤
│ ◆ hub  ● 1 working  ○ 2 idle                                                     hub │ 14:05 │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
  list (wt-sidebar, fzf)    agent viewer (wt-hub-pane agent)   review ⇄ files (wt-hub-pane review/files)
```

- **List** (left, about 22 % of the width). Every repo, worktree and agent, grouped by client.
  Agent rows update every few seconds, git signs every 30 s. A pick here drives the other two
  columns.
- **Agent viewer** (middle). `claude attach` on the picked background agent. You talk to the agent
  here. The pane title is the agent's name. A fresh hub opens on the hub Claude (see
  [The hub Claude](#the-hub-claude)); the "◆ hub" row in the list brings it back.
- **Review** (right). tuicr on the picked agent's turns (one commit per turn), or on the branch's
  commits. **Files** (yazi in the same worktree) opens over review and closes back to it.
  Ctrl g `v` hides review (the agent viewer gets its width) and shows it again.
- **Banner** (top, zjstatus, blue). `◆ HUB › worktrees` and the picked worktree (on a tasks tab:
  `◆ HUB › tasks` and its worktree), and where `Ctrl g Tab` goes.
- **Bar** (bottom, zjstatus). `◆ hub`, the agent counts from the list, the tasks of all worktrees
  (`● web:5174`), the zellij mode when it is not locked and the time.
- **Tasks tabs** (one per worktree, Ctrl g Tab). Shell panes for dev servers, watchers and
  `docker compose up`, which you and the agents both see. See [Tasks](#tasks-dev-servers).

The hub supports:

- Background agents first: `c` starts Claude as a background agent and attaches the terminal, so
  the hub can show the same agent. Plain `claude` (interactive) shows in the list too, but only
  in its own terminal; `b` moves it to the background.
- New agents from the list, in a worktree (`n`) or in a new worktree (`N`). An agent on a main
  checkout is an orchestrator: it gives each change to a worker in a new worktree.
- Review by turn: hooks save the worktree after each agent turn as hidden commits. Review opens
  on the newest turn, and new turns come in by themselves.
- Git state of each worktree at a glance: changes, commits to push or pull, merge conflicts,
  safe to remove.
- Removal of agents and worktrees after a confirm (a worktree goes with its idle agents), and
  automatic prune of dead agents.
- macOS notices when an agent finishes a turn or needs input, with a click that shows the agent.
- Your editor on any file of the worktree (`O` in files).
- Dev servers in a tasks tab per worktree: their state and ports in the bar, their output
  readable by agents (`hub-run`), no port or repo config.

## Requirements

The versions are the ones the hub was tested with (2026-10-20); `./install.sh --check` checks
the minimum versions. The hub is macOS only: it drives Ghostty tabs through AppleScript and
reads the front app with `lsappinfo`.

The hub itself runs in any terminal: run `wt hub` in it. Tab control is Ghostty only (other
terminals can come later). Tab control is on when Ghostty runs and the caller's terminal, if it
has one, is Ghostty (`TERM_PROGRAM`). `WT_TERMINAL=ghostty` turns it on, any other value turns
it off. Without tab control:

- `wt hub` does not look for the hub's tab, and it does not open a new tab: it prints a hint.
- `wt go` still shows a background agent in the hub when the hub runs. Else it prints the
  `claude attach` command. `o` in the list does nothing.
- `wt open` and `wt-edit` with a terminal editor (`O` in files) print the command to run.
- Notices always show (no "agent's tab in front" rule). A click still shows a background agent
  in the hub, but it does not bring the terminal to the front.

| Tool | Tested with | From | Used for |
|---|---|---|---|
| macOS | 27.0.1 | | `osascript`, `lsappinfo`, `stat -f`, `cp -c` |
| Ghostty | 1.3.2 (1.3+) | `brew install --cask ghostty` (optional) | tabs through AppleScript: `wt hub`, `wt go`, `wt open`, `wt-edit`, notices |
| zellij | 0.45.1 | `brew install zellij` | the hub session; the scripts use 0.45 behavior (see CLAUDE.md) |
| zjstatus | 0.25.0 | GitHub release, `~/.local/share/wt-hub/zjstatus-v0.25.0.wasm` | the bar; without it the hub uses zellij's compact bar |
| worktrunk (`wt`) | 0.80.0 | `brew install worktrunk` | worktrees, `wt list` data, task notes, `wt remove`; `wt <name>` runs `wt-<name>` from PATH |
| fzf | 0.74.1 (0.74+) | `brew install fzf` | the list (`--footer`, `transform-footer`, `--listen`, `--id-nth`) |
| jq | 1.7.1 | `brew install jq` | all JSON |
| tuicr | 0.27.0 | `brew install tuicr` | review |
| lazygit | 0.66.2 (0.66+) | `brew install lazygit` (optional) | review with `WT_REVIEW=lazygit` |
| yazi | 26.9.1 (26.x) | `brew install yazi` | files |
| terminal-notifier | 3.1.0 | `brew install terminal-notifier` (optional) | notices |
| Nerd Font | | Ghostty's built-in font has the Nerd Font symbols; in another terminal, set a Nerd Font | the Octicons in the git signs |
| Claude Code | 2.1.304 | `brew install --cask claude-code` | `claude --bg`, `claude attach`, `claude agents --json --all`, `claude rm`, `claude --bg --resume`, hooks, the mod |
| git | 2.54.0 (Apple) | Xcode Command Line Tools | worktrees, turn chains |
| bash | 3.2.57 (`/bin/bash`) | macOS | every script (`#!/usr/bin/env bash` finds `/bin/bash`) |
| python3 | 3.9.6 (`/usr/bin/python3`) | Xcode Command Line Tools | `wt-hub-keys`, `claude-clear` |
| perl | 5.34.1 | macOS | the 5 s timeout around every zellij call |
| lsof | macOS | macOS | the ports of the tasks (`hub-run`) |
| Docker | 29.8.2, Compose 5.5.1 | Docker Desktop (optional) | the ports of `docker compose` tasks, `hub-run port` |
| curl | 8.7.1 | macOS | the list's fzf socket |

## Install

1. Install the tools with Homebrew:

   ```sh
   brew install worktrunk zellij fzf jq tuicr yazi
   brew install --cask claude-code
   # optional:
   brew install terminal-notifier     # macOS notices when an agent finishes or needs input
   brew install --cask ghostty        # tab control (wt hub, wt go, wt open, O in files)
   ```

   Without terminal-notifier there are no notices; the rest works. Without Ghostty the hub runs
   in any terminal, but without tab control (see [Requirements](#requirements)).
2. Get the repo and run the installer. The repo can be anywhere:

   ```sh
   git clone <this repo> wt-hub && cd wt-hub
   ./install.sh --check    # what is there and what is missing; changes nothing
   ./install.sh            # install
   ```

   `~/.local/bin` must be on PATH. The installer:

   | What | Where |
   |---|---|
   | the scripts in `bin/` and `lib/wt-lib.sh` | `~/.local/bin`, `~/.local/lib` (copies; `--link`: symlinks) |
   | your settings, all at their defaults (see [Settings](#settings)) | `~/.config/wt-hub/config`, made when missing |
   | the hub's yazi keys | `~/.config/wt-hub/yazi` |
   | the hub's lazygit settings (for `WT_REVIEW=lazygit`) | `~/.config/wt-hub/lazygit` |
   | tuicr's `q_quits = true` | `~/.config/tuicr/config.toml`, made when missing; else checked |
   | the hub's worktrunk settings | `~/.config/worktrunk/config.toml`, copied when missing; else the missing keys are listed |
   | the hooks (SessionStart, Stop, UserPromptSubmit, PostToolUse, Notification) | added to `~/.claude/settings.json`, only the missing ones, after a backup |
   | zjstatus v0.25.0 (the bar) | `~/.local/share/wt-hub/`, sha256 checked |
   | the mod (`/wt`), with `--with-mod` | `~/.local/share/wt-hub/mod`, marketplace `wt-hub` |
   | `wt-setup` as worktrunk's `pre-start` hook, with `--with-setup` | `~/.config/worktrunk/config.toml` (see `wt setup` in [Commands](#commands)) |

   It never replaces a file that it did not install: it lists it as a TODO (`--force`
   replaces it). It never edits `~/.config/zellij/config.kdl`: it prints the pane keys below.
   It ends with "Ready", or with the TODO items. Run it again after a `git pull`: the copies do
   not change when the repo changes.
3. Optional pane keys, in `~/.config/zellij/config.kdl`. The hub expects
   `default_mode "locked"`, with `Ctrl g` to normal mode and `Ctrl q` to quit. Add these binds
   to the `normal` block of `keybinds`:

   ```kdl
   normal {
       bind "h" { MoveFocus "left"; SwitchToMode "locked"; }
       bind "l" { MoveFocus "right"; SwitchToMode "locked"; }
       bind "1" { MoveFocus "left"; MoveFocus "left"; SwitchToMode "locked"; }
       bind "2" { MoveFocus "left"; MoveFocus "left"; MoveFocus "right"; SwitchToMode "locked"; }
       bind "3" { MoveFocus "right"; MoveFocus "right"; Run "/Users/<you>/.local/bin/wt-sidebar" "--review" "show" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
       bind ";" { FocusLastPane; SwitchToMode "locked"; }
       bind "v" { Run "/Users/<you>/.local/bin/wt-sidebar" "--review" "toggle" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
       bind "Tab" { Run "/Users/<you>/.local/bin/hub-run" "--switch" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
       bind "r" { Run "/Users/<you>/.local/bin/hub-run" "--launcher" { floating true; close_on_exit true; x "20%"; y "35%"; width "60%"; height "3"; }; SwitchToMode "locked"; }
   }
   ```
4. Start the hub: `wt hub`. At the first start, zellij asks for the bar's permissions: click
   the bar and press `y`. The first click on a notice (or the first `wt hub` from a script)
   can make macOS ask for permission to control Ghostty: allow it.
5. Optional: worktrunk's own Claude Code plugin:
   `claude plugin marketplace add max-sixty/worktrunk && claude plugin install worktrunk@worktrunk`.

### Settings

`~/.config/wt-hub/config` holds `KEY=value` lines; `#` starts a comment. An environment
variable of the same name wins over the file. The file also reaches what a shell profile does
not: the hooks in background agents and a notice click.

| Key | Default | What |
|---|---|---|
| `WT_ROOTS` | `~/Documents/projects` | the folders with your repos, `:` between them; the list shows each repo 1–2 levels under them |
| `WT_EDITOR` | `$VISUAL`, else `$EDITOR`, else `nvim` | the editor for `O` in files and `wt-edit` |
| `WT_EDITOR_GUI` | a guess from the editor's name | `1`: a GUI editor, `0`: a terminal editor |
| `WT_TERMINAL` | on when Ghostty runs | `ghostty`: tab control on; another value: off |
| `WT_TASK_SHELL` | `$SHELL -i +m -c` (zsh, bash), else `$SHELL -l -c` | how a task runs its command line, which comes after these words |
| `WT_LAUNCHER` | the built-in zsh launcher | a command for the launcher (Ctrl g `r`) in another shell; see [Tasks](#tasks-dev-servers) |
| `WT_REVIEW` | `tuicr` | the review pane: `tuicr` (review comments) or `lazygit` (git actions); see [Review with lazygit](#review-with-lazygit) |

`./install.sh --check` tells you when a `WT_ROOTS` folder does not exist.

Your own worktrunk settings, for example aliases for one client's repo, go in
`~/.config/worktrunk/config.toml`, not in this repo.

**Work on wt-hub itself**: `./install.sh --link` links the scripts and keys into the checkout,
so an edit is live at once. Run it again after you add a script to `bin/`.

**Uninstall**: `./install.sh --uninstall` removes what it installed and lists the hooks and the
mod to remove by hand. It keeps `~/.config/worktrunk/config.toml` and `~/.local/state`.

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

- `n` on a worktree or agent row: a new idle background agent in that worktree. On a main
  checkout, the agent is the repo's orchestrator (see [Orchestrators](#orchestrators)). When
  the repo has one already, the hub shows that one.
- `N` on a repo, worktree or agent row: the list asks for a branch, makes a new worktree of that
  repo (`wt new <branch> --agent`) and starts an idle agent in it.

The new agent shows in the middle column, with the focus there. Type its first prompt. Agents
started by the list are named `<repo>/<branch>`.

From a shell: `wt new <branch> -- <prompt>` makes the worktree and starts the agent with a prompt.

`claude --bg` has no trust prompt: in a repo where Claude never ran, it fails with "Workspace not
trusted". Claude keeps the trust per repo, under its main checkout, for all its worktrees; a
trusted parent folder does not count. So `n`, `N` and `c` ask first, in one key (`y`), and write
the trust into `~/.claude.json` as the trust prompt of `claude` would. `wt new` does not ask.

### Pick agents and worktrees

Click a row or press Enter on it.

| Row | What the hub shows | Focus after the pick |
|---|---|---|
| background agent | the agent in the middle column; review on its turns, in its worktree | middle column |
| interactive agent | a note in the middle column (`o` goes to its tab); review on its turns | middle column |
| worktree | review (and files, when open) on that worktree | Enter: review (also a hidden one). Click: stays in the list |
| repo | the same as its main checkout | the same as a worktree |
| ◆ hub | the hub Claude in the middle column; review does not change | middle column |

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

### The hub Claude

A background agent named `hub`, for work across agents and repos: ask it to start agents (`wt
new`), to send a prompt to an agent, to tell you what the agents did, or to answer a question
that needs several repos. It starts in the first `WT_ROOTS` folder (the other roots are added
folders), with a short system prompt about the hub's commands (`wtl_hub_claude_prompt` in
`lib/wt-lib.sh`). It works in no worktree, so a pick of it does not change review.

- A fresh hub opens on it, with the focus in the middle column. The "◆ hub" row at the top of
  the list, or `wt go hub` from anywhere, shows it again.
- It is started the first time the hub needs it. Its id is in `~/.local/state/wt-hub-claude`.
  It is like any background agent: it keeps running when you leave it, and a stopped one opens
  again on a pick.
- It knows the orchestrators (`wt agents --orchestrators`). It sends work for a repo to the
  orchestrator of that repo (SendMessage). For a repo without one, it starts workers itself
  (`wt new`), or it tells you to press `n` on the repo's main checkout row.
- `c` on the "◆ hub" row gives it a fresh context (see [Fresh context](#fresh-context)). To
  start a new hub Claude, `claude rm <id>`: the next pick starts a new one.

### Orchestrators

An orchestrator is a background agent in a repo's main checkout that has the orchestrator
prompt (`wtl_orchestrator_prompt` in `lib/wt-lib.sh`). It is the orchestrator of that repo, as
the hub Claude is for all repos. It plans, reads, reviews and answers questions, and it gives
each change to a worker: a background agent in a new worktree (`wt new <branch> -t <task> --
<prompt>`). So no work piles up on main, and agents do not move between worktrees. The list
marks an orchestrator with a cyan `◇` before its name.

- `n` on a main checkout row starts one, with the prompt. The prompt only steers the agent:
  Claude's own rule still stops a background agent from editing in the main checkout, and the
  agent can go into a worktree (`EnterWorktree`) when you tell it to make a change itself.
- A repo has one orchestrator. When it has one, `n` on its main checkout does not start a
  second one: the list says so, and the hub shows the orchestrator.
- The list reads the prompt in the job's `state.json`: `respawnFlags` keeps the options that a
  background agent started with. The orchestrator of a repo is the oldest live agent with the
  prompt in its main checkout. A stopped agent does not count.
- A second agent with the prompt in the same main checkout gets a yellow `◇`. Only a start
  outside the list makes one, for example a copy from `claude --bg --resume` with new options.
  The hub Claude does not send work to it. Remove it with `d`.
- An agent in the main checkout without the prompt (`c`, `claude --bg`, an interactive
  `claude`) is a plain agent: it gets no `◇`, the hub Claude does not send work to it, and `n`
  still starts an orchestrator.
- Why this rule: the `◇` follows the prompt, so an agent with a `◇` always acts as an
  orchestrator. The oldest one keeps the `◇`, so the sign does not move to a new agent. The
  list, `n` and the hub Claude (`wt agents --orchestrators`) use the same rule, so they find the
  same agent.
- An agent from another folder that went into a worktree with `EnterWorktree` (Claude keeps that
  in the job's `state.json`) does not belong to the worktree: `d` on the worktree stops until it
  leaves (`ExitWorktree`), and the prune does not remove it. `d` on the agent itself removes
  the worktree and then the agent, with the same checks as `d` on the worktree: `claude rm`
  keeps such an agent while its worktree is on disk. One from a main checkout stays under the
  main checkout (with its `◇` when it is the orchestrator), and `→ <branch>` after its age
  names the worktree it is in. Its pick shows that worktree in review.
- `c` on its row gives an orchestrator a fresh context (see [Fresh context](#fresh-context)).

### Fresh context

`c` on an orchestrator row (cyan or yellow `◇`) or on the "◆ hub" row clears the agent's
context. After a confirm, the list types `/clear` into the agent through a hidden
`claude attach` (`claude-clear`). The agent then starts a new conversation with the same system
prompt, name and short id, in the same process. Only its session id changes. So its turn chain,
`~/.local/state/wt-hub-claude` and the middle column stay correct. The old conversation stays
in its transcript.

- The agent must be idle or unread (`○` or `✓`). `/clear` typed into a question or a permission
  prompt would answer it. When the agent works, waits for you or failed, the list says so and
  does nothing. An agent that only waits for its workers (state `working`, status `idle`) is
  idle: `c` clears it, and it forgets those workers. Its workers keep running.
- An orchestrator in a worktree that it entered: tell it to leave the worktree first
  (`ExitWorktree`).
- All `claude attach` clients of an agent share one input box. `claude-clear` deletes a draft
  in it first (Ctrl+U). The hidden client takes the size of a client that is attached already
  (the middle column), because the agent's screen takes the size of the last client.
- For another agent, type `/clear` in the agent.

### Review by turn

The hooks of `claude-turn-snapshot` (UserPromptSubmit, Stop, PostToolUse) save the worktree at
each turn as a hidden commit chain per agent: `refs/wt-turns/<id>/base` and
`refs/wt-turns/<id>/head`. They never touch the branch, the index or the files.

- The base is `HEAD` at the agent's first snapshot.
- Each Stop adds a commit `turn · <prompt>`, with the agent's result line as its body.
- Each UserPromptSubmit adds a commit `between turns · edits made outside the agent` when you
  changed files between two turns.
- A turn with no change adds no commit.
- While a turn runs, `refs/wt-turns/<id>/live` holds the turn so far: a commit
  `turn, running · <prompt>` on top of the head. PostToolUse on `Edit`, `MultiEdit`, `Write`,
  `NotebookEdit` and `Bash` replaces it, at most once in 5 s. Stop removes it. The chain keeps
  one commit per turn.
- A turn that ended without Stop (you stopped it) still gets its commit `turn · <prompt>`, at
  the next prompt.
- An agent that goes into another worktree of the repo (`EnterWorktree`, `ExitWorktree`) keeps
  its chain. After the tool (PostToolUse), the turn's changes so far get a commit
  `turn, in <old folder> · <prompt>`, then a commit `worktree · <new folder>` takes the files of
  the new worktree. Thus the next turn shows only its own changes. `wt-turns/<id>.worktree`
  follows the agent.
- `<id>` is the background agent's short id, else the first 8 characters of the session id. A
  background agent keeps its chain after a resume or `/clear`.

Review has two modes. The pane title starts with the mode, and `t` in tuicr toggles it. The mode
stays for the next picks (`~/.local/state/wt-hub-review.mode`).

- **turns**: the picked agent's chain. A worktree pick opens the newest chain of that worktree.
  With no chain, tuicr's own picker opens. A chain opens on its newest turn (the pane types `(`
  into tuicr). While the agent works, that is the running turn. Press `(` to see all turns.
- **commits**: the branch's own commits, from its merge-base with `origin/HEAD` (else `main`,
  else `master`) up to `HEAD`. A branch with no commits of its own opens tuicr's picker.

New turns come in by themselves. The pane looks at the chain head every 2 s (commits mode: at
`HEAD`). When it moves, tuicr starts again on the newest turn. It does not do this while you type
a comment or a `:` or `/` prompt; it waits until tuicr is back in NORMAL or SELECT mode. This
also works over tuicr's picker: when an agent's first turn (or running turn) comes, its chain
opens. A running turn that changes does not start tuicr again, so you keep your place: `q`
shows its newest state, and the end of the turn starts tuicr again.

`q` in tuicr means "back": tuicr starts again at its start (the picker, or the newest turn).
When tuicr quits less than 2 s after its start, the pane says so and waits for Enter.

The list's keys act in the list only. The list has no key for review's mode or for files.

### Review with lazygit

`WT_REVIEW=lazygit` in `~/.config/wt-hub/config` puts lazygit (0.66 or newer) in the review pane
in place of tuicr. Start the hub again after you change it. The modes and `t`, `e`, `q` stay the
same. lazygit has no review comments: use tuicr when you want to write comments for the agent.
See `notes/lazygit-review.md` for the study.

- **turns**: lazygit cannot open the hidden turn refs, so it runs on a view repo,
  `~/.local/state/wt-hub/lazygit/views/<id>`: a repo of its own that reads your repo's objects.
  Its branch `turns` is the chain head, `turns-base` the base. A turn is one row: a yellow `*`
  marks the turns, a green `*` the history under them. A commit, branch or rebase there changes
  only the view, never your repo. While the agent works, the top row is the running turn
  (`turn, running · <prompt>`, the live ref). An agent with no chain yet gets an empty view
  that fills at its first change. For a worktree pick with no chain, lazygit opens on the
  worktree.
- **commits**: lazygit on the worktree itself, with all its git actions (stage, commit, rebase).
  An agent can work in the same worktree at the same time.

New turns come in without a restart: the pane copies the chain's newest commit (the running
turn, else the head) into the view every 2 s, and lazygit refreshes when the branch moves. Your
place stays. When the newest turn was selected, the new turn is selected (the pane types `<`).
When the running turn changes or ends, its row stays where it is and shows the new state.

lazygit reads your own `config.yml` (theme, diff renderer), then the hub's
`~/.config/wt-hub/lazygit/hub.yml` over it: one tab group, list on top, no author or hash, and
the hub's `t` and `e`. Its state (recent repos) goes to `~/.local/state/wt-hub/lazygit/state`,
not into yours. `claude-turn-snapshot --prune` removes a view with its chain.

### Files

`e` in tuicr (NORMAL or SELECT mode) opens files: yazi in the review's worktree, over review.
tuicr keeps running under it. `e` or `q` in yazi closes files, and review comes back. A new pick
moves files to the new worktree.

In files:

- `o` opens the hovered file in this pane (yazi's own open).
- `O` opens the hovered file or folder in your editor, in its project, in a new tab (`wt-edit`).
- `W` is yazi's "open with" menu (yazi's own `O`).

### Hide review

Ctrl g `v` hides review, and the agent viewer gets its width. Ctrl g `v` again shows review on
the right, at the width it had. The focus stays in the column that has it. Ctrl g `3` and Enter
on a worktree row also show a hidden review, and move the focus to it.

- tuicr runs on while review is hidden: your place and draft comments stay. New turns come in
  when review shows again.
- Files closes when review hides, and opens again when review shows.
- A fresh hub (`wt hub` after a quit) starts with review shown.

zellij cannot hide a tiled pane, so a hidden review is a floating pane of no size in the bottom
right corner, and the hub tab's floating panes are hidden. A new floating pane (Ctrl g Tab,
Ctrl g `r`) shows them again; the hub hides them again when that pane closes. Ctrl g `p` `w`
(zellij's floating panes key) shows them too: the list hides them again within 3 s.

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
or the hub's tab. The hub's tab counts for every agent, whatever pane has the focus, but only
while the hub shows its "hub" tab: on a tasks tab the list is not on screen, so notices come.

A click on a notice runs `wt go <session>`: Ghostty comes to the front and shows the agent. A
background agent opens in the hub's middle column when the hub runs; else in its `claude attach`
tab (a new one if needed). An interactive session goes to its own tab. The click's output goes
to `~/.local/state/claude-notify.log`.

### Tasks (dev servers)

Each worktree gets its own tasks tab in the hub for long-running commands: `pnpm dev`, watchers,
`docker compose up`. The tab is named `<repo>/<branch> · <client>` and is made the first time it
is needed. Each pane in a tasks tab is a task. You and the agents see the same panes. A blue
banner at the top of each tab says where you are: `◆ HUB › worktrees <picked worktree>` on the
hub tab, `◆ HUB › tasks <its worktree>` on a tasks tab, with where Ctrl g Tab goes.

- **Ctrl g Tab**: from the hub tab to the tasks tab of the worktree you picked (agent or
  worktree row; a new tab when it has none); from a tasks tab back to the hub. With an agent
  picked whose worktree runs no task, it goes to the tab of the newest task that agent started
  with `hub-run` (a dev server in another worktree). zellij has no key
  action for a tab by name, so the key runs `hub-run --switch` in a floating pane of 1 cell that
  closes at once. A pick does not change the tab you are on.
- **Console**: each tasks tab has one, a shell in its worktree at its prompt (pane title
  `console`). Type a command there, as in any terminal. A command that ends leaves no pane
  behind: its output stays in the console. One that runs on (a dev server) makes the console its
  task pane, named after the command, and the hub opens a new console within 3 s, without moving
  your focus. When a task in a console ends, that pane is a console again; a tab keeps one (its
  newest), and an extra one closes after 10 minutes at its prompt, so a crashed server's last
  lines stay for a while. More panes: Ctrl g `p` `n`; close one: Ctrl g `p` `x`.
- **Launcher** (Ctrl g `r`, from any tab): a one-line floating prompt for the console of the
  picked worktree (from the hub tab) or of the tab you are on; its title says which. It is your
  own zsh, with your `.zshrc`: completion, history and autosuggestions work as in a terminal.
  Enter types the line into that console (with a `cd` when the console is elsewhere), puts it in
  your history, and you stay where you are. A command that ends within 2 s (`ls`, `pnpm
  docker:up`): the launcher grows to show the console's new lines until a key. One that runs on:
  the launcher closes, and the command is now that tab's task. An empty line or Ctrl-C closes the
  launcher. `hub-run restart` works on a command that the launcher typed (Ctrl-C, then the same
  line again). Other shells: see below.
- **From elsewhere**: `hub-run <command>` in any folder (a Ghostty tab, `! hub-run pnpm dev` in a
  Claude prompt) opens a new pane in that worktree's tasks tab, in that folder, and leaves you
  where you are. `-n <name>` names it; `-w` waits until it listens and prints its URL. When the
  hub does not run, it runs the command in your terminal.
- **Agents**: a SessionStart hook (`hub-run --hook`) tells each Claude session to start dev
  servers with `hub-run -n <name> -w -- <command>`, not with a background Bash call. Then the
  task runs where you see it, and it keeps running after the agent stops. Agents read any task,
  also the ones you typed: `hub-run ls --json`, `hub-run log <task>`.

The bar shows each task that runs or ended, with its first port: `● web:5174` (runs), `✗ admin`
(failed), `○ build` (ended with 0). A shell at its prompt is not shown. Two tasks with the same
name get their branch. The list sends the bar text every 3 s.

A pane that `hub-run` started shows `$ <command>` at the top. When the command ends, the pane says
`exited (<code>) · Enter: run again · q: close`. Ctrl-C stops the command, not the pane. The
command runs as you would type it: `$SHELL -i +m -c <line>` for zsh and bash (your rc file, so
aliases and `mise activate` apply; `+m`: no job control, so Ctrl-C reaches all of it), else
`$SHELL -l -c`. `WT_TASK_SHELL` ([Settings](#settings)) changes it.

**Other shells**: the launcher is built in for zsh; another shell gets a plain prompt (line
editing and its own history). For your own shell, set `WT_LAUNCHER` to a command that runs in
the launcher pane (in the worktree) and hands what you type to `hub-run --launch -- "<line>"`
(it types the line into the console and shows a quick command's output). For
example bash (also macOS `/bin/bash` 3.2), in `~/.config/wt-hub/config`:
`WT_LAUNCHER=BASH_SILENCE_DEPRECATION_WARNING=1 /bin/bash --rcfile ~/.config/wt-hub/launcher.bash -i`,
with this `~/.config/wt-hub/launcher.bash`:

```bash
[[ -f ~/.bashrc ]] && source ~/.bashrc
_wt_hub_run() {   # Enter puts its name before the line; the line comes back from the history
  local line
  line=$(HISTTIMEFORMAT= history 1 | sed -E 's/^ *[0-9]+ +_wt_hub_run //')
  hub-run --launch -- "$line" || read -rsn1 -p 'Press a key.'
  exit
}
bind '"\C-m": "\C-a_wt_hub_run \C-j"'
PS1='❯ '   # one line: the pane title says where the command runs
```

**Ports**: there is no port config. Vite and Next take the next free port by themselves; the hub
finds the ports that each task's processes listen on (`lsof`), and for `docker compose` the ports
that its containers publish. `hub-run ls` and the bar show them, so an agent can give a frontend
its backend's URL (`VITE_API_URL=http://localhost:<port> pnpm dev`). For "address in use",
`hub-run port <n>` tells who holds the port: a task (with its pane), a Docker container (with its
compose project), or another process (with its folder).

**Docker**: a `docker compose up` task stops its containers on Ctrl-C and on `hub-run stop` (the
containers stay, stopped). Two worktrees get different compose projects (compose names them
after the folder), but their published ports collide unless the compose file takes them from
variables (`${DB_PORT:-5432}:5432`).

**Output and secrets**: there are no log files. A pane's output stays in zellij's scrollback
(`scroll_buffer_size`, default 10000 lines), as in any zellij pane; `hub-run log` reads it with
`zellij action dump-screen` at that moment. Every pane in a tasks tab is readable by agents, and
what an agent reads goes into its transcript. Run a command that prints secrets in a terminal
outside the hub's tasks tabs. Not built yet, in case it is needed: a key that marks a pane as
private, so that `hub-run log` refuses to read it (the bar would still show its state and ports).

**Hub restart**: the tasks are panes of the hub session, so they stop when the hub quits or
starts fresh. `hub-run` keeps a record of each task it started (in
`~/.local/state/hub-tasks/started`, by hub server and pane id: pane ids start at 0 again in each
new hub). After a restart, `hub-run ls` lists those tasks as `gone` for a day, with the command
that starts each one again; `hub-run log|wait|stop <name>` say the same. `hub-run stop <name>`
forgets a gone task, and starting it again in its folder forgets it too.

| Command | What |
|---|---|
| `hub-run [-n name] [-w [-t s]] [--] <command...>` | a new pane in this worktree's tasks tab, in this folder; refuses a second copy of a command that runs in the same folder |
| `hub-run ls [--json]` | the tasks: pane, tab, name, state (running, idle, exited; gone after a hub restart), ports, worktree, command; in JSON also `agent` (who started it) and, for a gone task, `start` |
| `hub-run log <task> [-n lines \| --all]` | the pane's text (default: the last 100 lines) |
| `hub-run wait <task> [-t s]` | wait until the task listens (default 120 s); print its URLs, or its last lines when it ends |
| `hub-run stop <task>` | Ctrl-C to the command (TERM after 10 s, KILL after 5 s more); a pane that `hub-run` started closes, a shell stays |
| `hub-run restart <task>` | stop and start again in the same pane (panes that `hub-run` started) |
| `hub-run port <n>` | who listens on a port |

`<task>` is a name, a pane id (`terminal_3` or `3`), or a part of the command, folder or
worktree. When several match, `hub-run` lists them; use the pane id.

### Remove and prune

`d` on a row removes it after a confirm. It never forces.

- **Background agent**: `claude rm <id>`. It deletes the session and the worktree that Claude
  made for it, if any. Unpushed commits stop the removal. The transcript stays.
- **Interactive agent**: not removed. Close it in its tab, or `b` first.
- **Worktree**: `wt remove`, then `claude rm` for each idle background agent in it, then its tasks
  tab closes (the confirm names the agents and the tasks that run). The list never removes a
  main checkout. An agent that works, an interactive session, or an agent that came into the
  worktree with `EnterWorktree` (an orchestrator, say) stops the removal (the list names it). The branch is deleted only when it is merged. Uncommitted changes
  stop the removal, and then the agents and the tasks tab stay. A dim check sign and a dim name
  mark a worktree that is safe to remove.
- **Removed worktree** (a dim `(gone)` row): `claude rm` for each of its agents, with the same
  rules.

Dead agents are background agents whose folder is gone (a removed worktree) and that do not run
now. An agent that came into the worktree with `EnterWorktree` is not dead. The list removes them by itself every 10 minutes, with plain `claude rm`, and logs each one
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
| `n` | new idle background agent in this row's worktree (on a main checkout: the repo's orchestrator; when it has one, the hub shows it) |
| `N` | new worktree of this row's repo (asks the branch) + idle agent |
| `o` | the row's own Ghostty tab: an interactive agent's tab, else the worktree's zellij session (`wt open`) |
| `d` | remove the agent, or the worktree with its idle agents (asks first) |
| `b` | an idle interactive session goes on as a background agent (asks first) |
| `c` | an idle orchestrator (`◇`) or the hub Claude (`◆ hub` row) gets a fresh context: `/clear`, same prompt, name and id (asks first) |
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

### Review (lazygit, `WT_REVIEW=lazygit`)

`t` and `e` are lazygit custom commands (`config/lazygit/hub.yml`): lazygit does not run them
while you type in a prompt.

| Key | Action |
|---|---|
| `t` | toggle turns ⇄ commits |
| `e` | show files (yazi) over review |
| `q` | back: lazygit starts again on the newest turn |
| `Enter`, `Esc` | a turn's files, a file's diff; back |
| `v`, then `j` / `k` | select a range: one diff for many turns |
| `<` | newest turn |
| `[`, `]` | the other tabs: Files (the worktree's changes, in commits mode), Local branches |
| `+`, `_` | screen mode: the patch gets more or less of the pane |
| `?` | lazygit's own key help |

lazygit's own `t` (revert) and `e` (edit file) are not available in the hub; `o` opens a file.

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
| Ctrl g, `1` / `2` / `3` | list / middle / right column (`3` also shows a hidden review) |
| Ctrl g, `h` / `l` | pane to the left / right |
| Ctrl g, `;` | last pane |
| Ctrl g, `v` | hide or show review (see [Hide review](#hide-review)) |
| Ctrl g, Tab | hub tab ⇄ the picked worktree's tasks tab |
| Ctrl g, `r` | the launcher: start a task in the picked worktree (or this tab's worktree) |
| Ctrl g, Ctrl q | quit the hub (the agents keep running) |
| Ctrl g, Ctrl g / Esc / Enter | back to locked mode |
| Ctrl g, `p` `t` `r` `s` `m` `o` | zellij's pane, tab, resize, scroll, move and session modes |

### Pane titles

The titles show the keys of the panes that tuicr (or lazygit) and yazi fill:

- review: `turns · <repo>   e files · t commits` (or `commits · <repo>   e files · t turns`)
- files: `files · <repo>   e review · o open here · O editor tab · W open with`
- middle: the agent's name

## The list: rows and signs

The list shows each repo with a `.git` folder 1–2 levels under `$WT_ROOTS` (default
`~/Documents/projects`; more roots with `:`).

- `<root>/<client>/<repo>` goes under an orange heading for its client.
- `<root>/<repo>` goes under "Other" at the bottom.
- Under each repo (bold): its worktrees, the main checkout first (with a home sign); under each
  worktree, its agents. A repo row acts as its main checkout (`N`, `o`, click).
- A removed worktree that still has agents shows as a dim `<branch> (gone)` row of its repo.
  `d` on it removes those agents.
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
| `◆ hub` row (cyan) | the hub Claude, with its state sign |
| `◇` cyan, before the name | the repo's orchestrator: the oldest agent with the orchestrator prompt in its main checkout (also when it is in a worktree it entered) |
| `◇` yellow, before the name | a second agent with the orchestrator prompt in the same main checkout; remove it (`d`) |
| `→ feat` (dim, after the age) | the agent from the main checkout is in that worktree now (`EnterWorktree`); it shows under its main checkout |
| `!` bold yellow | agent needs input: it is blocked, or it asks you something |
| `✗` red | agent failed |
| `✓` bold magenta | done, unread: a turn ended after you last saw the agent |
| `●` dim green | agent works: its process is busy |
| `○` dim | idle: you saw it since its last turn, it is in the middle column now, or it waits for its first prompt |
| `bg 12m` (dim, after the name) | background agent; age (m, h, d) |
| Octicon home (U+F46D), before the branch | the main checkout |
| Octicon diff (U+F440), yellow | uncommitted changes |
| `↑N` cyan | commits to push (the branch is on the remote) |
| `↓N` cyan | commits to pull (the branch is on the remote) |
| `+N` green | commits not in the default branch (the branch is not on the remote) |
| Octicon alert (U+F421), red | a merge into the default branch would conflict |
| Octicon check (U+F42E), dim | safe to remove: the branch is empty or integrated (its name is dim too) |
| Octicon git-merge (U+F419), red | conflicts now, or a rebase or merge in progress |

The agents sort in the order of their state signs in the table (`!`, `✗`, `✓`, `●`, `○`). An
agent whose turn goes on while its process is idle (state `working`, status `idle`: it waits
for workers it started) does not work: it is unread or idle. You see an agent when it comes
into or leaves the middle column, when `wt go` shows it, and when its turn ends while its own
Ghostty tab is in front. The Stop hook (`claude-notify`) records when a turn ends. An agent
with no turn since this record started is idle. The list, `wt all`, `wt agents` and the mod
use one rule (`wtl_agent_phases` in `lib/wt-lib.sh`). `c` and `d` use it too.

"On the remote" means the branch has a tracking branch, or `origin/<branch>` exists (as for a PR
pushed without `-u`). The list uses local refs only; it does not fetch.

## Commands

All of these are in `~/.local/bin`. worktrunk runs `wt-<name>` for `wt <name>`, so `wt hub` and
`wt-hub` are the same. `-h` shows each script's header.

| Command | What it does |
|---|---|
| `wt hub [--here \| --tab \| --print-layout]` | Go to the hub's Ghostty tab, else open the hub in this terminal (attach, or a fresh start). A new tab without a terminal or inside another zellij session. `--here`: this terminal. `--tab`: a new tab. `--print-layout`: print the zellij layout. |
| `c [claude --bg options] [prompt]` | Claude in this folder as a background agent, attached here. Use it in place of `claude`. |
| `hub-run <command>` | Run a command in a new pane of this worktree's tasks tab in the hub; `ls`, `log`, `wait`, `stop`, `restart`, `port`. See [Tasks](#tasks-dev-servers). |
| `wt go <agent>` | Bring an agent in front: id, session id (or its start), name, or a part of a name (any case); `hub` is the hub Claude. Several name matches: the live ones win; still several is an error that lists them. A background agent opens in the hub when the hub runs (from anywhere, also from an agent), else in a `claude attach` tab. An interactive one: its own tab (or zellij pane). |
| `wt new <branch\|pr:N> [-b base] [-t "task"] [-a] [-- prompt...]` | Make (or reuse) the worktree and store the task note. With a prompt, or `-a` for an idle one, start a background agent there. Without `-t`, the first line of the prompt (60 characters) is the task note. |
| `wt-edit <file or folder>` | Open it in your editor, in its project. See [Open your editor](#open-your-editor). |
| `wt open [branch\|path]` | Select the Ghostty tab of the worktree's zellij session (named `<repo>.<branch>`), or open a tab that attaches to it (made with your default layout when new). |
| `wt all [-a]` | Worktrees of every repo, grouped by client, with agent counts (input, failed, unread, working, idle: the signs of the list) and task notes. `-a`: also repos with only a main checkout and no agent. |
| `wt all --json` | One JSON object per worktree (the list's data; implies `-a`). |
| `wt pick [-a]` | The same list in fzf, with git status and log in a preview. Enter: `wt open` on the row. Ctrl-A: `wt agents` for that worktree. |
| `wt agents [path]` | Claude sessions (all, or one worktree) in fzf, the ones that need input first. Enter: `wt go`. |
| `wt agents --json` | `claude agents --json --all` with each agent's `phase` (input, failed, unread, working, idle), for `wt all` and the mod. |
| `wt agents --orchestrators [main checkout]` | The orchestrator of each repo, one line each: main checkout, id, name (see [Orchestrators](#orchestrators)). |
| `claude-clear <id>` | Type `/clear` into idle background agent `<id>` through a hidden `claude attach` (`c` in the list). Exit 0 when its session id changed. See [Fresh context](#fresh-context). |
| `wt setup [path]` | The worktrunk `pre-start` hook, when you turn it on (`./install.sh --with-setup`): in a new worktree, copy the ignored files (`.worktreeinclude` through `wt step copy-ignored`, else the ignored `.env*` files of the main checkout) and install the dependencies (pnpm, bun, yarn, npm or uv, from the lock file). It puts back a lock file that the install changed. Safe to run again. |
| `wt task [text]` | worktrunk alias: set the worktree's task note, or show it. |
| `claude-turn-snapshot --list [path]` | The turn chains of a worktree: id, age, last subject. |
| `claude-turn-snapshot --prune [--dry-run]` | Remove the chains of agents that `claude agents --all` no longer lists, when their worktree is gone or their last turn is older than 7 days. It does nothing without an agent list or the worktree cache. |

Hooks and internal commands (not for hand use): `claude-notify` (Stop, Notification),
`claude-turn-snapshot` (UserPromptSubmit, Stop, PostToolUse), `hub-run --hook` (SessionStart), `hub-run --bar`
(the bar's tasks), `hub-run --tick` (the list's tick: a console in each tasks tab, the pane
names, the extra consoles, then the bar's tasks), `hub-run --where` (the hub banner's worktree, at each pick), `hub-run --switch`
(Ctrl g Tab), `hub-run --launcher` (Ctrl g r), `hub-run --worktree-tab <dir> --name|--tasks` and `hub-run --close-tab <name>`
(`d` on a worktree), `hub-run --exec` (a pane that `hub-run` started), `wt-sidebar` (the list),
`wt-sidebar --review toggle|show` (Ctrl g `v`, Ctrl g `3`), `wt-sidebar --files` (`e` in tuicr),
`wt-sidebar --clear <kind> <id>` (`c`),
`wt-hub-pane agent|review|files` (the panes), `wt-hub-keys` (tuicr's `t` and `e`).

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
| `hub-tasks/zdotdir/` | the launcher's zsh startup files: they load yours, then add its Enter |
| `hub-tasks/console-<pane>.line` | the line the launcher typed into a console, while it runs (its name in the bar, `restart`) |
| `hub-tasks/idle-<pane>` | when an extra console came to its prompt (it closes after 10 minutes) |
| `hub-tasks/launcher.history` | the launcher's history, for a shell other than zsh |

Elsewhere:

- `refs/wt-turns/<id>/{base,head,live}` in each repo: the turn chains.
- The task note: worktrunk's state variable `task` (`wt task`, `wt new -t`).
- `~/.local/share/wt-hub/`: `zjstatus-v0.25.0.wasm` (the bar), `mod/` (the mod, with
  `--with-mod`), `installed.txt` (the files `install.sh` installed).

Settings: `~/.config/wt-hub/config` ([Settings](#settings)). Environment variables only:
`WT_HUB_SESSION` (default `hub`), `WT_ZELLIJ_TIMEOUT` (default 5 s).

## Troubleshooting

- **The hub does not answer** (keys do nothing, a pick hangs): run `wt hub` in a terminal. It
  reuses a hub only when `zellij action list-clients` answers. Else it kills the hub's server,
  deletes the session and starts a fresh hub from the layout. The agents keep running; pick them
  again. Every zellij call in the scripts stops after 5 s (`WT_ZELLIJ_TIMEOUT`), so a stuck
  server cannot stop the list or a hook for long.
- **The list does not update**: press `r` in the list. It starts again as the newest
  `wt-sidebar` with fresh git signs.
- **No notices**: run `terminal-notifier -diagnose`. Look at
  `~/.local/state/claude-notify.log`: a line for each hook call means the hook runs. Remember the
  rule: no notice while Ghostty is in front with the agent's tab or the hub's tab selected.
- **A notice click does nothing**: look at the end of `claude-notify.log` for the output of
  `wt go`.
- **`o`, `wt open` or `O` in files does nothing**: tab control is off (not Ghostty). Run the
  command in a terminal to see the hint, or set `WT_TERMINAL=ghostty`.
- **Review shows tuicr's picker**: the agent has no turn chain yet (no change yet), or the branch has no commits of its own (commits mode). The chain opens by itself
  at the agent's first change (its running turn).
- **The middle column shows an old agent or an error**: pick the agent again, or press Enter in
  the middle column.

## Repo layout

```
bin/
  c                      Claude as a background agent, attached here
  claude-clear           /clear into an idle background agent (c in the list)
  claude-notify          hook (Stop, Notification): macOS notice; a click runs wt go; turn ends
                         for the unread sign
  claude-turn-snapshot   hook (UserPromptSubmit, Stop, PostToolUse): turn chains; --list, --prune
  hub-run                tasks in a tasks tab per worktree: start, ls, log, wait, stop, restart,
                         port; --switch (Ctrl g Tab), --tick, --bar, --hook, --exec (its panes)
  wt-agents              wt agents: Claude sessions in fzf; --json with each agent's phase
  wt-all                 wt all: worktrees of every repo; --json for the list
  wt-pick -> wt-all      wt pick: the same in fzf, Enter opens
  wt-edit                open a file or folder in your editor, in its project
  wt-go                  wt go: bring an agent in front (hub, tab or pane)
  wt-hub                 wt hub: start, attach or go to the hub; writes its layout
  wt-hub-keys            pty wrapper around tuicr: t (toggle mode), e (files)
  wt-hub-lazygit         lazygit as review (WT_REVIEW=lazygit): a turn chain's view repo
  wt-hub-pane            a hub pane (agent | review | files) that follows its target
  wt-new                 wt new: worktree, task note, background agent
  wt-open                wt open: the worktree's zellij session in a Ghostty tab
  wt-setup               optional worktrunk pre-start hook: ignored files, dependencies
  wt-sidebar             the list (fzf): rows, keys, remove, prune, new agents; --review
                         (Ctrl g v, 3: hide or show review)
lib/
  wt-lib.sh              shared helpers: zellij timeout, Ghostty tabs, hub panes and targets,
                         the hub Claude and orchestrator prompts, job state (wtl_jobs)
config/
  claude-settings-hooks.json   hooks to merge into ~/.claude/settings.json
  lazygit/hub.yml              the hub's lazygit settings and keys (WT_REVIEW=lazygit)
  tuicr/config.toml            q_quits: q in review goes back
  worktrunk/config.toml        hub settings to copy into ~: worktree path <repo>.<branch>, Task column, task alias
  yazi/keymap.toml             hub-only yazi keys: e, O, W
mod/
  .claude-plugin/              plugin.json, marketplace.json (marketplace wt-hub)
  hooks/hooks.json             loads register.tsx
  hooks/register.tsx           /wt command, status line, toasts, dock pane
  hooks/model.ts               parsing and grouping of worktrees and agents
  types/index.d.ts             row and event types
  tests/wt-hub.test.tsx        mod tests
  tsconfig.json
install.sh               installer: copies or links, configs, hooks, zjstatus; --check, --uninstall
CLAUDE.md                rules for edits in this repo
docs/open-items.md       open items and known faults
```

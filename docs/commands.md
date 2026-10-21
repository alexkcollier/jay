# Commands

[README](../README.md) · [Working in the hub](working.md) · [Tasks](tasks.md#hub-run-commands) ·
[Orchestrators](orchestrators.md) · [State and logs](state-and-logs.md)

All of these are in `~/.local/bin`. worktrunk runs `wt-<name>` for `wt <name>`, so `wt hub` and
`wt-hub` are the same. `-h` shows each script's header.

| Command | What it does |
|---|---|
| `wt hub [--here \| --tab \| --print-layout]` | Go to the hub's Ghostty tab, else open the hub in this terminal (attach, or a fresh start). A new tab without a terminal or inside another zellij session. `--here`: this terminal. `--tab`: a new tab. `--print-layout`: print the zellij layout. |
| `c [claude --bg options] [prompt]` | Claude in this folder as a background agent, attached here. Use it in place of `claude`. |
| `hub-run <command>` | Run a command in a new pane of this worktree's tasks tab in the hub; `ls`, `log`, `wait`, `stop`, `restart`, `port`. See [Tasks](tasks.md). |
| `wt go <agent>` | Bring an agent in front: id, session id (or its start), name, or a part of a name (any case); `hub` is the hub Claude. Several name matches: the live ones win; still several is an error that lists them. A background agent opens in the hub when the hub runs (from anywhere, also from an agent), else in a `claude attach` tab. An interactive one: its own tab (or zellij pane). |
| `wt new <branch\|pr:N> [-b base] [-t "task"] [-a] [-- prompt...]` | Make (or reuse) the worktree and store the task note. With a prompt, or `-a` for an idle one, start a background agent there. Without `-t`, the first line of the prompt (60 characters) is the task note. |
| `wt-edit <file or folder>` | Open it in your editor, in its project. See [Open your editor](working.md#open-your-editor). |
| `wt open [branch\|path]` | Select the Ghostty tab of the worktree's zellij session (named `<repo>.<branch>`), or open a tab that attaches to it (made with your default layout when new). |
| `wt all [-a]` | Worktrees of every repo, grouped by client, with agent counts (input, failed, unread, working, idle: the signs of the list) and task notes. `-a`: also repos with only a main checkout and no agent. |
| `wt all --json` | One JSON object per worktree (the list's data; implies `-a`). |
| `wt pick [-a]` | The same list in fzf, with git status and log in a preview. Enter: `wt open` on the row. Ctrl-A: `wt agents` for that worktree. |
| `wt agents [path]` | Claude sessions (all, or one worktree) in fzf, the ones that need input first. Enter: `wt go`. |
| `wt agents --json` | `claude agents --json --all` with each agent's `phase` (input, failed, unread, working, idle), for `wt all` and the mod. |
| `wt agents --orchestrators [main checkout]` | The orchestrator of each repo, one line each: main checkout, id, name (see [Orchestrators](orchestrators.md)). |
| `claude-clear <id>` | Type `/clear` into idle background agent `<id>` through a hidden `claude attach` (`c` in the list). Exit 0 when its session id changed. See [Fresh context](orchestrators.md#fresh-context). |
| `wt setup [path]` | The worktrunk `pre-start` hook, when you turn it on (`./install.sh --with-setup`): in a new worktree, copy the ignored files (`.worktreeinclude` through `wt step copy-ignored`, else the ignored `.env*` files of the main checkout) and install the dependencies (pnpm, bun, yarn, npm or uv, from the lock file). It puts back a lock file that the install changed. Safe to run again. |
| `wt task [text]` | worktrunk alias: set the worktree's task note, or show it. |
| `claude-turn-snapshot --list [path]` | The turn chains of a worktree: id, age, last subject. |
| `claude-turn-snapshot --prune [--dry-run]` | Remove the chains of agents that `claude agents --all` no longer lists, when their worktree is gone or their last turn is older than 7 days. It does nothing without an agent list or the worktree cache. |

## Hooks and internal commands

Not for hand use:

- `claude-notify` (Stop, Notification)
- `claude-turn-snapshot` (UserPromptSubmit, Stop, PostToolUse)
- `hub-run --hook` (SessionStart), `hub-run --bar` (the bar's tasks), `hub-run --tick` (the
  list's tick: a console in each tasks tab, the pane names, the extra consoles, then the bar's
  tasks), `hub-run --where` (the hub banner's worktree, at each pick), `hub-run --switch`
  (Ctrl g Tab), `hub-run --launcher` (Ctrl g r), `hub-run --worktree-tab <dir> --name|--tasks`
  and `hub-run --close-tab <name>` (`d` on a worktree), `hub-run --exec` (a pane that `hub-run`
  started)
- `wt-sidebar` (the list), `wt-sidebar --review toggle|show` (Ctrl g `v`, Ctrl g `3`),
  `wt-sidebar --files` (`e` in tuicr), `wt-sidebar --clear <kind> <id>` (`c`)
- `wt-hub-pane agent|review|files` (the panes), `wt-hub-keys` (tuicr's `t` and `e`)

## The mod (`/wt` in Claude Code)

`mod/` is a Claude Code mod for any interactive session. The hub itself does not need it.
`./install.sh --with-mod` installs it (marketplace `wt-hub`).

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

# Commands

[README](../README.md) · [Working in the hub](working.md) · [Tasks](tasks.md#jay-run-commands) ·
[Orchestrators](orchestrators.md) · [State and logs](state-and-logs.md)

All of these are in `~/.local/bin`. `jay` alone opens the hub; `jay <name> [args]` runs
`jay-<name>` from PATH (as git does), so `jay new` and `jay-new` are the same. `jay --help`
lists the commands; `jay <name> -h` shows a command's own help.

worktrunk (`wt`) stays required: it does the worktree operations (`wt switch`, `wt list`,
`wt merge`, `wt remove`, `wt step`) and keeps the task notes (`wt task`). The hub does not use
worktrunk's `wt <name>` dispatch.

| Command | What it does |
|---|---|
| `jay [--here \| --tab \| --print-layout]` | Go to the hub's Ghostty tab, else open the hub in this terminal (attach, or a fresh start). A new tab without a terminal or inside another zellij session. `--here`: this terminal. `--tab`: a new tab. `--print-layout`: print the zellij layout. It does not start while the old hub (the zellij session `hub`, from before the rename) runs. |
| `jay --help` | The commands, one line each. |
| `c [claude --bg options] [prompt]` | Claude in this folder as a background agent, attached here. Use it in place of `claude`. `jay c` is the same. |
| `jay run <command>` | Run a command in a new pane of this worktree's tasks tab in the hub; `ls`, `log`, `wait`, `stop`, `restart`, `port`. See [Tasks](tasks.md). |
| `jay go <agent>` | Bring an agent in front: id, session id (or its start), name, or a part of a name (any case); `hub` is the hub Claude. Several name matches: the live ones win; still several is an error that lists them. A background agent opens in the hub when the hub runs (from anywhere, also from an agent), else in a `claude attach` tab. An interactive one: its own tab (or zellij pane). |
| `jay new <branch\|pr:N> [-b base] [-t "task"] [-a] [-- prompt...]` | Make (or reuse) the worktree (through `wt switch`) and store the task note. With a prompt, or `-a` for an idle one, start a background agent there. Without `-t`, the first line of the prompt (60 characters) is the task note. |
| `jay edit <file or folder>` | Open it in your editor, in its project. See [Open your editor](working.md#open-your-editor). |
| `jay open [branch\|path]` | Select the Ghostty tab of the worktree's zellij session (named `<repo>.<branch>`), or open a tab that attaches to it (made with your default layout when new). |
| `jay all [-a]` | Worktrees of every repo, grouped by client, with agent counts (input, failed, unread, working, idle: the signs of the list) and task notes. `-a`: also repos with only a main checkout and no agent. |
| `jay all --json` | One JSON object per worktree (the list's data; implies `-a`). |
| `jay pick [-a]` | The same list in fzf, with git status and log in a preview. Enter: `jay open` on the row. Ctrl-A: `jay agents` for that worktree. |
| `jay agents [path]` | Claude sessions (all, or one worktree) in fzf, the ones that need input first. Enter: `jay go`. |
| `jay agents --json` | `claude agents --json --all` with each agent's `phase` (input, failed, unread, working, idle), for `jay all` and the mod. |
| `jay agents --orchestrators [main checkout]` | The orchestrator of each repo, one line each: main checkout, id, name (see [Orchestrators](orchestrators.md)). |
| `jay clear <id>` | Type `/clear` into idle background agent `<id>` through a hidden `claude attach` (`c` in the list). Exit 0 when its session id changed. See [Fresh context](orchestrators.md#fresh-context). |
| `jay setup [path]` | The worktrunk `pre-start` hook, when you turn it on (`./install.sh --with-setup`): in a new worktree, copy the ignored files (`.worktreeinclude` through `wt step copy-ignored`, else the ignored `.env*` files of the main checkout) and install the dependencies (pnpm, bun, yarn, npm or uv, from the lock file). It puts back a lock file that the install changed. Safe to run again. |
| `wt task [text]` | worktrunk alias: set the worktree's task note, or show it. |
| `jay snapshot --list [path]` | The turn chains of a worktree: id, age, last subject. |
| `jay snapshot --prune [--dry-run]` | Remove the chains of agents that `claude agents --all` no longer lists, when their worktree is gone or their last turn is older than 7 days. It does nothing without an agent list or the worktree cache. |

The old names of wt-hub (`wt hub`, `wt new`, `hub-run`, `claude-clear`, ...) still work through
shims until you remove them (`./install.sh --no-compat`). See
[Coming from wt-hub](install.md#coming-from-wt-hub).

## Hooks and internal commands

Not for hand use:

- `jay-notify` (Stop, Notification)
- `jay-snapshot` (UserPromptSubmit, Stop, PostToolUse)
- `jay-run --hook` (SessionStart), `jay-run --bar` (the bar's tasks), `jay-run --tick` (the
  list's tick: a console in each tasks tab, the pane names, the extra consoles, then the bar's
  tasks), `jay-run --where` (the hub banner's worktree, at each pick), `jay-run --switch`
  (Ctrl g Tab), `jay-run --launcher` (Ctrl g r), `jay-run --worktree-tab <dir> --name|--tasks`
  and `jay-run --close-tab <name>` (`d` on a worktree), `jay-run --exec` (a pane that `jay run`
  started)
- `jay-sidebar` (the list), `jay-sidebar --review toggle|show` (Ctrl g `v`, Ctrl g `3`),
  `jay-sidebar --files` (`e` in tuicr), `jay-sidebar --clear <kind> <id>` (`c`)
- `jay-pane agent|review|files` (the panes), `jay-keys` (tuicr's `t` and `e`)
- `jay-lazygit` (review with `JAY_REVIEW=lazygit`), `jay-diff` (its patch)

## The mod (`/jay` in Claude Code)

`mod/` is a Claude Code mod for any interactive session. The hub itself does not need it.
`./install.sh --with-mod` installs it (marketplace `jay`).

| Command | What it does |
|---|---|
| `/jay` | turn the hub features on: status line with agent counts, toasts when an agent needs input or finishes |
| `/jay pane` | the worktree list in the dock |
| `/jay hub` | `jay` (its tab, or a new tab) |
| `/jay off` | turn them off |
| `/jay new <branch> [-t "task"] [-- prompt]` | `jay new` |
| `/jay go <agent>` | `jay go` |
| `/jay open <branch\|path>` | `jay open` |
| `/jay msg <agent> <text>` | send a message to an agent |
| `/jay refresh` | reload worktrees and agents now |

Check the mod after an edit: `cd mod && claude plugin test . && claude plugin validate .`. Edits
apply at the next session start or after `/reload-plugins`.

# 🐦 jay

A worktree and agent hub for macOS. The name: a blue jay, the bird in the real tree beside all
the worktrees. One session, "jay" (on jay's own tmux server, or in zellij), shows three columns:
a live list of the worktrees and Claude agents across your projects, the picked agent, and a
review of that agent's work (tuicr on its turns, or yazi on its files). Built on [worktrunk](https://github.com/max-sixty/worktrunk)
and Claude Code background agents.

## What the hub is

```
 ◆ JAY › hub › shop/fix-login   ● 1 working  ○ 2 idle                ● shop/fix-login web  14:05
┌ worktrees ─────────────┬ shop/fix-login ────────────┬ turns · shop   e files · t commits ────┐
│ ◆ hub ○                │  the picked agent:         │  review of the agent's turns (tuicr)   │
│ acme                   │  claude attach <id>        │                                        │
│  shop                  │                            │            e ⇅ e / q                   │
│   main                 │  type to the agent here    │                                        │
│   fix-login  ↑2        │                            │  files of the worktree (yazi),         │
│     ▸ ● shop/fix-login │  Ctrl+Z or ←: leave it     │  over review                           │
│                        │  (it keeps running)        │                                        │
│ ⏎ open  n new  d remove│                            │                                        │
│ ? all keys and signs   │                            │                                        │
└────────────────────────┴────────────────────────────┴────────────────────────────────────────┘
  list (jay-sidebar, fzf)    agent viewer (jay-pane agent)    review ⇄ files (jay-pane review/files)
```

- **List** (left, about 22 % of the width). Every repo, worktree and agent, grouped by client.
  The hub sees only the Claude agents (background and interactive) whose folder is in one of
  the `JAY_ROOTS` folders, and the hub Claude: the list and its counts, `jay agents`, `jay all`,
  `jay go`, the mod, the notices and the turn chains ignore all others. Agent rows update every
  few seconds, git signs every 30 s. A pick here drives the other two columns.
- **Agent viewer** (middle). `claude attach` on the picked background agent. You talk to the agent
  here. The pane title is the agent's name. A fresh hub opens on the hub Claude (see
  [The hub Claude](docs/working.md#the-hub-claude)); the "◆ hub" row in the list brings it back.
- **Review** (right). tuicr on the picked agent's turns (one commit per turn), or on the branch's
  commits. **Files** (yazi in the same worktree) opens over review and closes back to it.
  Ctrl g `v` hides review (the agent viewer gets its width) and shows it again.
- **Status line** (one line at the top of each tab; zjstatus in zellij, tmux's own status line in
  tmux). Left: the tab you are on, `◆ JAY › hub ›` and the picked worktree (on a tasks tab:
  `◆ JAY › tasks ›`, its worktree and the tasks that run elsewhere). Middle: the agent counts with
  their signs. Right: the tasks of all worktrees with the project of each (`● shop/fix-login web`;
  the picked worktree's bright, the others dim), then the time. When the line is too narrow, the
  other worktrees' tasks become `+N` first, then the picked worktree's tasks only their signs,
  then the counts lose their words; the left part is never cut.
- **tmux or zellij**: a new hub runs on jay's own tmux server; `JAY_MUX=zellij jay` runs the
  same hub in zellij, also beside a tmux hub. Without `JAY_MUX`, the scripts use the hub that
  runs. See [tmux or zellij](docs/install.md#tmux-or-zellij-jay_mux).
- **Idle agents stop**: the list stops a background agent that was idle for `JAY_AUTO_STOP`
  minutes (default 15) and that nothing needs (never the hub Claude or an orchestrator). Its row
  and its conversation stay; a pick or `jay wake <name>` starts it again. Until then SendMessage
  to it fails ("No agent named X is reachable"). See
  [Idle agents stop](docs/working.md#idle-agents-stop).
- **Tasks tabs** (one per worktree, Ctrl g Tab). Shell panes for dev servers, watchers and
  `docker compose up`, which you and the agents both see. See [Tasks](docs/tasks.md).

An agent in a repo's main checkout can be the repo's **orchestrator**: it plans and gives each
change to a worker, a background agent in a worktree of its own. A repo has none by default: the
hub Claude plans and starts workers for it. A worker reports back with SendMessage; when a send
fails because the list stopped the worker, `jay wake <name>` starts it again. See
[Orchestrators](docs/orchestrators.md).

## Before you start

- **macOS only.** The scripts drive Ghostty tabs through AppleScript, read the front app with
  `lsappinfo`, and use BSD `stat` and `cp -c`.
- **Ghostty** (1.3 or newer) is optional. The hub runs in any terminal, but tab control is
  Ghostty only: without it, `jay` does not find or open the hub's tab, `o` in the list does
  nothing, `jay open` and `O` in files print the command to run, and notices always show. See
  [Terminals](docs/install.md#terminals).
- **A Nerd Font** for the git signs (Octicons). Ghostty's built-in font has the symbols; in
  another terminal, set a Nerd Font.
- **Claude Code 2.1.304 or newer** (built on 2.1.304; tested versions:
  [Requirements](docs/install.md#requirements)), logged in. The hub uses background agents and
  their commands: `claude --bg`, `claude attach`, `claude agents --json --all`, `claude rm`,
  `claude logs`, `claude --bg --resume`, `claude stop` and `claude respawn`. It also
  uses hooks (in `~/.claude/settings.json`), and plugins for the optional `/jay` mod.
  `./install.sh --check` checks the version and these commands.
- **The tools that `install.sh` checks**:

  | Required | Install |
  |---|---|
  | tmux 3.5+ | `brew install tmux` |
  | zellij 0.45.1+ | `brew install zellij` |
  | worktrunk (`wt`) 0.80+ | `brew install worktrunk` |
  | fzf 0.74+ | `brew install fzf` |
  | jq 1.7+ | `brew install jq` |
  | tuicr 0.27+ | `brew install tuicr` |
  | yazi 26+ | `brew install yazi` |
  | Claude Code 2.1.304+ | `brew install --cask claude-code` |
  | git, python3 (`/usr/bin/python3`) | `xcode-select --install` |
  | perl, curl | part of macOS |

  | Optional | Install | Without it |
  |---|---|---|
  | terminal-notifier | `brew install terminal-notifier` | no notices |
  | Ghostty | `brew install --cask ghostty` | no tab control |
  | lazygit 0.66+, delta | `brew install lazygit git-delta` | review with tuicr only ([review options](docs/review.md#the-review-options)) |

  worktrunk does the worktree work (`wt switch`, `wt list`, `wt merge`, `wt remove`).
  `./install.sh` also gets zjstatus (the bar) from GitHub, and needs `~/.local/bin` on PATH.
  All versions: [Requirements](docs/install.md#requirements).

## Quick start

1. Install the tools and the hub:

   ```sh
   brew install worktrunk tmux zellij fzf jq tuicr yazi
   brew install --cask claude-code
   brew install terminal-notifier; brew install --cask ghostty   # optional
   git clone <this repo> jay && cd jay
   ./install.sh --check    # what is there and what is missing; changes nothing
   ./install.sh            # install
   ```

   Put `~/.local/bin` on PATH. Your repos go under `~/Documents/projects`
   (`<client>/<repo>` or `<repo>`); else set `JAY_ROOTS` in `~/.config/jay/config`. Optional:
   the pane keys that `./install.sh` prints. Details: [Install](docs/install.md).
2. Start the hub: `jay` (the tmux hub). In the zellij hub (`JAY_MUX=zellij jay`), at the first
   start, click the top line and press `y` (zjstatus asks for its permissions).
3. The first agent: press `n` on a worktree row in the list. The agent shows in the middle
   column: type its first prompt. Or, in a shell, `c` in place of `claude`.
4. The first worker: press `n` on the `main` row of a repo (the home sign). That starts the
   repo's orchestrator. Ask it for a change; it starts a worker in a new worktree with
   `jay new <branch> -- <prompt>`, and the worker shows in the list. Or press `N` on the repo
   row: the list asks for a branch and starts an idle agent in a new worktree.
5. Pick an agent (Enter or a double click; a click selects) to see it in the middle column and
   its turns in review.
   `?` in the list shows all keys and signs. Ctrl g, `q` leaves the tmux hub (it runs on; `jay`
   opens it again), and `tmux -L jay kill-server` ends it. In the zellij hub, Ctrl g, Ctrl q
   quits. The agents keep running.

`jay --help` lists all commands.

## Coming from wt-hub

jay was called wt-hub. The commands, the variables and the folders have new names:

| wt-hub | jay |
|---|---|
| `wt hub` | `jay` |
| `wt new`, `wt go`, `wt agents`, `wt all`, `wt pick`, `wt open` | `jay new`, `jay go`, `jay agents`, `jay all`, `jay pick`, `jay open` |
| `wt-edit`, `wt setup` | `jay edit`, `jay setup` |
| `hub-run` | `jay run` |
| `c` | `c` (or `jay c`) |
| `claude-clear`, `claude-turn-snapshot` | `jay clear`, `jay snapshot` |
| `WT_ROOTS`, `WT_REVIEW`, ... (all `WT_` settings) | `JAY_ROOTS`, `JAY_REVIEW`, ... |
| `WT_HUB_SESSION`, zellij session `hub` | `JAY_SESSION`, zellij session `jay` |
| `~/.config/wt-hub`, `~/.local/share/wt-hub`, `~/.local/state/wt-hub`, `wt-turns`, `hub-tasks` | `~/.config/jay`, `~/.local/share/jay`, `~/.local/state/jay` (with `turns`, `tasks`) |
| the mod `/wt` (marketplace `wt-hub`) | the mod `/jay` (marketplace `jay`) |

- Run `./install.sh` (or `./install.sh --link`) once. It moves your settings and the hub's state
  to the new folders and leaves a link at each old path. It replaces the old hooks in
  `~/.claude/settings.json` with the new ones, and it installs the mod again under its new
  name. Details: [Coming from wt-hub](docs/install.md#coming-from-wt-hub).
- Then restart the hub: quit it (Ctrl g, Ctrl q; the agents keep running) and run `jay`.
  `jay` does not start while the old session `hub` runs.
- Your old config file works as it is: the `WT_` names still work, and a `JAY_` name wins.
- The old commands still work for a while: shims under the old names run the new command. A
  shim of a command that you type (`wt new`, `hub-run`, ...) first prints one line, for
  example `wt new is now: jay new`. A shim of a hook or an internal script prints nothing.
  `./install.sh --no-compat` removes the shims and the links at the old paths;
  `./install.sh --compat` brings them back.
- The turn chains keep their git refs, `refs/wt-turns/<id>/...`: they live in each repo, and a
  new name would lose the old chains.

## Docs

- [Install](docs/install.md): requirements, terminals, install steps, settings, pane keys,
  uninstall.
- [Working in the hub](docs/working.md): start the hub and agents, pick, the middle column, the
  hub Claude, your editor, notices, remove and prune, idle agents stop (`jay wake`), Claude Code
  updates, quit.
- [Orchestrators](docs/orchestrators.md): when a repo gets one, the agent that plans and gives
  each change to a worker; its prompt, review and merge, fresh context, an example.
- [Review](docs/review.md): the review options (turns or commits, tuicr or lazygit, the patch
  renderers), review by turn, files, hide review.
- [Tasks](docs/tasks.md): dev servers in a tasks tab per worktree (`jay run`).
- [Keys](docs/keys.md): all keys of the list, the panes, review and files.
- [Signs](docs/signs.md): the list's rows and signs, and the agent states.
- [Commands](docs/commands.md): `jay`, `c`, `jay go`, `jay new`, `jay agents` and the others;
  the `/jay` mod.
- [State and logs](docs/state-and-logs.md): the hub's files in `~/.local/state/jay` and
  elsewhere.
- [Troubleshooting](docs/troubleshooting.md): symptoms and what to do (the hub does not answer,
  a send that fails, text or a picker in Claude that you did not type, a list that ignores
  clicks).
- [Repo layout](docs/layout.md): what each file in this repo is.
- [TODO.md](TODO.md): open items, known faults and the hub's decisions.
- [CLAUDE.md](CLAUDE.md): rules for edits in this repo, zellij 0.45 facts and tmux facts.
- [LICENSE](LICENSE): MIT.

## Work on jay

- `./install.sh --link` links the scripts and keys into the checkout, so an edit is live at
  once. Run it again after you add a script to `bin/`.
- Shell tests: `tests/run.sh` (bash 3.2, no network; a fake HOME, stubs for claude and zellij).
  `tests/run.sh <name>` runs only the test files whose name has `<name>`.
- Mod tests: `cd mod && claude plugin test . && claude plugin validate .`.
- Rules for edits: [CLAUDE.md](CLAUDE.md). Facts about your own machine go in `CLAUDE.local.md`
  (not in git).

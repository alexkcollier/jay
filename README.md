# wt-hub

A worktree and agent hub for macOS. One zellij session, "hub", shows three columns: a live list
of the worktrees and Claude agents across your projects, the picked agent, and a review of that
agent's work (tuicr on its turns, or yazi on its files). Built on
[worktrunk](https://github.com/max-sixty/worktrunk) and Claude Code background agents.

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
  [The hub Claude](docs/working.md#the-hub-claude)); the "◆ hub" row in the list brings it back.
- **Review** (right). tuicr on the picked agent's turns (one commit per turn), or on the branch's
  commits. **Files** (yazi in the same worktree) opens over review and closes back to it.
  Ctrl g `v` hides review (the agent viewer gets its width) and shows it again.
- **Banner** (top, zjstatus, blue). `◆ HUB › worktrees` and the picked worktree (on a tasks tab:
  `◆ HUB › tasks` and its worktree), and where `Ctrl g Tab` goes.
- **Bar** (bottom, zjstatus). `◆ hub`, the agent counts from the list, the tasks of all worktrees
  (`● web:5174`), the zellij mode when it is not locked and the time.
- **Tasks tabs** (one per worktree, Ctrl g Tab). Shell panes for dev servers, watchers and
  `docker compose up`, which you and the agents both see. See [Tasks](docs/tasks.md).

An agent in a repo's main checkout can be the repo's **orchestrator**: it plans and gives each
change to a worker, a background agent in a worktree of its own. See
[Orchestrators](docs/orchestrators.md).

## Before you start

- **macOS only.** The scripts drive Ghostty tabs through AppleScript, read the front app with
  `lsappinfo`, and use BSD `stat` and `cp -c`.
- **Ghostty** (1.3 or newer) is optional. The hub runs in any terminal, but tab control is
  Ghostty only: without it, `wt hub` does not find or open the hub's tab, `o` in the list does
  nothing, `wt open` and `O` in files print the command to run, and notices always show. See
  [Terminals](docs/install.md#terminals).
- **A Nerd Font** for the git signs (Octicons). Ghostty's built-in font has the symbols; in
  another terminal, set a Nerd Font.
- **Claude Code 2.1.304 or newer** (built on 2.1.304, tested with 2.1.306), logged in. The hub
  uses background agents and their commands: `claude --bg`, `claude attach`,
  `claude agents --json --all`, `claude rm`, `claude logs` and `claude --bg --resume`. It also
  uses hooks (in `~/.claude/settings.json`), and plugins for the optional `/wt` mod.
  `./install.sh --check` checks the version and these commands.
- **The tools that `install.sh` checks**:

  | Required | Install |
  |---|---|
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

  `./install.sh` also gets zjstatus (the bar) from GitHub, and needs `~/.local/bin` on PATH.
  All versions: [Requirements](docs/install.md#requirements).

## Quick start

1. Install the tools and the hub:

   ```sh
   brew install worktrunk zellij fzf jq tuicr yazi
   brew install --cask claude-code
   brew install terminal-notifier; brew install --cask ghostty   # optional
   git clone <this repo> wt-hub && cd wt-hub
   ./install.sh --check    # what is there and what is missing; changes nothing
   ./install.sh            # install
   ```

   Put `~/.local/bin` on PATH. Your repos go under `~/Documents/projects`
   (`<client>/<repo>` or `<repo>`); else set `WT_ROOTS` in `~/.config/wt-hub/config`. Optional:
   the pane keys that `./install.sh` prints. Details: [Install](docs/install.md).
2. Start the hub: `wt hub`. At the first start, click the bar and press `y` (zjstatus asks for
   its permissions).
3. The first agent: press `n` on a worktree row in the list. The agent shows in the middle
   column: type its first prompt. Or, in a shell, `c` in place of `claude`.
4. The first worker: press `n` on the `main` row of a repo (the home sign). That starts the
   repo's orchestrator. Ask it for a change; it starts a worker in a new worktree with
   `wt new <branch> -- <prompt>`, and the worker shows in the list. Or press `N` on the repo
   row: the list asks for a branch and starts an idle agent in a new worktree.
5. Pick an agent (click or Enter) to see it in the middle column and its turns in review.
   `?` in the list shows all keys and signs. Quit the hub with Ctrl g, Ctrl q: the agents keep
   running.

## Docs

- [Install](docs/install.md): requirements, terminals, install steps, settings, pane keys,
  uninstall.
- [Working in the hub](docs/working.md): start the hub and agents, pick, the middle column, the
  hub Claude, your editor, notices, remove and prune, quit.
- [Orchestrators](docs/orchestrators.md): one agent per repo that plans and gives each change to
  a worker; its prompt, review and merge, fresh context, an example.
- [Review](docs/review.md): the review options (turns or commits, tuicr or lazygit, the patch
  renderers), review by turn, files, hide review.
- [Tasks](docs/tasks.md): dev servers in a tasks tab per worktree (`hub-run`).
- [Keys](docs/keys.md): all keys of the list, the panes, review and files.
- [Signs](docs/signs.md): the list's rows and signs, and the agent states.
- [Commands](docs/commands.md): `wt hub`, `c`, `wt go`, `wt new`, `wt agents` and the others;
  the `/wt` mod.
- [State and logs](docs/state-and-logs.md): the hub's files in `~/.local/state` and elsewhere.
- [Troubleshooting](docs/troubleshooting.md): what to do when the hub does not answer.
- [Repo layout](docs/layout.md): what each file in this repo is.
- [TODO.md](TODO.md): open items, known faults and the hub's decisions.
- [CLAUDE.md](CLAUDE.md): rules for edits in this repo, and zellij 0.45 facts.
- [LICENSE](LICENSE): MIT.

## Work on wt-hub

- `./install.sh --link` links the scripts and keys into the checkout, so an edit is live at
  once. Run it again after you add a script to `bin/`.
- Shell tests: `tests/run.sh` (bash 3.2, no network; a fake HOME, stubs for claude and zellij).
  `tests/run.sh <name>` runs only the test files whose name has `<name>`.
- Mod tests: `cd mod && claude plugin test . && claude plugin validate .`.
- Rules for edits: [CLAUDE.md](CLAUDE.md). Facts about your own machine go in `CLAUDE.local.md`
  (not in git).

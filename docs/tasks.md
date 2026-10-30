# Tasks (dev servers)

[README](../README.md) · [Working in the hub](working.md) · [Commands](commands.md) ·
[Keys](keys.md#panes-zellij-every-session)

- [The tasks tab](#the-tasks-tab)
- [The bar and the task panes](#the-bar-and-the-task-panes)
- [Other shells](#other-shells)
- [Ports](#ports)
- [Docker](#docker)
- [Output and secrets](#output-and-secrets)
- [Hub restart](#hub-restart)
- [jay run commands](#jay-run-commands)

## The tasks tab

Each worktree gets its own tasks tab in the hub for long-running commands: `pnpm dev`, watchers,
`docker compose up`. The tab is named `<repo>/<branch> · <client>` and is made the first time it
is needed. Each pane in a tasks tab is a task. You and the agents see the same panes. The status
line at the top of each tab says which tab you are on: `◆ JAY › hub › <picked worktree>` on the
hub tab, `◆ JAY › tasks › <its worktree>` on a tasks tab. Ctrl g Tab goes from one to the other.

- **Ctrl g Tab**: from the hub tab to the tasks tab of the worktree you picked (agent or
  worktree row; a new tab when it has none); from a tasks tab back to the hub. With an agent
  picked whose worktree runs no task, it goes to the tab of the newest task that agent started
  with `jay run` (a dev server in another worktree). zellij has no key action for a tab by
  name, so the key runs `jay-run --switch` in a floating pane of 1 cell that closes at once. A
  pick does not change the tab you are on.
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
  launcher. `jay run restart` works on a command that the launcher typed (Ctrl-C, then the same
  line again). Other shells: see [Other shells](#other-shells).
- **From elsewhere**: `jay run <command>` in any folder (a Ghostty tab, `! jay run pnpm dev` in a
  Claude prompt) opens a new pane in that worktree's tasks tab, in that folder, and leaves you
  where you are. `-n <name>` names it; `-w` waits until it listens and prints its URL. When the
  hub does not run, it runs the command in your terminal.
- **Agents**: a SessionStart hook (`jay-run --hook`) tells each Claude session to start dev
  servers with `jay run -n <name> -w -- <command>`, not with a background Bash call. Then the
  task runs where you see it, and it keeps running after the agent stops. Agents read any task,
  also the ones you typed: `jay run ls --json`, `jay run log <task>`.

## The bar and the task panes

The right part of the status line shows each task that runs or ended: its sign, the project it
runs in (the repo for a main checkout, `repo/branch` for a worktree) and its name:
`● shop/fix-login web` (runs), `✗ shop admin` (failed), `○ shop build` (ended with 0). The
tasks of the picked worktree come first and bright, the others dim. A shell at its prompt is not
shown. No ports in the line: `jay run ls` has them, and so do the task panes' titles
(`web · :5173`). The list sends the tasks every 3 s. When the line is too narrow, the other
worktrees' tasks become `+N`, then the picked worktree's tasks only their signs. A tasks tab's
left part says how many tasks run in other worktrees, and where
(`2 running elsewhere: shop, acme-api`); in the zellij hub that count is from the picked
worktree. Ctrl g `t` lists all tasks (project, name, state, ports): Enter goes to the task's tab.

A pane that `jay run` started shows `$ <command>` at the top. When the command ends, the pane says
`exited (<code>) · Enter: run again · q: close`. Ctrl-C stops the command, not the pane. The
command runs as you would type it: `$SHELL -i +m -c <line>` for zsh and bash (your rc file, so
aliases and `mise activate` apply; `+m`: no job control, so Ctrl-C reaches all of it), else
`$SHELL -l -c`. `JAY_TASK_SHELL` ([Settings](install.md#settings)) changes it.

## Other shells

The launcher is built in for zsh; another shell gets a plain prompt (line editing and its own
history). For your own shell, set `JAY_LAUNCHER` to a command that runs in the launcher pane (in
the worktree) and hands what you type to `jay-run --launch -- "<line>"` (it types the line into
the console and shows a quick command's output). The command gets `JAY_LAUNCH_IN`: the name of
the tasks tab. For example bash (also macOS `/bin/bash` 3.2), in `~/.config/jay/config`:
`JAY_LAUNCHER=BASH_SILENCE_DEPRECATION_WARNING=1 /bin/bash --rcfile ~/.config/jay/launcher.bash -i`,
with this `~/.config/jay/launcher.bash`:

```bash
[[ -f ~/.bashrc ]] && source ~/.bashrc
_jay_run() {   # Enter puts its name before the line; the line comes back from the history
  local line
  line=$(HISTTIMEFORMAT= history 1 | sed -E 's/^ *[0-9]+ +_jay_run //')
  jay-run --launch -- "$line" || read -rsn1 -p 'Press a key.'
  exit
}
bind '"\C-m": "\C-a_jay_run \C-j"'
PS1='❯ '   # one line: the pane title says where the command runs
```

## Ports

There is no port config. Vite and Next take the next free port by themselves; the hub finds the
ports that each task's processes listen on (`lsof`), and for `docker compose` the ports that its
containers publish. `jay run ls` and the task panes' titles show them, so an agent can give a frontend its
backend's URL (`VITE_API_URL=http://localhost:<port> pnpm dev`). For "address in use",
`jay run port <n>` tells who holds the port: a task (with its pane), a Docker container (with its
compose project), or another process (with its folder).

## Docker

A `docker compose up` task stops its containers on Ctrl-C and on `jay run stop` (the containers
stay, stopped). Two worktrees get different compose projects (compose names them after the
folder), but their published ports collide unless the compose file takes them from variables
(`${DB_PORT:-5432}:5432`).

## Output and secrets

There are no log files. A pane's output stays in zellij's scrollback (`scroll_buffer_size`,
default 10000 lines), as in any zellij pane, or in tmux's (`history-limit` 50000 in the tmux
hub); `jay run log` reads it with `zellij action dump-screen` (tmux: `capture-pane`) at that
moment. Every pane in a tasks tab is readable by agents, and
what an agent reads goes into its transcript. Run a command that prints secrets in a terminal
outside the hub's tasks tabs. Not built yet, in case it is needed: a key that marks a pane as
private, so that `jay run log` refuses to read it (the bar would still show its state and ports).

## Hub restart

The tasks are panes of the hub session, so they stop when the hub quits or starts fresh.
`jay run` keeps a record of each task it started (in `~/.local/state/jay/tasks/started`, by hub
server and pane id: pane ids start at 0 again in each new hub). After a restart, `jay run ls`
lists those tasks as `gone` for a day, with the command that starts each one again;
`jay run log|wait|stop <name>` say the same. `jay run stop <name>` forgets a gone task, and
starting it again in its folder forgets it too.

## jay run commands

| Command | What |
|---|---|
| `jay run [-n name] [-w [-t s]] [--] <command...>` | a new pane in this worktree's tasks tab, in this folder; refuses a second copy of a command that runs in the same folder |
| `jay run ls [--json]` | the tasks: pane, tab, name, state (running, idle, exited; gone after a hub restart), ports, worktree, command; in JSON also `agent` (who started it) and, for a gone task, `start` |
| `jay run log <task> [-n lines \| --all]` | the pane's text (default: the last 100 lines) |
| `jay run wait <task> [-t s]` | wait until the task listens (default 120 s); print its URLs, or its last lines when it ends |
| `jay run stop <task>` | Ctrl-C to the command (TERM after 10 s, KILL after 5 s more); a pane that `jay run` started closes, a shell stays. In a pane that `jay run` started, it also waits for the processes that ran under the command (turbo's dev servers can end after turbo) |
| `jay run restart <task>` | stop as `stop` does, then start again in the same pane (panes that `jay run` started): the new run starts only when all of the old one ended |
| `jay run port <n>` | who listens on a port |

`<task>` is a name, a pane id (`terminal_3` or `3`), or a part of the command, folder or
worktree. When several match, `jay run` lists them; use the pane id.

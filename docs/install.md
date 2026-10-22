# Install

[README](../README.md) · [Working in the hub](working.md) · [Keys](keys.md) ·
[Troubleshooting](troubleshooting.md)

- [Requirements](#requirements)
- [Terminals](#terminals)
- [Install steps](#install-steps)
- [What the installer does](#what-the-installer-does)
- [Coming from wt-hub](#coming-from-wt-hub)
- [Settings](#settings)
- [Pane keys](#pane-keys)
- [The tmux hub (JAY_MUX=tmux)](#the-tmux-hub-jay_muxtmux)
- [Uninstall](#uninstall)
- [Work on jay](#work-on-jay)

## Requirements

The versions are the ones the hub was tested with (2026-10-20); `./install.sh --check` checks
the minimum versions. The hub is macOS only: it drives Ghostty tabs through AppleScript and
reads the front app with `lsappinfo`.

### Required

| Tool | Tested with | From | Used for |
|---|---|---|---|
| macOS | 27.0.1 | | `osascript`, `lsappinfo`, `stat -f`, `cp -c` |
| zellij | 0.45.1 | `brew install zellij` | the hub session; the scripts use 0.45 behavior (see [CLAUDE.md](../CLAUDE.md)) |
| worktrunk (`wt`) | 0.80.0 | `brew install worktrunk` | the worktree operations (`wt switch`, `wt list`, `wt merge`, `wt remove`, `wt step`), `wt list` data, task notes |
| fzf | 0.74.1 (0.74+) | `brew install fzf` | the list (`--footer`, `transform-footer`, `--listen`, `--id-nth`) |
| jq | 1.7.1 | `brew install jq` (in `/usr/bin` on recent macOS) | all JSON |
| tuicr | 0.27.0 | `brew install tuicr` | review |
| yazi | 26.9.1 (26.x) | `brew install yazi` | files |
| Claude Code | 2.1.308 (2.1.304+; built on 2.1.304) | the native installer or `brew install --cask claude-code` ([Claude Code and its updates](#claude-code-and-its-updates)) | `claude --bg`, `claude attach`, `claude agents --json --all`, `claude rm`, `claude logs`, `claude --bg --resume`, `claude respawn`, hooks, the mod |
| git | 2.54.0 (Apple) | Xcode Command Line Tools | worktrees, turn chains |
| bash | 3.2.57 (`/bin/bash`) | macOS | every script (`#!/usr/bin/env bash` finds `/bin/bash`) |
| python3 | 3.9.6 (`/usr/bin/python3`) | Xcode Command Line Tools | `jay-keys`, `jay clear` |
| perl | 5.34.1 | macOS | the 5 s timeout around every zellij call |
| lsof | macOS | macOS | the ports of the tasks (`jay run`) |
| curl | 8.7.1 | macOS | the list's fzf socket |

### Optional

| Tool | Without it | Tested with | From | Used for |
|---|---|---|---|---|
| zjstatus | zellij's compact bar at the bottom, no status line | 0.25.0 | `./install.sh` gets it from GitHub: `~/.local/share/jay/zjstatus-v0.25.0.wasm` | the status line at the top of each tab (zellij hub) |
| tmux | the zellij hub only | 3.8 (3.5+) | `brew install tmux` | the tmux hub (`JAY_MUX=tmux`), on jay's own server and config; see [The tmux hub](#the-tmux-hub-jay_muxtmux). Required when `JAY_MUX=tmux` is set |
| Nerd Font | the git signs show as boxes | | Ghostty's built-in font has the Nerd Font symbols; in another terminal, set a Nerd Font | the Octicons in the git signs |
| Ghostty | no tab control ([Terminals](#terminals)) | 1.3.2 (1.3+) | `brew install --cask ghostty` | tabs through AppleScript: `jay`, `jay go`, `jay open`, `jay edit`, notices |
| terminal-notifier | no notices | 3.1.0 | `brew install terminal-notifier` | notices |
| lazygit | review with tuicr only | 0.66.2 (0.66+) | `brew install lazygit` | review with `JAY_REVIEW=lazygit` |
| delta | lazygit review shows git's plain diff, under the line "delta is not installed" (only for `JAY_REVIEW=lazygit`) | 0.19.2 | `brew install git-delta` | the patch in lazygit review (`jay-diff`) |
| difftastic (`difft`) | the difftastic renderer shows git's plain diff, under the line "difft is not installed" (only for `JAY_REVIEW=lazygit`) | 0.71.0 | `brew install difftastic` | the patch in lazygit review with `JAY_REVIEW_DIFF=difft` |
| Docker | no ports for `docker compose` tasks | 29.8.2, Compose 5.5.1 | Docker Desktop | reads (never changes) the published ports of `docker compose` tasks for `jay run ls` and the bar, and names the container in `jay run port` |

What `./install.sh --check` checks:

- macOS.
- zellij 0.45.1, worktrunk 0.80.0, fzf 0.74.0, jq 1.7, tuicr 0.27.0, yazi 26.0 or newer. Each
  missing or old tool is a TODO line with its `brew install` command, and the result at the end
  gives one `brew install` command for all missing tools. A program that is on PATH but does
  not run (a broken shim, say) is a TODO too.
- lazygit 0.66.0 or newer and delta, only when `JAY_REVIEW=lazygit`; else a note. difftastic
  only when `JAY_REVIEW_DIFF=difft` too; else a note.
- Claude Code 2.1.304 or newer, and the features of the hub in its help texts: `--bg`,
  `agents --json --all`, `attach`, `rm`, `logs`; a note when it has no `respawn`.
- git, perl, curl and `/usr/bin/python3`. Without the Xcode Command Line Tools, `/usr/bin/git`
  and `/usr/bin/python3` only ask macOS to install them: the check can open that dialog. Run
  `xcode-select --install` first.
- terminal-notifier and Ghostty (in `/Applications` or `~/Applications`): notes when they are
  missing (both are optional).
- `~/.local/bin` on PATH.
- An install of wt-hub (the old name): a TODO that `./install.sh` moves it to the new names.

### Claude Code and its updates

The hub works with both installs of Claude Code. It reads the installed version with
`claude --version` (from the `claude` on PATH) and the version each agent runs from its process.

| Install | How | Binary | Updates |
|---|---|---|---|
| Native installer | `curl -fsSL https://claude.ai/install.sh \| bash` | `~/.local/bin/claude`, a link to `~/.local/share/claude/versions/<version>` | by itself in the background (the updater moves the link); `claude update` by hand. Claude's daemon restarts itself when the link changes. |
| Homebrew cask | `brew install --cask claude-code` | `/opt/homebrew/bin/claude`, a link into `/opt/homebrew/Caskroom/claude-code/<version>/` | `brew upgrade --cask claude-code` (Claude Code does not update a Homebrew install by itself) |

Use one of the two. With both, the `claude` that comes first on PATH is the installed one for
the hub.

After an update, new agents and new `claude attach` clients use the new version at once. A
background agent that runs keeps the version it started with; the list marks it with `↻` and
moves it to the new version at a quiet moment (`claude respawn`). See
[Claude Code updates](working.md#claude-code-updates); `JAY_AUTO_RESPAWN=off` turns that off.

## Terminals

The hub itself runs in any terminal: run `jay` in it. Tab control is Ghostty only (other
terminals can come later). Tab control is on when Ghostty runs and the caller's terminal, if it
has one, is Ghostty (`TERM_PROGRAM`). `JAY_TERMINAL=ghostty` turns it on, any other value turns
it off. Without tab control:

- `jay` does not look for the hub's tab, and it does not open a new tab: it prints a hint.
- `jay go` still shows a background agent in the hub when the hub runs. Else it prints the
  `claude attach` command. `o` in the list does nothing.
- `jay open` and `jay edit` with a terminal editor (`O` in files) print the command to run.
- Notices always show (no "agent's tab in front" rule). A click still shows a background agent
  in the hub, but it does not bring the terminal to the front.

## Install steps

1. Install the tools with Homebrew:

   ```sh
   brew install worktrunk zellij fzf jq tuicr yazi
   brew install --cask claude-code    # or the native installer (Claude Code and its updates)
   # optional:
   brew install terminal-notifier     # macOS notices when an agent finishes or needs input
   brew install --cask ghostty        # tab control (jay, jay go, jay open, O in files)
   brew install lazygit git-delta     # review with lazygit (JAY_REVIEW=lazygit)
   brew install difftastic            # its patch with difftastic (JAY_REVIEW_DIFF=difft)
   ```

   Without terminal-notifier there are no notices; the rest works. Without Ghostty the hub runs
   in any terminal, but without tab control (see [Terminals](#terminals)). Log in to Claude Code
   once (`claude`) before you start agents.
2. Get the repo and run the installer. The repo can be anywhere:

   ```sh
   git clone <this repo> jay && cd jay
   ./install.sh --check    # what is there and what is missing; changes nothing
   ./install.sh            # install
   ```

   `~/.local/bin` must be on PATH. The installer does what the table in
   [What the installer does](#what-the-installer-does) says. It never replaces a file that it
   did not install: it lists it as a TODO (`--force` replaces it). It never edits
   `~/.config/zellij/config.kdl`: it prints the pane keys (see [Pane keys](#pane-keys)). It ends
   with "Ready", or with the TODO items. Run it again after a `git pull`: the copies do not
   change when the repo changes.
3. Optional: the pane keys in `~/.config/zellij/config.kdl` (see [Pane keys](#pane-keys)).
4. Start the hub: `jay`. At the first start, zellij asks for the status line's permissions:
   click the top line and press `y`. The first click on a notice (or the first `jay` from a script)
   can make macOS ask for permission to control Ghostty: allow it.
5. Optional: worktrunk's own Claude Code plugin:
   `claude plugin marketplace add max-sixty/worktrunk && claude plugin install worktrunk@worktrunk`.

Options of `install.sh`: `--link` (symlinks in place of copies, for work on jay),
`--with-mod` (the `/jay` mod), `--with-setup` (`jay-setup` as worktrunk's `pre-start` hook),
`--force` (replace files that jay did not install), `--check` (report only),
`--no-compat` (remove the shims of the old wt-hub names, and do not install them again),
`--compat` (install the shims again), `--uninstall`, `-h`.

## What the installer does

| What | Where |
|---|---|
| the scripts in `bin/`, `lib/jay-lib.sh` and the mux backends `lib/jay-mux-*.sh` | `~/.local/bin`, `~/.local/lib` (copies; `--link`: symlinks) |
| the tmux hub's config (`config/tmux/jay.conf`) | `~/.config/jay/tmux.conf` |
| the shims of the old names (`compat/`, `lib/wt-lib.sh`; not after `--no-compat`) | `~/.local/bin`, `~/.local/lib` |
| your settings, all at their defaults (see [Settings](#settings)) | `~/.config/jay/config`, made when missing |
| the hub's yazi keys | `~/.config/jay/yazi` |
| the hub's lazygit settings (for `JAY_REVIEW=lazygit`) | `~/.config/jay/lazygit` |
| tuicr's `q_quits = true` | `~/.config/tuicr/config.toml`, made when missing; else checked |
| the hub's worktrunk settings | `~/.config/worktrunk/config.toml`, copied when missing; else the missing keys are listed |
| the hooks (SessionStart, Stop, UserPromptSubmit, PreToolUse, PostToolUse, Notification) | added to `~/.claude/settings.json`, only the missing ones, after a backup |
| zjstatus v0.25.0 (the bar) | `~/.local/share/jay/`, sha256 checked |
| the mod (`/jay`), with `--with-mod` | `~/.local/share/jay/mod`, marketplace `jay` |
| `jay-setup` as worktrunk's `pre-start` hook, with `--with-setup` | `~/.config/worktrunk/config.toml` (see `jay setup` in [Commands](commands.md)) |

The hooks come from `config/claude-settings-hooks.json`. The installer adds a hook only when
`settings.json` does not have its command for that event yet, so your own hooks stay.

| Hook | Event | What it does |
|---|---|---|
| `jay-run --hook` | SessionStart | tells each agent to start dev servers as hub tasks ([Tasks](tasks.md)) |
| `jay-snapshot` | UserPromptSubmit, PostToolUse, Stop | the turn chains for review by turn ([Review](review.md)) |
| `jay-notify` | Stop, Notification | the macOS notices ([Working in the hub](working.md)) |
| `jay-guard` | PreToolUse (Bash) | stops an orchestrator's git commands that change its main checkout ([Orchestrators](orchestrators.md#skills-and-slash-commands)) |

`jay-guard` runs before each Bash call of each session. For a session that is not an
orchestrator, it exits at once (no `CLAUDE_JOB_DIR`, or no orchestrator prompt in the job).

## Coming from wt-hub

jay was called wt-hub. The name table is in the [README](../README.md#coming-from-wt-hub). On an
install of wt-hub, `./install.sh` (or `./install.sh --link`) does these steps first, in this
order:

1. It moves the old folders and files to the new places, and leaves a symlink at each old
   path, so a hub of the old version keeps working until you restart it:

   | Old | New |
   |---|---|
   | `~/.config/wt-hub` | `~/.config/jay` |
   | `~/.local/share/wt-hub` | `~/.local/share/jay` |
   | `~/.local/state/wt-hub` | `~/.local/state/jay` |
   | `~/.local/state/wt-turns` | `~/.local/state/jay/turns` |
   | `~/.local/state/hub-tasks` | `~/.local/state/jay/tasks` |
   | the other state files (`wt-hub-claude`, `wt-hub-review.mode`, `claude-notify.log`, ...) | their new names in `~/.local/state/jay` (see [State and logs](state-and-logs.md)) |

   When the new place exists already, it moves only what the new place does not have. It
   changes the list of installed files (`installed.txt`) to the new paths. Your config file
   stays as it is: the `WT_` names in it still work.
2. It installs the scripts and keys, and the shims: an old script or link under an old name
   becomes its shim.
3. In `~/.claude/settings.json`, it removes the hub's old hook commands (`claude-notify`,
   `claude-turn-snapshot` and `hub-run --hook` in `.local/bin`, also with a `VAR=value` before
   them) and adds the new ones (`jay-run --hook`, `jay-notify`, `jay-snapshot`). Your other
   hooks stay. A backup comes first: `settings.json.jay-backup.<time>`.
4. The mod: after the rename, Claude cannot load an installed old mod (marketplace `wt-hub` or
   `alex-wt-hub`, plugin `wt-hub`): "Plugin wt-hub not found in marketplace". The installer
   uninstalls `wt-hub@<old marketplace>`, removes that marketplace, adds the marketplace again
   and installs `jay@jay`. It uses the same folder when its `marketplace.json` now says `jay`,
   else a copy in `~/.local/share/jay/mod`. It does this on each install that finds the old
   mod, also without `--with-mod`.
5. worktrunk: `--with-setup` writes `pre-start = "jay-setup"`. An old `pre-start = "wt-setup"`
   still works through its shim; the check notes that you can change it to `jay-setup`.
6. Pane keys: old binds that run `hub-run` or `wt-sidebar` still work through the shims; the
   check notes that you can change them to `jay-run` and `jay-sidebar`.
7. When the old hub (the zellij session `hub`) runs, the result says so: quit it (Ctrl g,
   Ctrl q; the agents keep running), then start the hub with `jay`. `jay` does not start a
   second hub while the old session runs; it gives the same advice.

The shims: under each old name, a small script runs the new command. A command that you type
(`wt hub`, `wt new`, `wt go`, `wt agents`, `wt all`, `wt pick`, `wt open`, `wt-edit`, `hub-run`)
first prints one line to stderr, for example `wt new is now: jay new`. A hook or an internal
script (`claude-notify`, `claude-turn-snapshot`, `claude-clear`, `wt-setup`, `wt-sidebar`,
`wt-hub-pane`, `wt-hub-keys`, `wt-hub-lazygit`, `wt-hub-diff`) prints nothing: the output of a
hook can become Claude's context. `hub-run` prints nothing for its internal options (`--hook`,
`--switch`, `--launcher`, `--exec`, ...). The shims are there for agents whose prompts still
name the old commands, for the hooks and pane keys of an old config, and for habits.

`./install.sh --no-compat` removes the shims and the links at the old paths, and remembers that
(the file `~/.local/share/jay/no-compat`): later installs leave them out. `./install.sh --compat`
installs them again.

The turn chains keep their git refs, `refs/wt-turns/<id>/...`: they live in each repo, and a new
name would lose the old chains.

## Settings

`~/.config/jay/config` holds `KEY=value` lines; `#` starts a comment. An environment variable
of the same name wins over the file. The file also reaches what a shell profile does not: the
hooks in background agents and a notice click.

| Key | Default | What |
|---|---|---|
| `JAY_ROOTS` | `~/Documents/projects` | the folders with your repos, `:` between them; the list shows each repo 1–2 levels under them |
| `JAY_EDITOR` | `$VISUAL`, else `$EDITOR`, else `nvim` | the editor for `O` in files and `jay edit` |
| `JAY_EDITOR_GUI` | a guess from the editor's name | `1`: a GUI editor, `0`: a terminal editor |
| `JAY_TERMINAL` | on when Ghostty runs | `ghostty`: tab control on; another value: off |
| `JAY_TASK_SHELL` | `$SHELL -i +m -c` (zsh, bash), else `$SHELL -l -c` | how a task runs its command line, which comes after these words |
| `JAY_LAUNCHER` | the built-in zsh launcher | a command for the launcher (Ctrl g `r`) in another shell; see [Tasks](tasks.md#other-shells) |
| `JAY_REVIEW` | `tuicr` | the review pane: `tuicr` (review comments) or `lazygit` (git actions); see [Review with lazygit](review.md#review-with-lazygit) |
| `JAY_REVIEW_DIFF` | `delta` | the patch in lazygit review: `delta`, `difft` (difftastic) or `plain` (delta, no wrap); see [The patch in lazygit](review.md#the-patch-in-lazygit) |
| `JAY_AUTO_RESPAWN` | `idle` | after a Claude Code update: `idle`, the list moves each agent that runs the old version onto the new one at a quiet moment; `off`, only `jay respawn` does; see [Claude Code updates](working.md#claude-code-updates) |
| `JAY_MUX` | `zellij` | the hub's multiplexer: `zellij` or `tmux` (jay's own tmux server); see [The tmux hub](#the-tmux-hub-jay_muxtmux) |
| `JAY_ORCHESTRATE` | none | the repos that always get an orchestrator, `:` between them: a repo's name as the list shows it (`shop`), or `client/repo` (`acme/shop`) when two clients have a repo of that name; any case. A pick of a row of such a repo starts its orchestrator when it has none; see [When to start one](orchestrators.md#when-to-start-one) |

The old `WT_` names (`WT_ROOTS`, `WT_REVIEW`, ...) still work, in the file and in the
environment; a `JAY_` name wins over a `WT_` name. `./install.sh --check` tells you when a
`JAY_ROOTS` folder does not exist.

Environment variables only: `JAY_SESSION` (default `jay`), `JAY_ZELLIJ_TIMEOUT` (default 5 s),
`JAY_TMUX_SOCKET` (the tmux hub's socket name, default `jay`), `JAY_TMUX_TIMEOUT` (default 5 s).
The old `WT_HUB_SESSION` and `WT_ZELLIJ_TIMEOUT` still work.

Your own worktrunk settings, for example aliases for one client's repo, go in
`~/.config/worktrunk/config.toml`, not in this repo.

## Pane keys

Optional pane keys, in `~/.config/zellij/config.kdl`. The hub expects `default_mode "locked"`,
with `Ctrl g` to normal mode and `Ctrl q` to quit. Add these binds to the `normal` block of
`keybinds` (`./install.sh` prints them with your home folder):

```kdl
normal {
    bind "h" { MoveFocus "left"; SwitchToMode "locked"; }
    bind "l" { MoveFocus "right"; SwitchToMode "locked"; }
    bind "1" { MoveFocus "left"; MoveFocus "left"; SwitchToMode "locked"; }
    bind "2" { MoveFocus "left"; MoveFocus "left"; MoveFocus "right"; SwitchToMode "locked"; }
    bind "3" { MoveFocus "right"; MoveFocus "right"; Run "/Users/<you>/.local/bin/jay-sidebar" "--review" "show" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
    bind ";" { FocusLastPane; SwitchToMode "locked"; }
    bind "v" { Run "/Users/<you>/.local/bin/jay-sidebar" "--review" "toggle" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
    bind "Tab" { Run "/Users/<you>/.local/bin/jay-run" "--switch" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
    bind "r" { Run "/Users/<you>/.local/bin/jay-run" "--launcher" { floating true; close_on_exit true; x "20%"; y "35%"; width "60%"; height "3"; }; SwitchToMode "locked"; }
}
```

`Tab`, `v` and `3` run a script in a floating pane of 1 cell that closes at once: zellij has no
key action for a tab by name. What each key does: [Keys](keys.md#panes-zellij-every-session).
Binds of wt-hub (`hub-run`, `wt-sidebar`) still work through the shims.

The tmux hub needs none of these: its keys ship in `~/.config/jay/tmux.conf`.

## The tmux hub (JAY_MUX=tmux)

The hub can run on tmux instead of zellij (optional for now; zellij stays the default). It runs
on jay's own tmux server (`tmux -L jay`) with jay's own config (`~/.config/jay/tmux.conf`, from
`config/tmux/jay.conf`; `./install.sh` puts it there). Your `~/.tmux.conf`, your own tmux
sessions and `~/.config/zellij/config.kdl` do not matter to it. The layout, the picks, review
and files, the tasks windows, the bar and the keys (Ctrl g, then one key: [Keys](keys.md#panes-the-tmux-hub))
are the same as in the zellij hub.

1. `brew install tmux` (3.5 or newer), then `./install.sh` (it installs the config).
2. Try it beside the zellij hub: in a new Ghostty tab, `JAY_MUX=tmux jay`. Each hub keeps its
   panes' state apart (the tmux hub in `~/.local/state/jay/tmux`); both show the same agents,
   marks, turn chains and hub Claude. Both can show the hub Claude at once: its screen then
   takes the size of the last view that opened it.
3. To keep it: `JAY_MUX=tmux` in `~/.config/jay/config`. Then `jay`, `jay go`, `jay run` and the
   notices use the tmux hub; without the line, agents' `jay run` and notices go to the zellij
   hub.

`jay` attaches to the tmux hub when it runs. Ctrl g `q` detaches; `tmux -L jay kill-server`
ends it (its tasks stop, the agents run on). Ghostty sends Shift+Enter and the other modified
keys through tmux to Claude (extended keys, tested with `claude attach` in a tmux pane).

## Uninstall

`./install.sh --uninstall` removes what it installed, the shims and the links at the old
paths, and lists the hooks and the mod to remove by hand. It keeps `~/.config/jay/config`,
`~/.config/worktrunk/config.toml` and `~/.local/state`.

## Work on jay

`./install.sh --link` links the scripts and keys into the checkout, so an edit is live at once.
Run it again after you add a script to `bin/`. `./install.sh --check` notes when the links go
into another checkout of jay. Tests: `tests/run.sh` (the shell part) and
`cd mod && claude plugin test . && claude plugin validate .` (the mod). Rules for edits:
[CLAUDE.md](../CLAUDE.md).

### Move the checkout folder

A checkout from before the rename can keep its folder name (say `wt-hub`). To give it the new
name later, by hand:

1. Quit the hub (Ctrl g, Ctrl q). Do this when no agent works in the checkout or its
   worktrees.
2. `mv <projects>/wt-hub <projects>/jay`, then `cd <projects>/jay`.
3. `git worktree repair`: the repo's worktrees find the moved checkout again.
4. `./install.sh --link`: the links go into the new folder.
5. Start the hub: `jay`.

Claude keeps the folder trust per path: the first `c` or `n` in the moved folder asks again.

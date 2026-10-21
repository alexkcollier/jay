# Install

[README](../README.md) · [Working in the hub](working.md) · [Keys](keys.md) ·
[Troubleshooting](troubleshooting.md)

- [Requirements](#requirements)
- [Terminals](#terminals)
- [Install steps](#install-steps)
- [What the installer does](#what-the-installer-does)
- [Settings](#settings)
- [Pane keys](#pane-keys)
- [Uninstall](#uninstall)
- [Work on wt-hub](#work-on-wt-hub)

## Requirements

The versions are the ones the hub was tested with (2026-10-20); `./install.sh --check` checks
the minimum versions. The hub is macOS only: it drives Ghostty tabs through AppleScript and
reads the front app with `lsappinfo`.

| Tool | Tested with | From | Used for |
|---|---|---|---|
| macOS | 27.0.1 | | `osascript`, `lsappinfo`, `stat -f`, `cp -c` |
| Ghostty | 1.3.2 (1.3+) | `brew install --cask ghostty` (optional) | tabs through AppleScript: `wt hub`, `wt go`, `wt open`, `wt-edit`, notices |
| zellij | 0.45.1 | `brew install zellij` | the hub session; the scripts use 0.45 behavior (see [CLAUDE.md](../CLAUDE.md)) |
| zjstatus | 0.25.0 | GitHub release, `~/.local/share/wt-hub/zjstatus-v0.25.0.wasm` | the bar; without it the hub uses zellij's compact bar |
| worktrunk (`wt`) | 0.80.0 | `brew install worktrunk` | worktrees, `wt list` data, task notes, `wt remove`; `wt <name>` runs `wt-<name>` from PATH |
| fzf | 0.74.1 (0.74+) | `brew install fzf` | the list (`--footer`, `transform-footer`, `--listen`, `--id-nth`) |
| jq | 1.7.1 | `brew install jq` | all JSON |
| tuicr | 0.27.0 | `brew install tuicr` | review |
| lazygit | 0.66.2 (0.66+) | `brew install lazygit` (optional) | review with `WT_REVIEW=lazygit` |
| delta | 0.19.2 | `brew install git-delta` (optional) | the patch in lazygit review (`wt-hub-diff`) |
| difftastic (`difft`) | 0.71.0 | `brew install difftastic` (optional) | the patch in lazygit review with `WT_REVIEW_DIFF=difft` |
| yazi | 26.9.1 (26.x) | `brew install yazi` | files |
| terminal-notifier | 3.1.0 | `brew install terminal-notifier` (optional) | notices |
| Nerd Font | | Ghostty's built-in font has the Nerd Font symbols; in another terminal, set a Nerd Font | the Octicons in the git signs |
| Claude Code | 2.1.306 (2.1.304+; built on 2.1.304) | `brew install --cask claude-code` | `claude --bg`, `claude attach`, `claude agents --json --all`, `claude rm`, `claude logs`, `claude --bg --resume`, hooks, the mod |
| git | 2.54.0 (Apple) | Xcode Command Line Tools | worktrees, turn chains |
| bash | 3.2.57 (`/bin/bash`) | macOS | every script (`#!/usr/bin/env bash` finds `/bin/bash`) |
| python3 | 3.9.6 (`/usr/bin/python3`) | Xcode Command Line Tools | `wt-hub-keys`, `claude-clear` |
| perl | 5.34.1 | macOS | the 5 s timeout around every zellij call |
| lsof | macOS | macOS | the ports of the tasks (`hub-run`) |
| Docker | 29.8.2, Compose 5.5.1 | Docker Desktop (optional) | the ports of `docker compose` tasks, `hub-run port` |
| curl | 8.7.1 | macOS | the list's fzf socket |

What `./install.sh --check` checks:

- macOS.
- zellij 0.45.1, worktrunk 0.80.0, fzf 0.74.0, jq 1.7, tuicr 0.27.0, yazi 26.0 or newer. Each
  missing or old tool is a TODO line with its `brew install` command, and the result at the end
  gives one `brew install` command for all missing tools. A program that is on PATH but does
  not run (a broken shim, say) is a TODO too.
- lazygit 0.66.0 or newer and delta, only when `WT_REVIEW=lazygit`; else a note. difftastic
  only when `WT_REVIEW_DIFF=difft` too; else a note.
- Claude Code 2.1.304 or newer, and the features of the hub in its help texts: `--bg`,
  `agents --json --all`, `attach`, `rm`, `logs`.
- git, perl, curl and `/usr/bin/python3`. Without the Xcode Command Line Tools, `/usr/bin/git`
  and `/usr/bin/python3` only ask macOS to install them: the check can open that dialog. Run
  `xcode-select --install` first.
- terminal-notifier and Ghostty (in `/Applications` or `~/Applications`): notes when they are
  missing (both are optional).
- `~/.local/bin` on PATH.

## Terminals

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

## Install steps

1. Install the tools with Homebrew:

   ```sh
   brew install worktrunk zellij fzf jq tuicr yazi
   brew install --cask claude-code
   # optional:
   brew install terminal-notifier     # macOS notices when an agent finishes or needs input
   brew install --cask ghostty        # tab control (wt hub, wt go, wt open, O in files)
   brew install lazygit git-delta     # review with lazygit (WT_REVIEW=lazygit)
   brew install difftastic            # its patch with difftastic (WT_REVIEW_DIFF=difft)
   ```

   Without terminal-notifier there are no notices; the rest works. Without Ghostty the hub runs
   in any terminal, but without tab control (see [Terminals](#terminals)). Log in to Claude Code
   once (`claude`) before you start agents.
2. Get the repo and run the installer. The repo can be anywhere:

   ```sh
   git clone <this repo> wt-hub && cd wt-hub
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
4. Start the hub: `wt hub`. At the first start, zellij asks for the bar's permissions: click
   the bar and press `y`. The first click on a notice (or the first `wt hub` from a script)
   can make macOS ask for permission to control Ghostty: allow it.
5. Optional: worktrunk's own Claude Code plugin:
   `claude plugin marketplace add max-sixty/worktrunk && claude plugin install worktrunk@worktrunk`.

Options of `install.sh`: `--link` (symlinks in place of copies, for work on wt-hub),
`--with-mod` (the `/wt` mod), `--with-setup` (`wt-setup` as worktrunk's `pre-start` hook),
`--force` (replace files that wt-hub did not install), `--check` (report only),
`--uninstall`, `-h`.

## What the installer does

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
| the mod (`/wt`), with `--with-mod` | `~/.local/share/wt-hub/mod`, marketplace `wt-hub` (a mod added under its old name `alex-wt-hub` counts too) |
| `wt-setup` as worktrunk's `pre-start` hook, with `--with-setup` | `~/.config/worktrunk/config.toml` (see `wt setup` in [Commands](commands.md)) |

The hooks come from `config/claude-settings-hooks.json`. The installer adds a hook only when
`settings.json` does not have its command for that event yet, so your own hooks stay.

## Settings

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
| `WT_LAUNCHER` | the built-in zsh launcher | a command for the launcher (Ctrl g `r`) in another shell; see [Tasks](tasks.md#other-shells) |
| `WT_REVIEW` | `tuicr` | the review pane: `tuicr` (review comments) or `lazygit` (git actions); see [Review with lazygit](review.md#review-with-lazygit) |
| `WT_REVIEW_DIFF` | `delta` | the patch in lazygit review: `delta`, `difft` (difftastic) or `plain` (delta, no wrap); see [The patch in lazygit](review.md#the-patch-in-lazygit) |

`./install.sh --check` tells you when a `WT_ROOTS` folder does not exist.

Environment variables only: `WT_HUB_SESSION` (default `hub`), `WT_ZELLIJ_TIMEOUT` (default 5 s).

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
    bind "3" { MoveFocus "right"; MoveFocus "right"; Run "/Users/<you>/.local/bin/wt-sidebar" "--review" "show" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
    bind ";" { FocusLastPane; SwitchToMode "locked"; }
    bind "v" { Run "/Users/<you>/.local/bin/wt-sidebar" "--review" "toggle" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
    bind "Tab" { Run "/Users/<you>/.local/bin/hub-run" "--switch" { floating true; close_on_exit true; x "100%"; y "100%"; width "1"; height "1"; }; SwitchToMode "locked"; }
    bind "r" { Run "/Users/<you>/.local/bin/hub-run" "--launcher" { floating true; close_on_exit true; x "20%"; y "35%"; width "60%"; height "3"; }; SwitchToMode "locked"; }
}
```

`Tab`, `v` and `3` run a script in a floating pane of 1 cell that closes at once: zellij has no
key action for a tab by name. What each key does: [Keys](keys.md#panes-zellij-every-session).

## Uninstall

`./install.sh --uninstall` removes what it installed and lists the hooks and the mod to remove by
hand. It keeps `~/.config/wt-hub/config`, `~/.config/worktrunk/config.toml` and
`~/.local/state`.

## Work on wt-hub

`./install.sh --link` links the scripts and keys into the checkout, so an edit is live at once.
Run it again after you add a script to `bin/`. `./install.sh --check` notes when the links go
into another checkout of wt-hub. Tests: `tests/run.sh` (the shell part) and
`cd mod && claude plugin test . && claude plugin validate .` (the mod). Rules for edits:
[CLAUDE.md](../CLAUDE.md).

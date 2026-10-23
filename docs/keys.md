# Keys

[README](../README.md) · [Working in the hub](working.md) · [Review](review.md) ·
[Signs](signs.md) · [Install: pane keys](install.md#pane-keys)

- [List](#list)
- [Agent viewer (middle column)](#agent-viewer-middle-column)
- [Review (tuicr)](#review-tuicr)
- [Review (lazygit, JAY_REVIEW=lazygit)](#review-lazygit-jay_reviewlazygit)
- [Files (yazi)](#files-yazi)
- [Panes (zellij, every session)](#panes-zellij-every-session)
- [Panes (the tmux hub)](#panes-the-tmux-hub)
- [Pane titles](#pane-titles)

## List

| Key | Action |
|---|---|
| Enter | open the row; the focus moves (agent: middle column; worktree: review). An agent that cannot wake (`home gone`, `lost`): continue it as a copy (asks first) |
| click | select the row: the cursor moves there and nothing else changes; the keys (`d`, `n`, `N`, `c`, `b`, `o`) then act on it. In the zellij hub, a click from another column first only gives the list the focus (zellij keeps that click); in the tmux hub one click selects |
| double-click | open the row, as Enter |
| `n` | new idle background agent in this row's worktree (on a main checkout: the repo's orchestrator; when it has one, the hub shows it) |
| `N` | new worktree of this row's repo (asks the branch) + idle agent |
| `o` | the row's own Ghostty tab: an interactive agent's tab, else the worktree's zellij session (`jay open`) |
| `d` | remove the agent, or the worktree with its idle agents (asks first; agents that came from it and are in another worktree go on there first, as copies) |
| `b` | an idle interactive session goes on as a background agent (asks first) |
| `c` | an idle orchestrator (`◇`) or the hub Claude (`◆ hub` row) gets a fresh context: `/clear`, same prompt, name and id (asks first). With a dim `⇡` (an older prompt than jay's), it also offers `y`: a new agent with the current prompt and the same name in place of the old one (`jay renew`) |
| `a` | hide / show idle repos (a main checkout row stays while its repo has other rows) |
| `p` | prune dead agents now (asks first) |
| `r` | reload the list (fresh git signs; starts the newest `jay-sidebar`) |
| `j` / `k`, ↓ / ↑, wheel | move |
| `-` / `+` (or `=`) | narrower / wider |
| `h`, `l` | nothing (the width is `-` / `+`; Ctrl g `h` / `l` go to the pane left or right) |
| `?` | all keys and signs (press again: fewer keys) |
| `q`, Esc, Ctrl-C, Ctrl-G, Ctrl-Q, Ctrl-D | nothing (the list belongs to the hub; when it ends anyway, it starts again) |

The list's keys act in the list only. The list has no key for review's mode or for files.

## Agent viewer (middle column)

| Key | Action |
|---|---|
| any key | goes to the agent (`claude attach`) |
| Ctrl+Z | leave the agent; it keeps running |
| ← | leave the agent (Claude's agent view is stopped; the list is that view) |
| Enter (after you left) | open the agent again; when it is gone, the agent that took its place (a `jay renew`, a copy, the current hub Claude), else the pane says it is gone |
| Enter (after a failed attach) | try again |

A pick shows "Opening <name>..." at once. A pick of the agent the column should show opens it
again when the column does not show it now: when Claude's agent view is on screen, or another
agent that you opened from there, or an error.

## Review (tuicr)

`jay-keys` runs tuicr and takes `t` and `e` while tuicr's status line shows NORMAL or SELECT.
In a comment, a `:` or `/` prompt or a paste, they go to tuicr.

| Key | Action |
|---|---|
| `t` | toggle turns ⇄ commits (from `jay-keys`) |
| `e` | show files (yazi) over review (from `jay-keys`) |
| `q` | back: tuicr starts again at its start (`q_quits`, `config/tuicr/config.toml`) |
| `(` | newest turn; press again for all turns (tuicr) |
| `i`, `:` | tuicr's include filter and commands |
| `?` | tuicr's own key help |
| Enter (after "tuicr closed") | open tuicr again |

tuicr's own `e` (exclude filter) is not available in the hub.

## Review (lazygit, JAY_REVIEW=lazygit)

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
| `0`, `Esc` | focus the patch (then `n` / `N` next or previous file, `l` / `h` next or previous hunk); back |
| `J`, `K` | scroll the patch from the list |
| `\|` | the next diff renderer (see [The patch in lazygit](review.md#the-patch-in-lazygit)) |
| `?` | lazygit's own key help |

lazygit's own `t` (revert) and `e` (edit file) are not available in the hub; `o` opens a file.

## Files (yazi)

From `config/yazi/keymap.toml` (hub only: `YAZI_CONFIG_HOME=~/.config/jay/yazi`). The other
keys are yazi's own (yazi's help: `~` or F1).

| Key | Action |
|---|---|
| `e` | back to review at once (jay closes the files pane; in a prompt, `e` is text) |
| `q` | quit yazi: back to review (in the tmux hub yazi takes 5 s to quit: use `e`) |
| `o` | open the hovered file in this pane (yazi's open; in the tmux hub the first `o` after files opens waits 5 s) |
| `O` | open the hovered file or folder in your editor, in its project, in a new tab (`jay edit`) |
| `W` | open with... (yazi's "open with" menu) |

## Panes (zellij, every session)

The hub runs zellij in locked mode. Ctrl g goes to normal mode; these keys act once and go back
to locked mode. `1` `2` `3` `h` `j` `k` `l` `;` `v` Tab `r` `t` need the binds in
[Install: pane keys](install.md#pane-keys); `j` and `k` are new (2026-10-23): add them by hand
to binds from before.

| Keys | Action |
|---|---|
| Ctrl g, `1` / `2` / `3` | list / middle / right column (`3` also shows a hidden review) |
| Ctrl g, `h` / `l` | pane to the left / right |
| Ctrl g, `j` / `k` | pane below / above |
| Ctrl g, `;` | last pane |
| Ctrl g, `v` | hide or show review (see [Hide review](review.md#hide-review)) |
| Ctrl g, Tab | hub tab ⇄ the picked worktree's tasks tab (or the tab of the newest task that the picked agent started) |
| Ctrl g, `r` | the launcher: start a task in the picked worktree (or this tab's worktree) |
| Ctrl g, `t` | all tasks in a picker (project, name, state); Enter: that task's tab |
| Ctrl g, Ctrl q | quit the hub (the agents keep running) |
| Ctrl g, Ctrl g / Esc / Enter | back to locked mode |
| Ctrl g, `p` `t` `r` `s` `m` `o` | zellij's pane, tab, resize, scroll, move and session modes |

## Panes (the tmux hub)

The tmux hub (the default; `JAY_MUX=tmux`) runs on jay's own tmux server with its own config
(`~/.config/jay/tmux.conf`, from `config/tmux/jay.conf`): your `~/.tmux.conf` does not load
there, and there is no prefix key. Ctrl g, then one key; the status line shows the keys (in
place of the agent counts) while it waits.

| Keys | Action |
|---|---|
| Ctrl g, `1` / `2` / `3` | list / middle / right column (`3` also shows a hidden review); a column whose pane was closed gets it back first |
| Ctrl g, `h` / `l` | pane to the left / right |
| Ctrl g, `j` / `k` | pane below / above |
| Ctrl g, `;` | last pane |
| Ctrl g, `v` | hide or show review |
| Ctrl g, Tab | hub window ⇄ the picked worktree's tasks window (as in zellij) |
| Ctrl g, `r` | the launcher, in a popup; its title says where the line runs. A command that ends shows its output in a popup of its size (any key closes it); one that runs on closes the launcher |
| Ctrl g, `t` | all tasks in a popup picker; Enter: that task's window |
| Ctrl g, `q` | quit this terminal's view (detach); the hub, the agents and the tasks run on. Ctrl g, Ctrl q (zellij's quit) does nothing here |
| Ctrl g, `[` | scroll mode (tmux's copy mode; `q` leaves it) |
| Ctrl g, Ctrl g | a Ctrl g for the program in the pane |
| any other key, Esc | back, nothing done |

`jay` attaches to the running tmux hub again. To end it: `tmux -L jay kill-server` (its tasks
stop; the agents keep running). The mouse: a click on a pane focuses it and reaches the program
at once (one click selects a row in the list, a double click opens it); drag a border to resize; the wheel scrolls a program that
takes the mouse, else tmux's scroll mode.

Alt+P and Alt+O do not reach the panes. tmux has no Cmd modifier: a Cmd key that Ghostty does
not use itself (Cmd+P, Cmd+O) comes to the pane as Alt+P (Claude's model picker) or Alt+O
(Claude's fast mode), and tmux cannot tell the two apart. In Claude, use `/model` and `/fast`.
Alt+Shift+P does not reach them either: a terminal reply that comes late (`ESC P …`) gets to the
pane as Alt+Shift+P and the reply's text, and Claude opens its model picker on it. Text such as
`>|ghostty 1.3.2` in Claude's input box is such a reply. See
[Troubleshooting](troubleshooting.md).

## Pane titles

The titles show the keys of the panes that tuicr (or lazygit) and yazi fill:

- review: `turns · <repo>   e files · t commits` (or `commits · <repo>   e files · t turns`)
- files: `files · <repo>   e review · o open here · O editor tab · W open with`
- middle: the agent's name

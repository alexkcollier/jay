# Troubleshooting

[README](../README.md) · [Install](install.md) · [State and logs](state-and-logs.md) ·
[TODO.md: known faults](../TODO.md#known-faults)

- **`./install.sh` lists TODO items**: do each one, then run it again. A tool that is on PATH but
  does not run (a broken shim, say) shows as "does not run": install it again.
- **The hub does not answer** (keys do nothing, a pick hangs): run `jay` in a terminal. It
  reuses a hub only when it answers (the tmux hub: `tmux -L jay has-session`; the zellij hub:
  `zellij action list-clients`). Else it kills the hub's server, removes the session and starts a
  fresh hub. The agents keep running; pick them again. Every tmux and zellij call in the scripts
  stops after 5 s (`JAY_TMUX_TIMEOUT`, `JAY_ZELLIJ_TIMEOUT`), so a stuck server cannot stop the
  list or a hook for long.
- **`jay` says the old hub runs**: the zellij session `hub` of wt-hub (before the rename) still
  runs. Quit it (Ctrl g, Ctrl q in it; the agents keep running), then run `jay` again.
- **The list, the middle column or review is gone** (the pane was closed, or zellij shows
  "exited" in it): run `jay`. It puts the missing pane back in its column at its saved width
  (or the hub tab, when it was closed). In the tmux hub, Ctrl g `1` `2` `3` do it too.
- **The list does not update**: press `r` in the list. It starts again as the newest
  `jay-sidebar` with fresh git signs.
- **The list ignores clicks** (the wheel and clicks do nothing, keys work): press `r` in the
  list. fzf turns the mouse off when a command of the list runs over 1 s. A pick and `o` no
  longer do that (they go on in the background after half a second); when it occurs anyway, `r`
  brings the mouse back.
- **A key in the list seems lost**: press it again. fzf drops a key that comes during a reload.
  The list reloads after a pick, and at its 4 s tick only when its rows changed. `h` and `l` do nothing in the list: the width is `-`
  and `+`.
- **SendMessage fails with "No agent named X is reachable"**: the agent does not run. The list
  stops an agent after `JAY_AUTO_STOP` minutes idle, and Claude retires idle agents after some
  hours. The failed message is lost. Run `jay wake X`, then send it again. See
  [A worker that does not run](orchestrators.md#a-worker-that-does-not-run). To keep agents
  running, set `JAY_AUTO_STOP=off` (or more minutes) in `~/.config/jay/config`.
- **An agent's idle notice says "X has exited before going idle"**: the list stopped X, which
  was idle already. `jay wake X` makes it reachable again.
- **Text such as `>|ghostty 1.3.2` in Claude's input box, or in the list** (the tmux hub): a reply
  of the terminal to a query reached the pane as keys. Delete it (Ctrl+U in Claude). jay's tmux
  config stops these replies since 2026-10-23: run `./install.sh` (it writes
  `~/.config/jay/tmux.conf`), then `tmux -L jay source-file ~/.config/jay/tmux.conf`, or restart
  the hub (`tmux -L jay kill-server`, then `jay`; its tasks stop).
- **Claude's model picker opens by itself** (the tmux hub): Claude got Alt+P, from Cmd+P or from
  a late terminal reply (`ESC P …`). Esc closes it. jay's tmux config stops Alt+P, Alt+Shift+P
  and Alt+O: install it as in the line above. In Claude, use `/model` and `/fast`. See
  [Keys](keys.md#panes-the-tmux-hub).
- **Files takes 5 s to close** (the tmux hub): `q` quits yazi, which waits for a terminal reply.
  Press `e`: jay closes files at once. See [Files](review.md#files).
- **No notices**: run `terminal-notifier -diagnose`. Look at
  `~/.local/state/jay/notify.log`: a line for each hook call means the hook runs. Remember the
  rule: no notice while Ghostty is in front with the agent's tab or the hub's tab selected.
- **A notice click does nothing**: look at the end of `notify.log` for the output of `jay go`.
- **A notice click opens a new Ghostty tab with `claude attach`** in place of the hub: `jay go`
  found no hub. Either the hub does not run, or `JAY_MUX` in `~/.config/jay/config` names the
  other hub: the click has no `JAY_MUX` in its environment, so the file's wins over the hub that
  runs. Remove that line, or set it to the hub you use. Run `./install.sh` after a `git pull`:
  the hooks run the installed copies.
- **`o`, `jay open` or `O` in files does nothing**: tab control is off (not Ghostty). Run the
  command in a terminal to see the hint, or set `JAY_TERMINAL=ghostty`.
- **Review shows tuicr's picker**: the agent has no turn chain yet (no change yet), or the branch
  has no commits of its own (commits mode). The chain opens by itself at the agent's first change
  (its running turn).
- **The middle column shows an old agent or an error**: pick the agent again, or press Enter in
  the middle column.
- **The middle column says "<name> is gone: claude agents does not list it"**: you left that agent,
  and it was removed with no agent in its place. Pick another agent in the list.
- **A `zellij pipe` process uses 100 % CPU** (Activity Monitor, `top`): a pipe to a zellij server
  that stopped, with its stdin open, waits for good. `pgrep -fl 'zellij.* pipe '` lists such
  processes; `kill <pid>` ends one. jay's own pipes (the zellij hub's status line) read no stdin
  and give up after 2 s (`JAY_ZELLIJ_PIPE_TIMEOUT`); run `./install.sh` when your copies are
  older. By hand, give `zellij pipe` `</dev/null` and a timeout.
- **"Workspace not trusted"** when an agent starts: Claude never ran in that repo. Press `n` or
  `N` in the list, or run `c` in the repo: they ask to trust it. See
  [Start agents](working.md#start-agents-in-the-background).
- **An agent started from another agent does not show in the list**: it inherited the caller's
  `CLAUDE*` variables (`CLAUDE_CODE_CHILD_SESSION` hides a session from `claude agents`). From an
  agent, start it with `jay new`, which removes them, or start it from the list.
- **An old command prints "... is now: jay ..."**: that is a shim of the old wt-hub name. It
  runs the new command. Use the new name. See [Coming from wt-hub](install.md#coming-from-wt-hub).
- **The mod shows "failed to load" (Plugin wt-hub not found)**: run `./install.sh`. It installs
  the mod again under its new name, `jay@jay`.
- **The middle column stops taking the mouse**: see [TODO.md](../TODO.md#known-faults).

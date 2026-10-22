# Troubleshooting

[README](../README.md) · [Install](install.md) · [State and logs](state-and-logs.md) ·
[TODO.md: known faults](../TODO.md#known-faults)

- **`./install.sh` lists TODO items**: do each one, then run it again. A tool that is on PATH but
  does not run (a broken shim, say) shows as "does not run": install it again.
- **The hub does not answer** (keys do nothing, a pick hangs): run `jay` in a terminal. It
  reuses a hub only when `zellij action list-clients` answers. Else it kills the hub's server,
  deletes the session and starts a fresh hub from the layout. The agents keep running; pick them
  again. Every zellij call in the scripts stops after 5 s (`JAY_ZELLIJ_TIMEOUT`), so a stuck
  server cannot stop the list or a hook for long.
- **`jay` says the old hub runs**: the zellij session `hub` of wt-hub (before the rename) still
  runs. Quit it (Ctrl g, Ctrl q in it; the agents keep running), then run `jay` again.
- **The list, the middle column or review is gone** (the pane was closed, or zellij shows
  "exited" in it): run `jay`. It puts the missing pane back in its column at its saved width
  (or the hub tab, when it was closed). In the tmux hub, Ctrl g `1` `2` `3` do it too.
- **The list does not update**: press `r` in the list. It starts again as the newest
  `jay-sidebar` with fresh git signs.
- **No notices**: run `terminal-notifier -diagnose`. Look at
  `~/.local/state/jay/notify.log`: a line for each hook call means the hook runs. Remember the
  rule: no notice while Ghostty is in front with the agent's tab or the hub's tab selected.
- **A notice click does nothing**: look at the end of `notify.log` for the output of `jay go`.
- **`o`, `jay open` or `O` in files does nothing**: tab control is off (not Ghostty). Run the
  command in a terminal to see the hint, or set `JAY_TERMINAL=ghostty`.
- **Review shows tuicr's picker**: the agent has no turn chain yet (no change yet), or the branch
  has no commits of its own (commits mode). The chain opens by itself at the agent's first change
  (its running turn).
- **The middle column shows an old agent or an error**: pick the agent again, or press Enter in
  the middle column.
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

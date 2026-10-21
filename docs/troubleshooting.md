# Troubleshooting

[README](../README.md) · [Install](install.md) · [State and logs](state-and-logs.md) ·
[TODO.md: known faults](../TODO.md#known-faults)

- **`./install.sh` lists TODO items**: do each one, then run it again. A tool that is on PATH but
  does not run (a broken shim, say) shows as "does not run": install it again.
- **The hub does not answer** (keys do nothing, a pick hangs): run `wt hub` in a terminal. It
  reuses a hub only when `zellij action list-clients` answers. Else it kills the hub's server,
  deletes the session and starts a fresh hub from the layout. The agents keep running; pick them
  again. Every zellij call in the scripts stops after 5 s (`WT_ZELLIJ_TIMEOUT`), so a stuck
  server cannot stop the list or a hook for long.
- **The list does not update**: press `r` in the list. It starts again as the newest
  `wt-sidebar` with fresh git signs.
- **No notices**: run `terminal-notifier -diagnose`. Look at
  `~/.local/state/claude-notify.log`: a line for each hook call means the hook runs. Remember the
  rule: no notice while Ghostty is in front with the agent's tab or the hub's tab selected.
- **A notice click does nothing**: look at the end of `claude-notify.log` for the output of
  `wt go`.
- **`o`, `wt open` or `O` in files does nothing**: tab control is off (not Ghostty). Run the
  command in a terminal to see the hint, or set `WT_TERMINAL=ghostty`.
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
  agent, start it with `wt new`, which removes them, or start it from the list.
- **The middle column stops taking the mouse**: see [TODO.md](../TODO.md#known-faults).

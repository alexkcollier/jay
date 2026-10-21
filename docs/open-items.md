# Open items and known faults

[README](../README.md) · [Troubleshooting](troubleshooting.md)

## Known faults

- **The agent viewer stops taking the mouse.** Seen a few times: in the middle column the wheel
  moves Claude's cursor (zellij sends arrow keys), and a drag makes zellij's own (green)
  selection. The other panes still take the mouse. A new pick does not fix it. It is not a
  Claude fault: zellij ignores the mouse modes of that pane. It was not seen again after the hub
  server stopped inheriting an agent's `CLAUDE*` variables (`wt hub --here` removes them). If it
  comes back: quit the hub (Ctrl g, Ctrl q) and run `wt hub` in a terminal that no agent
  started.
- **Tab control is Ghostty only.** Other terminals get the hub, but no tab control (see
  [Install](install.md#terminals)).
- **macOS only.** The scripts use AppleScript, `lsappinfo`, BSD `stat` and `cp -c`.

## Open items

- A key that marks a task pane as private, so that `hub-run log` refuses to read it (the bar would
  still show its state and ports). Not built; see [Tasks](tasks.md#output-and-secrets).
- Tab control for terminals other than Ghostty.
- Proposals that are on record, but not accepted: a tuicr config for the narrow review column
  (theme, unified diff, wrap gutter, compact folders), and a review with revdiff that sends review
  notes back to the agent.

## Not planned

- Bulk removal of worktrees (`wt step prune`): the list's dim check sign and `d` remove one
  worktree at a time, after a confirm. Be careful with `wt step prune` in your own repos: in one
  repo it would have deleted the `main` branch.

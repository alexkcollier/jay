# Repo layout

[README](../README.md) · [Commands](commands.md) · [Install](install.md#work-on-wt-hub)

```
bin/
  c                      Claude as a background agent, attached here
  claude-clear           /clear into an idle background agent (c in the list)
  claude-notify          hook (Stop, Notification): macOS notice; a click runs wt go; turn ends
                         for the unread sign
  claude-turn-snapshot   hook (UserPromptSubmit, Stop, PostToolUse): turn chains; --list, --prune
  hub-run                tasks in a tasks tab per worktree: start, ls, log, wait, stop, restart,
                         port; --switch (Ctrl g Tab), --tick, --bar, --hook, --exec (its panes)
  wt-agents              wt agents: Claude sessions in fzf; --json with each agent's phase;
                         --orchestrators
  wt-all                 wt all: worktrees of every repo; --json for the list
  wt-pick -> wt-all      wt pick: the same in fzf, Enter opens
  wt-edit                open a file or folder in your editor, in its project
  wt-go                  wt go: bring an agent in front (hub, tab or pane)
  wt-hub                 wt hub: start, attach or go to the hub; writes its layout
  wt-hub-keys            pty wrapper around tuicr: t (toggle mode), e (files)
  wt-hub-diff            the diff renderer of lazygit review: delta or difftastic, fit to the column
  wt-hub-lazygit         lazygit as review (WT_REVIEW=lazygit): a turn chain's view repo
  wt-hub-pane            a hub pane (agent | review | files) that follows its target
  wt-new                 wt new: worktree, task note, background agent
  wt-open                wt open: the worktree's zellij session in a Ghostty tab
  wt-setup               optional worktrunk pre-start hook: ignored files, dependencies
  wt-sidebar             the list (fzf): rows, keys, remove, prune, new agents; --review
                         (Ctrl g v, 3: hide or show review)
lib/
  wt-lib.sh              shared helpers: zellij timeout, Ghostty tabs, hub panes and targets,
                         the hub Claude and orchestrator prompts, job state (wtl_jobs)
config/
  claude-settings-hooks.json   hooks to merge into ~/.claude/settings.json
  lazygit/hub.yml              the hub's lazygit settings and keys (WT_REVIEW=lazygit)
  lazygit/diff-*.yml           another diff renderer first (WT_REVIEW_DIFF=difft, plain)
  tuicr/config.toml            q_quits: q in review goes back
  worktrunk/config.toml        hub settings to copy into ~: worktree path <repo>.<branch>, Task column, task alias
  yazi/keymap.toml             hub-only yazi keys: e, O, W
mod/
  .claude-plugin/              plugin.json, marketplace.json (marketplace wt-hub)
  hooks/hooks.json             loads register.tsx
  hooks/register.tsx           /wt command, status line, toasts, dock pane
  hooks/model.ts               parsing and grouping of worktrees and agents
  types/index.d.ts             row and event types
  tests/wt-hub.test.tsx        mod tests
  tsconfig.json
tests/
  run.sh                 the shell tests: bash 3.2, no network, a fake HOME, stubs for claude
                         and zellij; run.sh <name> runs the test files whose name has <name>
  lib.sh                 the helpers of the tests (fake HOME, stubs, checks)
  test-*.sh              the test files
docs/                    the documentation (this file, install, working, orchestrators, ...)
notes/
  lazygit-review.md      the study behind review with lazygit (7: the diff renderers)
  lazygit-diff/          screen dumps of the diff renderers at 60, 80 and 120 columns
install.sh               installer: copies or links, configs, hooks, zjstatus; --check, --uninstall
CLAUDE.md                rules for edits in this repo, and zellij 0.45 facts
TODO.md                  open items, known faults and the hub's decisions
LICENSE                  MIT
```

Not in git: `CLAUDE.local.md` (facts about your own machine for Claude; git ignores
`*.local.md`, Claude Code loads it with `CLAUDE.md`).

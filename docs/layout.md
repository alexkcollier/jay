# Repo layout

[README](../README.md) · [Commands](commands.md) · [Install](install.md#work-on-jay)

```
bin/
  jay                    jay: start, attach or go to the hub; writes its layout; jay <name>
                         runs jay-<name>; jay --help lists the commands
  jay-agents             jay agents: Claude sessions in fzf; --json with each agent's phase;
                         --orchestrators
  jay-all                jay all: worktrees of every repo; --json for the list
  jay-pick -> jay-all    jay pick: the same in fzf, Enter opens
  jay-c                  jay c: Claude as a background agent, attached here
  c -> jay-c             the short name of jay c
  jay-clear              jay clear: /clear into an idle background agent (c in the list)
  jay-diff               the diff renderer of lazygit review: delta or difftastic, fit to the column
  jay-edit               jay edit: open a file or folder in your editor, in its project
  jay-go                 jay go: bring an agent in front (hub, tab or pane)
  jay-keys               pty wrapper around tuicr: t (toggle mode), e (files)
  jay-lazygit            lazygit as review (JAY_REVIEW=lazygit): a turn chain's view repo
  jay-new                jay new: worktree, task note, background agent
  jay-notify             hook (Stop, Notification): macOS notice; a click runs jay go; turn ends
                         for the unread sign
  jay-open               jay open: the worktree's zellij session in a Ghostty tab
  jay-pane               a hub pane (agent | review | files) that follows its target
  jay-run                jay run: tasks in a tasks tab per worktree: start, ls, log, wait, stop,
                         restart, port; --switch (Ctrl g Tab), --tick, --bar, --hook, --exec
  jay-setup              jay setup: optional worktrunk pre-start hook: ignored files, dependencies
  jay-sidebar            the list (fzf): rows, keys, remove, prune, new agents; --review
                         (Ctrl g v, 3: hide or show review)
  jay-snapshot           hook (UserPromptSubmit, Stop, PostToolUse): turn chains; --list, --prune
compat/                  shims under the old wt-hub names (wt-new, hub-run, claude-notify, ...):
                         each runs the new command; ./install.sh --no-compat removes them
lib/
  jay-lib.sh             shared helpers: settings, zellij timeout, Ghostty tabs, hub panes and
                         targets, the hub Claude and orchestrator prompts, job state (jay_jobs)
  wt-lib.sh              shim: sources jay-lib.sh (scripts of an old install source this path)
config/
  claude-settings-hooks.json   hooks to merge into ~/.claude/settings.json
  lazygit/hub.yml              the hub's lazygit settings and keys (JAY_REVIEW=lazygit)
  lazygit/diff-*.yml           another diff renderer first (JAY_REVIEW_DIFF=difft, plain)
  tuicr/config.toml            q_quits: q in review goes back
  worktrunk/config.toml        hub settings to copy into ~: worktree path <repo>.<branch>, Task column, task alias
  yazi/keymap.toml             hub-only yazi keys: e, O, W
mod/
  .claude-plugin/              plugin.json, marketplace.json (marketplace jay)
  hooks/hooks.json             loads register.tsx
  hooks/register.tsx           /jay command, status line, toasts, dock pane
  hooks/model.ts               parsing and grouping of worktrees and agents
  types/index.d.ts             row and event types
  tests/jay.test.tsx           mod tests
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
install.sh               installer: copies or links, configs, hooks, zjstatus, the move from
                         wt-hub; --check, --no-compat, --compat, --uninstall
CLAUDE.md                rules for edits in this repo, and zellij 0.45 facts
TODO.md                  open items, known faults and the hub's decisions
LICENSE                  MIT
```

Not in git: `CLAUDE.local.md` (facts about your own machine for Claude; git ignores
`*.local.md`, Claude Code loads it with `CLAUDE.md`).

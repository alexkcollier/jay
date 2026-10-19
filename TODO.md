# Hub to-do

Continue Alex's hub to-do list. This repo (~/Documents/projects/wt-hub) is the live install of his worktree hub: ~/.local/bin, ~/.local/lib/wt-lib.sh, ~/mods/wt-hub and the worktrunk/zellij configs are symlinks into it. Read CLAUDE.md and README.md first, and your memory note "worktree-tooling-worktrunk" (decisions, zellij 0.45 facts, incidents). The hub is the zellij session "hub" (layout written by bin/wt-hub): worktree list (fzf, bin/wt-sidebar) | hub Claude ⇄ one agent viewer | review (tuicr via bin/wt-hub-pane) ⇄ files (yazi).

Alex's to-do list, in his words (2026-10-19):
1. Clean up the tops of the panes — "the stacks are cumbersome/ugly" (zellij stacked-pane title bars in the middle and right columns).
2. Nicer zellij UI — "the current tabs and hints are meh" (tab-bar and status-bar plugins in the hub layout).
3. Faster pane switching/navigation.
4. Keyboard hints in the worktree list, and the ability to remove agents and worktrees from it.
5. The agent panel sometimes stops responding to the mouse (added 2026-10-19).

How to work:
- Items 1 and 2 are taste: first show Alex 2–3 concrete options (short ASCII previews, what each costs), let him pick, then build. Items 3 and 4: propose the keys in one message, then build.
- Removing a worktree is destructive: confirm in the UI first, use `wt remove`, never remove a main checkout, never run `wt step prune` in one client repo. Removing an agent: `claude rm <id>` after a confirm; closing a viewer stays `x`.
- Test zellij behaviour in a throwaway session as CLAUDE.md says, never on Alex's live hub. Apply to the live hub only when an item is done, and restart a live pane in place (focus it, `zellij -s hub run --in-place --close-replaced-pane ... -- env -u CLAUDE_JOB_DIR <cmd>`, refocus) — never quit the hub session.
- Edit running scripts write-then-mv. Commit each finished item in this repo (no Claude-Session trailer, no ticket ids); there is no remote.
- Respond in Simplified Technical English. End each item with what changed and how Alex uses it.

Also on record, not accepted yet (do not build unless Alex asks): a tuicr config for the narrow review column (gruvbox-dark, unified, wrap gutter, compact folders), and a revdiff trial with a turn picker that sends review notes to the agent.

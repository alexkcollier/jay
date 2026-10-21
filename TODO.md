# Hub to-do

Continue Alex's hub to-do list. The main checkout (~/Documents/projects/wt-hub) is the live install of his worktree hub (`./install.sh --link`): ~/.local/bin, ~/.local/lib/wt-lib.sh, the yazi keys and the tuicr config are symlinks into it, and ~/mods/wt-hub links to mod/. Read CLAUDE.md and README.md first, and your memory note "worktree-tooling-worktrunk" (decisions, zellij 0.45 facts, incidents). The hub is the zellij session "hub" (layout written by bin/wt-hub): worktree list (fzf, bin/wt-sidebar) | agent viewer (bin/wt-hub-pane agent; opens on the hub Claude, a background agent, since 2026-10-21) | review (tuicr via bin/wt-hub-pane) ⇄ files (yazi).

Alex's to-do list, in his words (2026-10-19):
1. Clean up the tops of the panes — "the stacks are cumbersome/ugly" (zellij stacked-pane title bars in the middle and right columns). Done 2026-10-19: one pane per column, panes in place.
2. Nicer zellij UI — "the current tabs and hints are meh" (tab-bar and status-bar plugins in the hub layout). Done 2026-10-19: one zjstatus bar.
3. Faster pane switching/navigation. Done 2026-10-19: Ctrl g h/l/1/2/3/;, Enter in the list moves the focus, an agent pick focuses the middle column.
4. Keyboard hints in the worktree list, and the ability to remove agents and worktrees from it. Done 2026-10-19: footer, ? for all keys, d removes after a confirm.
5. The agent panel sometimes stops responding to the mouse (added 2026-10-19). Closed 2026-10-20 (Alex): not seen since the clean restart; notes below in case it comes back.

## Item 5 (closed): what we know

- Symptom: in the agent viewer the wheel moves the cursor (zellij sends arrow keys), a drag makes zellij's green selection, and the other panes still take the mouse. Closing the viewer and a new pick do not fix it.
- Not a Claude problem: `claude attach` turns the mouse modes on at start and sends them again every few seconds. Writing `?1000/1002/1003/1006h` straight to the viewer's tty did not help, so zellij ignores mouse mode for that pane.
- Not reproduced in throwaway hubs (fake HOME, real claude through a shim): the wheel works after the first pick, after a retarget, after a list click, and with a real Claude in the suspended hub pane.
- Possible cause, fixed: Ghostty passed an agent's CLAUDE_* env into every tab, and the hub server inherited it (f040335: `wt hub --here` removes CLAUDE*/ANTHROPIC* before zellij starts). After a clean restart Alex said "all seems to be working".
- Next step: wait. If the fault comes back in the clean hub, look at the suspended `zellij:link` plugin pane over the middle column, or at how zellij handles the pane under the suspended hub pane. Record DEC mode changes with a pty recorder (attachrec.py).

## Done after the list (2026-10-19)

- Review pane opens a turn chain on its last turn; `q` in tuicr goes back (the pane starts tuicr again).
- `t` toggles review between turns (the agent's turn chain) and commits (merge-base..HEAD), in tuicr (bin/wt-hub-keys; it left the list on 2026-10-20); the title shows the mode.
- List: `n` new idle agent in the row's worktree, `N` new worktree + idle agent; ▸ marks the shown agent.
- Turn chains are per agent (a bg agent keeps its chain after resume or /clear).
- Turn snapshots: committing agents now get turns (the base stays until the first turn commit).
- Key hints: keys in orange, labels in plain text; short hints grouped, `?` one key per line,
  all under 30 columns. `v`/`e` left the list: `e` in tuicr shows files, `e` in yazi goes back.

## Done 2026-10-20

- Lost viewer pane: a pick opened a viewer in place over the already suspended hub Claude; zellij
  lost that pane, and every later pick went to it. Fixed in wtl_hub_role / wtl_hub_show (a334f58).
- Interactive picks show a note in the middle column; a failed attach keeps its error; the list
  prunes dead agents every 10 minutes (a334f58).
- Background-first (Alex's choice): `c` starts every new session as a background agent and
  attaches the terminal; `b` in the list moves an idle interactive session to the background;
  ← in the hub viewer leaves the agent (it went back to the hub Claude until that was removed).
- List keys act in the list only (Alex: no list key may change review's mode or files): `t` left
  the list. The `?` help has Keys, Panes (Ctrl g moves, Alex: fine to show) and Signs (git signs,
  ▸) under their own headings; signs are not drawn as keys. `r` reloads the agent list (and
  starts it again as the newest version); no `q`.
- No hub Claude (Alex: "i still don't see a point of hub claude"): the middle column is a layout
  pane running `wt-hub-pane agent` that never closes (placeholder; "you left this agent, Enter:
  open it again"); the "◆ hub" row is gone. Nothing opens in place over a suspended pane any
  more except files over review.
- Notices: a click works now (Alex checked; wt-go lacked claude/zellij on launchd's PATH).
  No notice while Ghostty is in front with the agent's own tab or the hub tab selected (the hub
  counts for every agent); the zellij pane does not matter (Alex). macOS stacks them (grouping
  Automatic). Turn chains of gone agents are pruned (claude-turn-snapshot --prune).
- Review: new turns come in by themselves (Alex: turns must come in without manual steps).
  A watcher restarts tuicr when the chain head (commits mode: HEAD) moves, only while tuicr is
  in NORMAL/SELECT. tuicr kept: revdiff (Alex offered a switch) has only a manual reload, no
  per-commit pick, and keys that cannot run commands; its plus is annotations back to Claude.
- Removed (Alex agreed): a scratch worktree turns-selftest, test chains 11112222 and
  60e27a52, bin/wt-hub-edit, the wtl_nvim_* helpers, ~/.config/wt/lazygit-hub.yml.
- Kept as is (Alex): idle background agents stay until removed; the Octicons for uncommitted,
  conflict, safe and rebase.

## Done 2026-10-21

- The hub Claude is back (Alex: "i now see some utility for it"), as a background agent named
  `hub` (Alex picked this over the old pane under the viewer, a floating pane or a pane under
  the list). Its use (Alex): orchestrate agents and answer questions across repos; its system
  prompt says how (`wtl_hub_claude_prompt`). A fresh hub opens on it with the focus in the
  middle column; the "◆ hub" row (top of the list, with its state sign) and `wt go hub` show it
  again; review does not change on that pick. `wtl_hub_claude` starts it when
  `~/.local/state/wt-hub-claude` names no agent. No in-place panes: it uses the agent viewer.

## Other open items

None. Dropped 2026-10-20 (Alex): `wt step prune` (bulk removal; the list's dim ✓ and `d` do it
one worktree at a time). Never run it in the client repo where it would delete `main` (the
memory note "worktree-tooling-worktrunk" names it).

## How to work

- Taste items: first show Alex 2–3 concrete options (short ASCII previews, what each costs), let him pick, then build. Key items: propose the keys in one message, then build. Alex wants idiomatic keys ("q means quit").
- Removing a worktree is destructive: confirm in the UI first, use `wt remove`, never remove a main checkout, never run `wt step prune` (see "Other open items"). Removing an agent: `claude rm <id>` after a confirm. The agent viewer never closes; the hub Claude is a background agent shown in it (since 2026-10-21), never a pane under it.
- Test zellij behaviour in a throwaway session as CLAUDE.md says, never on Alex's live hub. Apply to the live hub only when an item is done, and restart a live pane in place (focus it, `zellij -s hub run --in-place --close-replaced-pane ... -- env -u CLAUDE_JOB_DIR <cmd>`, refocus) — never quit the hub session.
- Edit running scripts write-then-mv. Commit each finished item in this repo (no Claude-Session trailer, no ticket ids); there is no remote.
- Respond in Simplified Technical English. End each item with what changed and how Alex uses it.

Also on record, not accepted yet (do not build unless Alex asks): a tuicr config for the narrow review column (gruvbox-dark, unified, wrap gutter, compact folders), and a revdiff trial with a turn picker that sends review notes to the agent (Alex: a switch to revdiff is fine if tuicr gets in the way).

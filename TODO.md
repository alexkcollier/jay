# Hub to-do

Open items, known faults, and the decisions behind the hub, with the dates they were made. Read
CLAUDE.md and README.md first. The project is jay (called wt-hub until 2026-10-21; the dated
entries below keep the names of their time). The hub is the zellij session "jay" (layout
written by bin/jay): worktree list (fzf, bin/jay-sidebar) | agent viewer (bin/jay-pane agent;
opens on the hub Claude, a background agent, since 2026-10-21) | review (tuicr via
bin/jay-pane) ⇄ files (yazi).

## Open items

- Remove the shims of the old wt-hub names (`compat/`, `lib/wt-lib.sh`, the links at the old
  paths that `install.sh` leaves) and the `WT_` fallbacks of the settings, when no running
  agent's prompt, no config and no habit uses the old names any more. Until then
  `./install.sh --no-compat` removes them on one machine.
- A key that marks a task pane as private, so that `jay run log` refuses to read it (the bar
  would still show its state and ports). Not built; the README notes it.
- Tab control for terminals other than Ghostty.
- The tmux hub (2026-10-22, `JAY_MUX=tmux`, steps 1 and 2 of notes/paradigm.md): Alex's trial
  beside the zellij hub (step 3). To judge on a real screen in Ghostty: the look (border titles,
  the two status lines at the top: banner, then bar), the keys (Ctrl g table; Claude's own
  Ctrl+B, Ctrl+G are free now), the mouse (one click picks; border drag; wheel), fzf's partial
  redraws in the list (the clear on a new row count stays), wide glyphs. Known limits: both
  hubs' lists follow a pick made in either (`jay_list_follow` finds every list's socket); the
  zellij tasks tabs' note counts from the picked worktree, tmux's from each window's own; the
  launcher's popup has a fixed height (a command's output opens a second popup of its size);
  the bar is under the banner at the top (tmux has one status position; zellij's is at the
  bottom). Step 4 (tmux the default) is in: without `JAY_MUX`, the hub that runs, else tmux
  (`jay_which_mux`; docs/install.md, "tmux or zellij"). Then 5 (remove zellij).
- tmux hub, files: no image previews, and yazi 26.9.1 takes 5 s to quit (`q`) and to run the
  first `o` after a start (2026-10-23). jay.conf keeps tmux's passthrough off, so the terminal's
  replies to yazi's queries no longer arrive as keys (`>|ghostty 1.3.2`: `o` opened the editor in
  yazi; text in Claude); yazi's probe then waits for a DA1 reply that never comes. `e` does not
  wait: jay closes the files pane itself (`jay-sidebar --review back`). Yazi's main branch
  (9561890a, 2026-10-18) ends the probe 2 s after the start: with the next yazi release the 5 s
  of `q` and `o` should go. Check it then.
- An agent whose home is gone goes on as a copy with a new id (docs/working.md, "When the folder
  an agent came from goes"): its turn chain starts again, and an old entry whose recorded
  worktree is on disk stays hidden until that worktree goes. Claude has no option to move an
  agent's home, or to remove an entry and keep its recorded worktree. When it gets one: use it
  in `jay_continue_in` / `jay_drop_replaced` (lib/jay-lib.sh), and keep the id.
- On record, not accepted yet (do not build unless the user asks): a tuicr config for the narrow
  review column (gruvbox-dark, unified, wrap gutter, compact folders), and a revdiff trial with
  a turn picker that sends review notes to the agent (a switch to revdiff is fine if tuicr gets
  in the way).
- Ideas from a worker (2026-10-26; it removed its worktree with `wt remove` and could not remove
  itself, which led to `jay rm`), not built yet:
  - `wt remove` (a worktrunk hook, or the hub's own step) offers to remove the worktree's
    background agents too. `jay_remove_agent` (lib/jay-lib.sh) does the stop, `claude rm`, the
    log and jay's cleanup for one agent; an agent in its turn must go after the turn (as `jay rm
    --self` does).
  - A worktree whose PR was squash-merged shows as merged (the dim check sign, `wt list`): its
    branch is not in main's history, so it looks unmerged now.

Done 2026-10-26: scratch worktrees. A worker (ui-audit repo) made three detached worktrees in
its job folder (`~/.claude/jobs/<id>/tmp/base`, `v1`, `v2`) for before/after screenshots; they
showed as loose "(detached)" rows, and git kept their entries after the job went. Now the
prompts of `jay new`, the hub Claude and the orchestrators say to compare in a plain copy
(`git archive | tar -x`), and in a detached worktree only when git must work in it (removed
before the report). `jay rm` (also `--self`) removes the git worktrees under the agent's job
folder and prunes (`jay_remove_scratch`); the list's prune runs `git worktree prune` in the
hub's repos (`jay_prune_worktrees`); the list marks a scratch worktree (dim, "scratch of
<agent>", under the agent's row). The need is legitimate: nothing forbids such a worktree.
Open: `wt remove` of a worktree does not remove the scratch worktrees of its agents (only `jay
rm` does); the list's `d` on a scratch row runs `wt remove` on it like any worktree.

Dropped 2026-10-20: `wt step prune` (bulk removal; the list's dim ✓ and `d` do it one worktree
at a time). Be careful with `wt step prune` in your own repos: in one repo it would have deleted
`main`.

## Known faults

- The agent viewer sometimes stops taking the mouse (item 5 below; closed, not seen since the
  clean restart). If it comes back: quit the hub (Ctrl g, Ctrl q) and run `jay` in a terminal
  that no agent started. Notes: "Item 5 (closed): what we know".
- Tab control is Ghostty only; other terminals get the hub without tab control.
- With bash as `$SHELL`, `jay run stop` of a task takes about 12 s: bash 3.2's `-i +m -c` keeps
  job control, so the command gets a process group of its own and Ctrl-C to the pane's group
  misses it (TERM after 10 s stops it). zsh (`-i +m -c`): 0.3 s. Seen 2026-10-22.
- macOS only: AppleScript, `lsappinfo`, BSD `stat`, `cp -c`.

## The first to-do list (2026-10-19)

1. Clean up the tops of the panes: the zellij stacked-pane title bars in the middle and right
   columns were cumbersome. Done 2026-10-19: one pane per column, panes in place.
2. A nicer zellij UI: the tab bar and status bar plugins in the hub layout. Done 2026-10-19: one
   zjstatus bar.
3. Faster pane switching and navigation. Done 2026-10-19: Ctrl g h/l/1/2/3/;, Enter in the list
   moves the focus, an agent pick focuses the middle column.
4. Keyboard hints in the worktree list, and the removal of agents and worktrees from it. Done
   2026-10-19: footer, ? for all keys, d removes after a confirm.
5. The agent panel sometimes stops responding to the mouse (added 2026-10-19). Closed
   2026-10-20: not seen since the clean restart; notes below in case it comes back.

## Item 5 (closed): what we know

- Symptom: in the agent viewer the wheel moves the cursor (zellij sends arrow keys), a drag makes
  zellij's green selection, and the other panes still take the mouse. Closing the viewer and a
  new pick do not fix it.
- Not a Claude problem: `claude attach` turns the mouse modes on at start and sends them again
  every few seconds. Writing `?1000/1002/1003/1006h` straight to the viewer's tty did not help,
  so zellij ignores mouse mode for that pane.
- Not reproduced in throwaway hubs (fake HOME, real claude through a shim): the wheel works after
  the first pick, after a retarget, after a list click, and with a real Claude in the suspended
  hub pane.
- Possible cause, fixed: Ghostty passed an agent's CLAUDE_* env into every tab, and the hub
  server inherited it (f040335: `wt hub --here` removes CLAUDE*/ANTHROPIC* before zellij
  starts). After a clean restart all worked.
- Next step: wait. If the fault comes back in the clean hub, look at the suspended `zellij:link`
  plugin pane over the middle column, or at how zellij handles the pane under the suspended hub
  pane. Record DEC mode changes with a pty recorder.

## Done after the list (2026-10-19)

- Review pane opens a turn chain on its last turn; `q` in tuicr goes back (the pane starts tuicr
  again).
- `t` toggles review between turns (the agent's turn chain) and commits (merge-base..HEAD), in
  tuicr (bin/wt-hub-keys; it left the list on 2026-10-20); the title shows the mode.
- List: `n` new idle agent in the row's worktree, `N` new worktree + idle agent; ▸ marks the
  shown agent.
- Turn chains are per agent (a bg agent keeps its chain after resume or /clear).
- Turn snapshots: committing agents now get turns (the base stays until the first turn commit).
- Key hints: keys in orange, labels in plain text; short hints grouped, `?` one key per line,
  all under 30 columns. `v`/`e` left the list: `e` in tuicr shows files, `e` in yazi goes back.

## Done 2026-10-20

- Lost viewer pane: a pick opened a viewer in place over the already suspended hub Claude; zellij
  lost that pane, and every later pick went to it. Fixed in wtl_hub_role / wtl_hub_show (a334f58).
- Interactive picks show a note in the middle column; a failed attach keeps its error; the list
  prunes dead agents every 10 minutes (a334f58).
- Background-first: `c` starts every new session as a background agent and attaches the
  terminal; `b` in the list moves an idle interactive session to the background; ← in the hub
  viewer leaves the agent (it went back to the hub Claude until that was removed).
- List keys act in the list only (no list key may change review's mode or files): `t` left the
  list. The `?` help has Keys, Panes (Ctrl g moves) and Signs (git signs, ▸) under their own
  headings; signs are not drawn as keys. `r` reloads the agent list (and starts it again as the
  newest version); no `q`.
- No hub Claude (it had no clear use then): the middle column is a layout pane running
  `wt-hub-pane agent` that never closes (placeholder; "you left this agent, Enter: open it
  again"); the "◆ hub" row is gone. Nothing opens in place over a suspended pane any more except
  files over review.
- Notices: a click works now (wt-go lacked claude/zellij on launchd's PATH). No notice while
  Ghostty is in front with the agent's own tab or the hub tab selected (the hub counts for every
  agent); the zellij pane does not matter. macOS stacks them (grouping Automatic). Turn chains of
  gone agents are pruned (claude-turn-snapshot --prune).
- Review: new turns come in by themselves, without manual steps. A watcher restarts tuicr when
  the chain head (commits mode: HEAD) moves, only while tuicr is in NORMAL/SELECT. tuicr kept:
  revdiff has only a manual reload, no per-commit pick, and keys that cannot run commands; its
  plus is annotations back to Claude.
- Removed: a scratch worktree turns-selftest, test chains 11112222 and 60e27a52,
  bin/wt-hub-edit, the wtl_nvim_* helpers, ~/.config/wt/lazygit-hub.yml.
- Kept as is: idle background agents stay until removed; the Octicons for uncommitted,
  conflict, safe and rebase.

## Done 2026-10-21

- The hub Claude is back, now with a use: a background agent named `hub` (picked over the old
  pane under the viewer, a floating pane or a pane under the list). Its use: orchestrate agents
  and answer questions across repos; its system prompt says how (`wtl_hub_claude_prompt`). A
  fresh hub opens on it with the focus in the middle column; the "◆ hub" row (top of the list,
  with its state sign) and `wt go hub` show it again; review does not change on that pick.
  `wtl_hub_claude` starts it when `~/.local/state/wt-hub-claude` names no agent. No in-place
  panes: it uses the agent viewer.
- Tasks tab for dev servers (dev servers were easy to lose sight of; a team can run a backend
  and several frontends, with ports that overlap across projects). The choices: no repo config,
  no `wt` subcommands (worktrunk is third-party), an embedded terminal that agents can see, an
  overview in the bar, a tiled "tasks" tab (picked over floating panes and a mix), no log files
  (secrets would end up in them), panes readable by default and no private-pane key for now
  (only a README note). Built: `bin/hub-run` (start in a new pane of the tab, ls, log via
  `dump-screen`, wait, stop, restart, port), the tab in the layout, the bar's `pipe_tasks` (sent
  by the list), the SessionStart hook for agents, Ctrl g Tab (`GoToNextTab`: `ToggleTab` does
  nothing in a fresh session, which has no previous tab), a pick from the tasks tab goes back to
  the hub tab, and notices come while the hub shows the tasks tab. Facts: `ps -E` does not show
  the env of pane processes, so panes are matched to their processes by foreground command and
  folder; `new-pane --tab-id` works from outside, also on a hub without a client; bash 3.2
  `read -t` returns 1 on a time-out.
- Tasks tab, round 2 (the footer was not a clear enough sign of being in the hub on the other
  tab; a switch to the tab should land in the worktree folder when the terminal is empty;
  commands run in the task tab did not get a pane of their own). A blue zjstatus banner at the
  top of the tab (picked over a banner + coloured bar, or a coloured bar only). zellij has no
  tab-switch event, so the shells follow the picks: each pick replaces the tab's empty shells in
  place with a shell in the picked worktree, and the list's tick opens a new free shell when a
  command takes the last one. Facts: `new-pane --in-place` without a command ignores `--cwd`
  (with a command it works); `new-pane --tab-id` into the tab a client looks at does not move
  that client's focus. Then the hub tab got the banner too (`◆ HUB › worktrees`). Then (only
  programs and running commands may block a move): every shell at its prompt follows the pick; a
  used one gets Ctrl-C and ` cd -- <worktree>` typed.
- Tasks tabs, round 3 (instead of following, tie the terminal to the worktree): a tasks tab per
  worktree (not per agent: a server runs in a folder), made on first need with `new-tab
  --no-focus`; the follow logic is gone. Ctrl g Tab is a zellij `Run` binding (`hub-run
  --switch` in a 1-cell floating pane that closes at once), because zellij 0.45 has no key
  action for a tab by name; picked over moving the pick's tab to position 2 at each pick (a CLI
  tab switch at each pick). The bar has no tab list; the banners say where you are. `d` on a
  worktree closes its tab. Cost measured: the hub server used 68 MB with 5 plugin panes; a tab
  adds a shell and two zjstatus instances.
- Launcher (a command typed in a tasks shell uses that shell; it must have the completion of
  your shell; no slash command): Ctrl g r runs `hub-run --launcher` in a floating pane: your zsh
  through our ZDOTDIR (it loads your startup files), Enter hands the line to hub-run. Then (keep
  it small and narrow, for simplicity; portable, with a user config if needed, zsh as the
  default): the launcher is 4 rows by 60 %, its title says where; tasks run with `$SHELL -i +m
  -c` (aliases: 2 with -lc, 237 with -i; +m keeps Ctrl-C on the whole command); `WT_TASK_SHELL`
  and `WT_LAUNCHER` settings, with a tested bash 3.2 launcher in the README. Then (commands that
  end at once, like `ls` or `docker:up`, should not make panes): zellij cannot move a process to
  another pane, so `hub-run --launch` starts the task, waits up to 2 s for `pane-<id>.exit`, and
  when it ends, closes its pane and shows its output in the launcher (grown to fit) until a key.
- Consoles (no task panel full of one-line panes; a console per tab was picked over a stack for
  one-liners and an inverted Enter / `&`): the launcher types its line into the tab's console; a
  command that runs on makes the console its task (named from the typed line) and the tick opens
  a new console; a tab keeps its newest console, extras close after 10 minutes at the prompt. A
  quick command's output shows in the launcher (end: the shell has the terminal again, or a new
  prompt on screen; 0.7 s for `ls`). Fault found on the way: macOS `pgrep` leaves out its
  ancestors without `-a`, so inside a hub pane (the list's tick) it did not find the zellij
  server, and every task was "unknown" (no tasks in the bar from the list, no free shells);
  `wtl_hub_role` had the same lookup.
- Hide review (hide and show the review panel easily; "tuck away" was picked over
  close-and-reopen and an overlay peek, with the key Ctrl g v): Ctrl g v hides review (the agent
  viewer gets its width) and shows it again at its old width; Ctrl g 3 and Enter on a worktree
  row show it with the focus. tuicr runs on while hidden; files closes and opens again. Facts
  (zellij 0.45): an embedded floating pane splits the biggest pane (under the agent, not right
  of it); `stack-panes -- <tiled> <floating>` puts the floating pane in the tiled pane's place
  and suspends that one; a floating pane over a suspended one loses it on close; any new floating
  pane shows the hidden ones, and the last one keeps the focus after it closes, so hub-run
  --switch/--launcher and the list's tick hide them again; `hide-floating-panes` from outside
  needs `-t <tab id>`; tuicr survives a 0x0 pane.
- The rename to jay (after a blue jay: a real tree beside the worktrees). One command, `jay`:
  alone it opens the hub, `jay <name>` runs `jay-<name>` (git style); `hub-run` is `jay run`,
  `c` stays as the short name of `jay c`. worktrunk stays for the worktree operations; the hub
  no longer uses its `wt <name>` dispatch. Settings `JAY_*` (the `WT_*` names still work), all
  state under `~/.local/state/jay`, the zellij session `jay`, the mod `/jay` (marketplace `jay`).
  The git refs stay `refs/wt-turns` (a new name would orphan the old chains). Shims under the
  old names in `compat/`, kept for a while (Alex's choice): running agents have prompts with the
  old commands, the old hub runs the old scripts until its restart, and old hooks and pane keys
  call the old names. `install.sh` moves the old folders (a symlink stays at each old path),
  replaces the old hooks and installs the mod again: Claude cannot load an installed mod after
  its plugin name changes ("Plugin wt-hub not found in marketplace wt-hub"). The checkout folder
  keeps its name for now (see docs/install.md, "Move the checkout folder").

## Done 2026-10-22

- Agents whose home is gone. Seen: an agent started in worktree A went into worktree B
  (EnterWorktree), A was removed, and the agent could not wake ("Workspace not trusted. <A>
  could not be resolved on disk"). Probe results (claude 2.1.308, a throwaway repo): Claude
  wakes an agent in its home (state.json cwd); `claude --bg --resume <sid>` without options
  wakes the same agent there and fails the same way; with A back as a git worktree, the same
  command wakes the same id, and it runs in B; with options it starts a copy (new id, home B,
  the conversation is there). EnterWorktree with the path of an existing worktree leaves
  worktreePath empty (the transcript's cwd tells where it is); with a name it makes the
  worktree (worktrunk's hook) and records it. `claude rm` of the old entry tries to delete
  that recorded worktree: it refuses while a session works there, on unpushed commits, and for
  a hook-made one (no WorktreeRemove hook), but a clean, pushed git-made one would go. Chosen:
  `d` on A moves such agents first (copies in B, then A goes), never leaving one that cannot
  wake; the list marks `home gone` / `lost` and a pick repairs; `jay go --repair`. Refusing `d`
  until the agent left B was the other option: it leaves the user no way to keep the agent in B.

## Done 2026-10-23 to 2026-10-26

- Idle agents stop (each running agent is a full Claude Code process): the list stops a
  background agent idle for `JAY_AUTO_STOP` minutes (default 15) that nothing needs; never the
  hub Claude or an orchestrator. A stopped agent is not reachable: SendMessage to it fails and
  the message is lost, so senders run `jay wake X` and send again (the prompts say so).
- The list reloads only when its rows change: a reload at each 4 s tick dropped the keys typed
  during it. The tick makes the rows in the background and compares them with
  `sidebar.<pid>.rows`.
- The agent pane and `jay go` wake a stopped agent that has no transcript (it never got a
  prompt) before `claude attach`, which says "nothing to resume" for it.
- `jay rm`: stop a background agent and delete it (`claude stop`, then `claude rm`), also itself
  (`--self`: a detached process waits for the end of its turn). Refuses the hub Claude,
  orchestrators and a busy agent unless `--force` (Alex kept `--force` for all three), and an
  agent whose recorded worktree is on disk. Probe (claude 2.1.310): `claude rm` stops a running
  agent itself, and keeps one whose recorded worktree is on disk ("kept <id> — its worktree is
  still at ..."), naming unpushed commits or hook-made files.

## How to work

- Taste items: first show the user 2–3 concrete options (short ASCII previews, what each costs),
  let them pick, then build. Key items: propose the keys in one message, then build. Keys must
  be idiomatic ("q means quit").
- Removing a worktree is destructive: confirm in the UI first, use `wt remove`, never remove a
  main checkout, never run `wt step prune` (see "Open items"). Removing an agent: `jay rm
  <id>` (or `claude rm <id>`) after a confirm. The agent viewer never closes; the hub Claude is a background agent
  shown in it (since 2026-10-21), never a pane under it.
- Test zellij behaviour in a throwaway session as CLAUDE.md says, never on the live hub. Apply to
  the live hub only when an item is done, and restart a live pane in place (focus it, `zellij -s
  jay run --in-place --close-replaced-pane ... -- env -u CLAUDE_JOB_DIR <cmd>`, refocus) — never
  quit the hub session.
- Edit running scripts write-then-mv. Commit each finished item (no Claude-Session trailer, no
  ticket ids).
- End each item with what changed and how the user uses it.

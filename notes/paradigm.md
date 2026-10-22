# Is zellij the right base for jay? A study

Date: 2026-10-22. Branch: `paradigm-study`. Versions: zellij 0.45.1, tmux 3.8 (installed with
`brew install tmux` for this study), Ghostty 1.3.2 (tip), Claude Code 2.1.308, macOS 27.

The question: is zellij the best base for jay, or a good one? The evidence: the code
(`bin/jay`, `bin/jay-pane`, `bin/jay-sidebar`, `bin/jay-run`, `lib/jay-lib.sh`), CLAUDE.md,
TODO.md, the git log (130 commits, 2026-10-16 to 2026-10-22), and small spikes in throwaway
sessions (a private tmux socket, a fake HOME, a throwaway zellij session). No spike touched the
live hub. The spike scripts are in `notes/paradigm-spike/`.

## Summary

| Question | Answer |
|---|---|
| 1. What jay needs | 13 jobs. Most are **scripted** jobs (swap a program, cover a pane, move the focus, push to the bar), not jobs a person does with the keys. |
| 2. The cost of zellij | 31 workarounds in the code and CLAUDE.md, in 7 groups. Three faults hurt Alex: the hung server (2026-10-19), the lost viewer pane (2026-10-20) and the dead mouse in the viewer (2026-10-19, cause not found). |
| 3. Alternatives | tmux does all 13 jobs, most of them with one command. WezTerm and kitty replace Ghostty and lose detach (kitty) or maturity (WezTerm). Ghostty alone cannot read a pane or keep a pane alive. A custom TUI or a desktop app is months of work. |
| 4. Spikes | tmux: every job passed. Each call took 5 to 7 ms (zellij: 18 to 21 ms). `claude attach` works in a tmux pane, with mouse modes. |
| 5. Recommendation | **Hybrid, then tmux.** First put a thin mux layer in `lib/jay-lib.sh` (no change of behaviour). Then add a tmux backend behind `JAY_MUX=tmux`, let Alex try it, and make it the default when it holds. Sure: about 70 %. |

In one sentence: zellij is a good multiplexer for a person at the keys, but jay is mostly a
multiplexer driven by scripts, and zellij 0.45's CLI is the weak part of zellij.

## 1. What jay needs from its base

| # | Job | How zellij does it now | Evidence |
|---|---|---|---|
| 1 | Layout: list \| agent \| review, widths in %, the list width kept | A KDL layout written at each fresh start | `bin/jay:116` `write_layout` |
| 2 | Swap the program in a pane (a pick) | The pane runs a loop (`jay-pane <role>`) that follows a target file; a pick kills its child, the loop starts the new one; `rename-pane` sets the title | `bin/jay-pane`, `lib/jay-lib.sh:534` `jay_hub_point`, `:574` `jay_hub_show` |
| 3 | A pane over a pane: files over review | `new-pane --in-place --pane-id <review>`: review is suspended, and comes back when files closes | `lib/jay-lib.sh:835` `jay_hub_show_files` |
| 4 | Hide review and show it again | review becomes a 1x1 floating pane, then the floating panes hide; show: a placeholder pane, `stack-panes`, close, then a resize loop in 5 % steps | `lib/jay-lib.sh:858-970` |
| 5 | Focus from scripts | `move-focus left, left, right` (relative), because `focus-pane-id` from the CLI does not move the client's focus | `lib/jay-lib.sh:551`, `bin/jay-sidebar:200` |
| 6 | Tabs per worktree for tasks | `new-tab --no-focus --layout`, `new-pane --tab-id`, `go-to-tab-by-id` | `bin/jay-run:389` `ensure_tab`, `:411` `cmd_switch` |
| 7 | Read a pane, type into a pane | `dump-screen`, `write-chars` (tuicr's mode, the console's prompt, the last turn) | `bin/jay-pane:87,117`, `bin/jay-keys`, `bin/jay-run:593` |
| 8 | Bar and banner | zjstatus (a WASM plugin, downloaded, sha256 checked, a permission prompt at first start), fed by `zellij pipe` | `bin/jay:70,99`, `bin/jay-sidebar:762,773`, `bin/jay-run:880` |
| 9 | Keys (Ctrl g mode) | The user adds binds to `~/.config/zellij/config.kdl` by hand; a key that runs a script needs a `Run` in a 1-cell floating pane | `install.sh:615` `check_zellij` |
| 10 | Mouse | Clicks, wheel, border drag; a click on an unfocused pane only focuses it | CLAUDE.md, docs/working.md |
| 11 | Detach, attach, survive a terminal close | zellij sessions; `jay` reuses a hub only when it answers, else kills the server | `bin/jay:149,164` |
| 12 | Run inside Ghostty | zellij in a Ghostty tab; the tab is found by the client's process or the title | `lib/jay-lib.sh:152-271` |
| 13 | Notices | `jay-notify` asks zellij which tab is active (the hub tab counts for all agents) | `bin/jay-notify:75` |

Jobs 2 to 9 are calls from scripts. zellij has 23 kinds of CLI calls in the code (`action
rename-pane` 7, `dump-screen` 7, `move-focus` 6, `new-pane` 5, `list-panes` 5, and others).
Only jobs 1, 10 and 11 are mostly "use zellij as it is".

## 2. The cost of zellij

### The workarounds, in groups

A. **Hangs** (4)
1. Every zellij call goes through a 5 s `perl alarm` wrapper (`lib/jay-lib.sh:58`): a server that
   outlives its session hangs every zellij command, also for other sessions.
2. `jay` checks that the hub answers (`list-clients`), else it kills the server and runs
   `delete-session --force`: a resurrected session brings panes that wait for Enter.
3. `kill-session` can hang: tests kill the server process.
4. `zellij -s <a session that is not there>` exits 0: `jay run` checks the list first.

B. **Suspended and lost panes** (8)
5. `new-pane --in-place` over a suspended pane makes a lost pane: not listed, not shown, its
   program runs on and takes every pick. `jay_hub_role` finds and kills lost panes
   (`lib/jay-lib.sh:454`).
6. A chained `--close-replaced-pane` over an in-place pane loses the suspended pane.
7. `rename-pane` does nothing on a suspended pane: review gets its title from a delayed
   background job after files closes (`bin/jay-pane`, end).
8. `jay_hub_wait_shown`: wait until review is not suspended before files opens.
9. A rule: never replace a suspended pane in place on the live hub.
10. `pane_command` can be null: panes are found by title, column or `terminal_command`, and each
    `jay-pane` writes its pane id and pid to a file.
11. Pane ids start at 0 in each new server: task records carry the server's pid
    (`bin/jay-run:271`).
12. `run --in-place`, `--no-focus`, `--near-current-pane` from outside make invisible panes.

C. **Focus** (4)
13. `focus-pane-id` from the CLI sets a separate CLI focus: the scripts use relative
    `move-focus` steps and must know where the focus is.
14. `focus-pane-id` exits 2 when the pane has the focus already.
15. `focus-pane-id` on a suspended pane makes it float.
16. A click on an unfocused pane only focuses it: two clicks to pick.

D. **Keys** (4)
17. No key action for a tab by name: `Ctrl g Tab`, `v` and `3` are `Run` binds in a 1-cell
    floating pane, and the script waits until that pane is gone before it acts
    (`bin/jay-sidebar:215`, `jay_hub_wait_gone`).
18. A new floating pane shows the hidden floating panes (the hidden review):
    `jay_hub_keep_hidden` and `jay_hub_rehide` hide them again.
19. `ToggleTab` does nothing in a fresh session: `GoToNextTab`.
20. The keys live in the user's own `config.kdl`; `install.sh` can only print them.

E. **Layout** (5)
21. A tiled pane cannot be hidden: the 1x1 floating pane, the placeholder, `stack-panes` and a
    resize loop in 5 % steps (about 110 lines, `lib/jay-lib.sh:858-970`).
22. An embedded floating pane goes under the biggest pane, not where it was.
23. `hide-floating-panes` from outside needs `-t <tab>`.
24. `override-layout` does nothing from outside and adds panes from inside.
25. A held (exited) command pane cannot run again: close it and open a new one.

F. **Events and the bar** (3)
26. No tab-switch event: the banner gets the worktree at each pick, through a pipe.
27. zjstatus: a download, a pinned sha256, and a permission prompt in the bar at the first
    start. Never write `permissions.kdl`.
28. `new-pane --in-place` without a command ignores `--cwd`.

G. **Screen** (3)
29. Wide (East Asian W) glyphs shift lines: none in the list.
30. fzf partial redraws leave old cells: the list clears the screen when the row count changes.
31. Tests: a screen under 20 rows drops new panes; the About pane takes the focus without
    `show_startup_tips false`.

Not counted: things that a tmux base needs too (strip `CLAUDE*` from the server's env, the hub
lock, `jay-keys` in front of tuicr, `pgrep -a`).

### The faults that hurt Alex

| Date | Fault | What it cost | Status |
|---|---|---|---|
| 2026-10-16 | First trial of the zellij hub: "not super convinced"; stack title bars "cumbersome", the bars "meh" | Items 1 and 2 of the first to-do list | Fixed (one pane per column, zjstatus) |
| 2026-10-19 11:25 | The hub's server outlived the session. Every zellij command hung, also in other sessions | A dead hub; the timeout wrapper; the kill-and-start-fresh logic in `jay` | Worked around (A1, A2) |
| 2026-10-19 | The mouse stopped in the agent viewer, twice. zellij ignored the pane's mouse mode | Hours of tests; not reproduced | Open. Not seen since a clean restart (TODO.md, item 5) |
| 2026-10-19 | "The hub adds a new panel instead of changing it out" | The pane-loop design (`jay-pane`) | Fixed |
| 2026-10-20 morning | A lost viewer pane (in place over a suspended pane) took every pick | a334f58, the lost-pane check | Fixed (B5) |
| 2026-10-21 | Ctrl g Tab, hide review | The 1-cell pane trick, 110 lines of hide/show | Works |

The pattern: zellij is fast enough (about 19 ms a call), but its state is hidden (suspended,
floating, CLI focus), and its CLI acts on that state in ways that the docs do not say. Each
new feature found a new trap, and each trap became a line in CLAUDE.md.

## 3. Alternatives

The same 13 jobs. ✓ one command or a setting; ~ possible with work; ✗ not possible.

| Job | zellij 0.45 | tmux 3.8 | WezTerm | kitty | Ghostty alone | Custom TUI | Desktop app |
|---|---|---|---|---|---|---|---|
| 1 Layout | ✓ KDL | ✓ `split-window -l` | ✓ Lua, `cli split-pane` | ✓ layouts | ~ `split` (no size) | ✓ own | ✓ own |
| 2 Swap program | ~ pane loop | ✓ `respawn-pane -k` (same id) | ~ kill + split | ~ close + launch | ~ close + split | ✓ | ✓ |
| 3 Pane over pane | ~ suspended (traps) | ✓ `swap-pane` with a hidden window | ~ `move-pane-to-new-tab` | ~ stack layout | ✗ | ✓ | ✓ |
| 4 Hide review | ~ 110 lines | ✓ `break-pane` / `join-pane -l` | ~ zoom | ✓ stack layout | ~ zoom | ✓ | ✓ |
| 5 Focus from scripts | ~ relative moves | ✓ `select-pane -t` | ✓ `activate-pane` | ✓ `focus-window` | ✓ `focus` | ✓ | ✓ |
| 6 Tabs by name | ~ no key action | ✓ `select-window -t :=name` | ✓ | ✓ | ✓ tabs | ✓ | ✓ |
| 7 Read / type a pane | ✓ | ✓ `capture-pane`, `send-keys -l` | ✓ `get-text`, `send-text` | ✓ `get-text`, `send-text` | ~ type only, no read | ✓ | ✓ |
| 8 Bar, banner | ~ plugin | ✓ status line, user options | ✓ Lua status | ✓ Python tab bar | ✗ | ✓ | ✓ rich |
| 9 Keys run scripts | ~ 1-cell pane | ✓ key tables, `run-shell -b` | ✓ Lua callbacks | ✓ `launch`, kittens | ~ macOS only | ✓ | ✓ |
| 10 Mouse | ✓ (2 clicks) | ✓ (1 click) | ✓ | ✓ | ✓ | ~ own work | ✓ |
| 11 Detach, survive close | ✓ | ✓ | ~ mux server | ✗ | ✗ | ✗ without a daemon | ✗ without a daemon |
| 12 Inside Ghostty | ✓ | ✓ | ✗ replaces it | ✗ replaces it | ✓ it is Ghostty | ✓ | ✗ own window |
| 13 Events | ✗ no tab event | ✓ hooks, control mode | ✓ Lua events | ✓ watchers | ✗ | ✓ | ✓ |

### tmux

- Easier: every scripted job is one command on a stable id (`%3`). No suspended or lost panes:
  every pane is in a window and `list-panes -a` lists it. `select-pane` moves the real focus.
  `join-pane -l 70` gives an exact width (no 5 % steps). `#{pane_current_command}`,
  `#{pane_current_path}`, `#{pane_dead_status}`, `remain-on-exit` and `respawn-pane` give the
  task logic what `jay run` now gets from `ps` and exit files. Hooks and control mode give the
  events zellij lacks (a window switch). The bar needs no plugin, no download and no
  permission prompt. jay can run its own server (`tmux -L jay -f <jay's conf>`): its keys ship
  with jay, and the user's own `config.kdl` or `.tmux.conf` does not matter.
- Harder: the look. Pane titles are border titles (`pane-border-status top`), not frames; no
  rounded corners. One status position (top or bottom, up to 5 lines): the banner and the bar
  both go there, or the banner is a 1-row pane as now. Claude Code's Ctrl+B is tmux's default
  prefix (jay's server sets no prefix, only Ctrl g). Shift+Enter in Claude needs
  `extended-keys on` (to check with Alex's keys). Copy mode differs from zellij's.
- jay loses: zellij's frames and its floating-pane look; the launcher becomes a `display-popup`
  (it is better at this: a popup needs no pane and goes away by itself).
- Migration: the zellij calls are in `lib/jay-lib.sh` (55), `bin/jay-run` (34), `bin/jay` (20,
  the layout), `bin/jay-sidebar` (9), `bin/jay-open`, `bin/jay-go`, `bin/jay-notify`,
  `bin/jay-pane`, `bin/jay-lazygit`, `bin/jay-keys` (14 together), `install.sh` (zjstatus, the
  printed keys), the test stubs (`tests/lib.sh`) and 39 lines of docs. The hide/show code
  (110 lines) and the lost-pane code mostly go away.
- Risks: tmux has its own traps that this study did not hit (`set-titles`, terminal features,
  passthrough). A user who runs tmux already: a separate socket keeps the two apart.
- macOS: very mature (since 2007, Homebrew, used by iTerm2's control mode). Claude Code's own
  `--tmux` flag (`claude --worktree --tmux`) and its agent-team split panes use tmux; claude-squad
  needs tmux.

### WezTerm

- Easier: one program for terminal and multiplexer; Lua config and events; a full CLI.
- Harder: jay must replace Ghostty, and its Ghostty tab logic goes (lib, about 120 lines). No
  "respawn": a new program is a new pane with a new id. Detach needs the mux server and
  `wezterm connect`.
- Risks: the last stable release is from 2024-02 (nightlies since); one main maintainer.
- Verdict: not better than tmux for jay, and it takes Ghostty away.

### kitty

- Easier: a rich remote control (`kitten @ launch`, `focus-window`, `get-text`), layouts with a
  stack (hide review), Python watchers for events, keys that run kittens.
- Harder: no server, so no detach. When the window closes, the list, review and the **dev
  servers in the tasks tabs** die (the agents live on: they are `claude --bg`). It replaces
  Ghostty.
- Verdict: no. Job 11 is a hard need (tasks must outlive the terminal).

### Ghostty alone

- What its AppleScript can do now (sdef of 1.3.2): windows, tabs, terminals (splits), `split`
  with a direction and a surface configuration (command, cwd, env), `focus`, `input text`,
  `send key`, mouse events, `perform action` (keybind actions), `close`.
- What it cannot do: read a pane's text, set a size on a split, run a script from a key, show a
  bar, send events, keep panes alive after the window closes. Each call takes about 110 ms
  (measured: `count windows`). The maintainers expect breaking changes in 1.4.
- Verdict: no, for now. Good for what jay uses it for (find and select the hub's tab).

### A custom TUI that hosts terminals

- For example Rust (ratatui with `tui-term`/vt100, `alacritty_terminal` or `libghostty-vt`), or
  Python Textual with a terminal widget.
- Easier: full control. The list is real UI, not fzf; no focus tricks; one process knows all.
- Harder: jay becomes a terminal emulator inside a terminal. Claude Code's screen uses the
  alternate screen, mouse modes, synchronized output, the kitty keyboard protocol and true
  colour: each must work. The wide-glyph and mouse-mode faults of zellij become jay's own
  faults. Detach needs a daemon and a client protocol (or tmux under it).
- Cost: months, and a new language for the repo (now bash, jq, a little Python).
- Verdict: no. The Textual terminal widgets are not mature; the Rust path is a product, not a
  hub.

### A desktop or web app (Tauri or Electron with xterm.js)

- Easier: a real agent dashboard, a rich diff view, native notices, clicks everywhere. xterm.js
  is mature (VS Code uses it).
- Harder: the PTYs live in the app, so a quit kills the tasks, unless a daemon (or tmux, with
  control mode) holds them. The keyboard-first flow in Ghostty goes. A new stack (TypeScript,
  Rust or Node) and a build and signing chain.
- What exists: Claude Code's own desktop and web apps show sessions and diffs; Conductor and
  similar apps run agents in worktrees. jay's place is the terminal: worktrunk, tuicr, yazi,
  fzf, Ghostty.
- Verdict: not now. If it comes later, tmux is a good base under it: an app can attach to
  jay's tmux server in control mode, as iTerm2 does.

## 4. Spikes

All on a private tmux socket (`-L jayspike`, `TMUX_TMPDIR` in the job's temp folder), a fake
HOME and a clean env; a pty client attached at 200x50 where a client was needed. The server was
killed at the end. Test programs log their size, SIGWINCH and input. Script:
`notes/paradigm-spike/tmux_spike.py`.

| Test | Command | Time | Result |
|---|---|---|---|
| T1 Three columns | `new-session -x 200 -y 50`, `split-window -h -l 78%`, `split-window -h -l 45%`, `select-pane -T` | 48 ms all | ✓ 43 \| 85 \| 70 columns, titles on the borders |
| T2 Swap the middle program | `respawn-pane -k -t %1 <cmd>` | 6 ms | ✓ same pane id, new program |
| T3 Files over review and back | `new-window -d` (files), `swap-pane -d` ×2, `kill-pane` | 13 ms, 11 ms back | ✓ review runs on in the hidden window. Two faults: the swapped-in pane's title is the host name until set; review gets SIGWINCH to 200 columns while hidden (one extra redraw of tuicr) |
| T4 Focus from outside | `select-pane -t %1` from a script | 7 ms | ✓ the client's pane is `%1`; one active pane; the `pane-focus-in` hook ran |
| T5 Bar fed by a script | `set -g @agents '…'` + `refresh-client -S` | 23 ms | ✓ the client shows it; no plugin |
| T6 A key runs a script | `bind -n C-g switch-client -T jay`; `bind -T jay Tab run-shell -b …` | 13 ms key to script | ✓ no pane made (3 before, 3 after) |
| T7 Hide review, show it | `break-pane -d`; `join-pane -d -h -l 35% -s %2 -t %1` | 5 ms, 6 ms | ✓ the middle takes the width. Fault: `-l 35%` is a share of the target pane, not of the window: give columns (`-l 70`) |
| T8 Tab by name from a key | `bind -T jay t select-window -t :=tasks` | — | ✓ and the `session-window-changed` hook ran |
| T9 Click on an unfocused pane | SGR click at the middle pane | — | ✓ focus moves **and** the program gets the click (zellij: focus only) |
| T10 Control mode | `tmux -C attach` | — | ✓ `%window-pane-changed`, `%session-window-changed`, `%output` |
| T11 Read, type, list | `capture-pane -p`, `send-keys -l`, `list-panes -a` | 5 ms each | ✓ |
| T12 Wide glyph | `✋x\|` in a pane, `capture-pane` | — | ✓ captured; not checked on a real screen |
| T13 Detach | `Ctrl b d` | — | ✓ 0 clients, all panes run on |

The same calls on a throwaway zellij session (`notes/paradigm-spike/zellij_timing.sh`):
`list-panes` 19 to 21 ms, `rename-pane` 19, `move-focus` 19, `dump-screen` 19, `write-chars` 18,
`list-tabs` 19, `pipe` 19, `new-pane --in-place` 19. Speed is not the problem with zellij; both
are fast.

`claude attach` in a tmux pane: one idle background agent (no prompt) in this worktree, all
`CLAUDE*`/`ANTHROPIC*` variables unset, attached in a tmux pane at 160x45. After 6 s:
`mouse_any=1 sgr=1 alt=1`, the full Claude screen, typed text in its input box, Ctrl-U cleared
it. The agent was removed after the test (`claude rm`).

Not tested: Shift+Enter and the kitty keyboard protocol through tmux in Ghostty; tmux on a real
screen in Ghostty (look, wide glyphs, border drag); fzf's partial redraws in tmux; the dead
mouse fault (item 5), which zellij caused and tmux may not have.

## 5. Recommendation

**Hybrid now, tmux next.** Keep the zellij hub running. Put a thin mux layer between the
scripts and zellij. Build a tmux backend behind it, and switch when Alex likes it.

Why not stay on zellij only: the cost is not one fault, it is the trend. 31 workarounds in
about a week, three of them after real faults on the live hub. The next features (more tabs,
more overlays, events) go through the same weak CLI: suspended panes, a CLI focus that is not
the client's, no tab key action, no events. This study did not find a zellij release that
fixes these.

Why not a big move: the hub works today, and Alex uses it. A layer makes the move small and
lets it stop at any step.

Why tmux and not the others: it does all 13 jobs (the spikes show jobs 1 to 11; tmux in a
Ghostty tab and the active-window check for notices were not tested), it keeps Ghostty and detach, it is the base that Claude Code itself uses for split
panes, and it can later carry a desktop or web front through control mode.

### Steps

1. **Mux layer, zellij only** (no behaviour change). In `lib/jay-lib.sh`, about 15 functions:
   `jay_mux_alive`, `jay_mux_kill`, `jay_mux_panes` (JSON: id, tab, title, x, width, command,
   cwd, focused, floating), `jay_mux_respawn <pane> <cmd>`, `jay_mux_rename`, `jay_mux_read`,
   `jay_mux_type`, `jay_mux_focus <role>` (by role, not by moves), `jay_mux_cover <pane> <cmd>`
   and `jay_mux_uncover` (files over review), `jay_mux_hide` / `jay_mux_unhide` (review),
   `jay_mux_tab_new`, `jay_mux_tab_go`, `jay_mux_bar <key> <text>`. Move every `zellij` call in
   `bin/` behind them. `tests/run.sh` must pass unchanged. About a day.
2. **tmux backend** behind `JAY_MUX=tmux`: `bin/jay` starts `tmux -L jay -f
   ~/.local/share/jay/tmux.conf` with the three columns, the tasks windows and the status line;
   `config/tmux/jay.conf` ships the Ctrl g key table (no edits to the user's config).
   `jay_mux_cover` is `swap-pane` with a hidden window; hide is `break-pane` / `join-pane`;
   the launcher is `display-popup`. Tests: a tmux stub next to the zellij stub. Two to three
   days.
3. **Trial**: Alex runs `JAY_MUX=tmux jay` beside the zellij hub (another session name). Check
   the open points: the look, Shift+Enter in Claude, the mouse, fzf redraws, notices.
4. **Switch the default** when the trial holds. Keep zellij as `JAY_MUX=zellij` for a while,
   as with the `wt-hub` shims.
5. **Remove** the zellij backend, zjstatus and the zellij facts in CLAUDE.md, when nothing uses
   them.

Step 1 has value alone: it puts the zellij traps in one file, and the scripts say what they
want ("focus the agent") and not how ("left, left, right").

### How sure

About 70 %. Sure on the scripting side: the spikes show each job as one plain command, on a
real tmux, with no traps found. Less sure on two things that only Alex can judge: the look
(tmux borders against zellij frames and zjstatus) and the feel of Claude in tmux in Ghostty
(keys, mouse, scroll). Those are the points of step 3, and the layer means a "no" there costs
only step 2.

What would change this: a zellij release that adds a tab-by-name key action, a CLI focus that
moves the client, a way to hide a tiled pane and a tab-switch event. Then stay on zellij and
keep the layer.

## How to repeat the tests

```sh
mkdir -p "$TMP/spike/home/.config/zellij" "$TMP/spike/sock"
cp notes/paradigm-spike/* "$TMP/spike/"
env -i PATH=/usr/bin:/bin HOME="$TMP/spike/home" /usr/bin/python3 -I "$TMP/spike/tmux_spike.py"
/bin/bash "$TMP/spike/zellij_timing.sh"     # a throwaway zellij session; kills its server
```

`$TMP` is a temp folder of your own. `tmux_spike.py` runs `/opt/homebrew/bin/tmux` (Homebrew
on Apple silicon); change `TMUX` at its top for another path. Both scripts use their own socket or session name and
never touch the session `jay`.

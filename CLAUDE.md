# CLAUDE.md

jay: a shareable worktree and agent hub (see README.md and docs/); `install.sh` installs it.
It was called wt-hub: `compat/` holds shims under the old names, and `lib/wt-lib.sh` is a shim
of `lib/jay-lib.sh` (functions `jay_*`). For work on the hub itself, `./install.sh --link`
makes the main checkout the live install: the scripts, the yazi keys, the lazygit settings and
the tuicr config are symlinks into it, so an edit is live at once.
`~/.config/worktrunk/config.toml` and `~/.claude/settings.json` are never links.

The checkout folder can still be named `wt-hub` (the live install links into it, and agents
run there). To move it later, by hand: quit the hub, `mv` the folder, `git worktree repair` in
it, `./install.sh --link`, then `jay` (see docs/install.md, "Move the checkout folder").

Facts about your own machine (where the live install is, how your mod loads) go in
`CLAUDE.local.md` in the repo root. Git ignores `*.local.md`, and Claude Code loads
`CLAUDE.local.md` with this file. Open items, known faults and past decisions: `TODO.md`.

## Tests

- Shell part: `tests/run.sh` (bash 3.2, no network; a fake HOME, stubs for claude and zellij).
  `tests/run.sh <name>` runs the test files whose name has `<name>`.
- A throwaway tmux hub in a pty (about a minute): `tests/run.sh smoke` (`tests/smoke-tmux.sh`).
- Mod: see "Mod" below.

## Rules

- Scripts reach the hub's multiplexer only through the mux layer: `jay_mux_*` in
  `lib/jay-mux-<backend>.sh` (the API is listed in `lib/jay-lib.sh`, "The mux layer";
  `jay-mux <name>` from outside bash). zellij calls for the user's own sessions (`jay open`,
  interactive agents in `jay go`) are not the hub's and stay in `lib/jay-lib.sh`.

- No client names in this repo (client folders, repos, remotes, people), also not in examples,
  tests or notes: use made-up names (`acme`, `shop`). Client settings go in `~`-level config,
  for worktrunk in `~/.config/worktrunk/config.toml`.
- No machine-specific paths in the repo: the scripts use `$HOME/.local/...` (the install
  prefix) and find other tools on PATH.
- A new script in `bin/`: with a `--link` install, run `./install.sh --link` again for its link.
  A new tool, config or hook the hub needs goes into `install.sh` (and `docs/install.md`) too.
- Test `install.sh` with a fake `HOME` (`HOME=<tmp> ./install.sh`), never against the real
  `~/.claude/settings.json`; `--check` is safe anywhere.
- Edit with the Edit/Write tools (so `/diff` tracks changes), never python/sed via Bash.
- A script that is running (`jay-sidebar`, `jay-pane`) must be replaced write-then-mv: edit a
  copy, then `mv` it over the file. Bash reads a running script lazily.
- macOS `/bin/bash` is 3.2: empty arrays under `set -u` need `${arr[@]+...}`.
- No wide (East Asian W) glyphs in sidebar rows: they shift lines in zellij.
- Test zellij actions in a throwaway session, never the live hub (the session `jay`; it is
  `hub` until Alex restarts the hub after the rename, so leave both alone):
  `env -u CLAUDE_JOB_DIR zellij attach --create-background <name> options --default-layout <kdl>`,
  drive it with a pty client from `python3 -I` (`pty.fork`, SGR mouse sequences for clicks and
  drags; focus by a click or `move-focus`), and stop it by killing its server process
  (`pkill -9 -f 'zellij --server .*/<name>$'`) — `kill-session` can hang. Use a screen of at least
  20 rows. Tests of the list need the fake HOME's `bin` first on PATH (fzf binds call `jay-sidebar`).
  Give the fake HOME a `.config/zellij/config.kdl` with `show_startup_tips false` and
  `show_release_notes false`: else a floating About pane takes the focus and `close-pane` acts
  on the wrong pane. A test pane that runs hub scripts needs `JAY_SESSION=<name>` exported,
  and the test commands need the agent's own `ZELLIJ*` variables unset: `lib/jay-lib.sh` uses
  `jay` when `JAY_SESSION` (and the old `WT_HUB_SESSION`) is empty, so a `jay-sidebar --files`
  from a test acts on the live hub.
- Test the tmux hub on a socket of its own, never tmux's default server or the socket `jay`:
  `JAY_MUX=tmux JAY_TMUX_SOCKET=<test name> TMUX_TMPDIR=<tmp>` (as `tests/smoke-tmux.sh`), with
  `TMUX`/`TMUX_PANE` unset; end it with `tmux -L <test name> kill-server`. Keep the fake HOME
  short (`/tmp`): fzf's `--listen` socket and tmux's socket fail over 104 bytes of path.
- Starting a pane in the live hub from an agent: strip `CLAUDE*`/`ANTHROPIC*` env vars. The hub
  server must not inherit them either (`jay --here` removes them before zellij starts).
- Never replace a suspended pane in place on the live hub; wait until it is visible.
- Never write zellij's `permissions.kdl` yourself; a plugin asks for its permissions in the pane.
- Bash: `if …; fi >file` truncates the file before the condition reads it.
- Bash 3.2: `IFS=$'\t' read … < <(f)` runs `f` with that IFS, so `$(…)` lists in `f` do not split
  on newlines. Set `local IFS=$' \t\n'` in such functions.
- Claude: `claude attach` turns into the agent view (`claude agents`, same process) on ←.
  `claude rm` keeps an agent while its recorded worktree is on disk (no WorktreeRemove hook
  here) or has unpushed work; its transcript stays. `claude --bg --resume <session-id>` continues
  an ended interactive session in the background with the same ids.
- Claude: `/clear` in a background session keeps its `--append-system-prompt` (respawnFlags),
  name, short id and process; only the session id changes. All `claude attach` clients of a
  session share one input box (Ctrl+U clears a line of a draft), and the session's screen takes
  the size of the client that joined last, also after that client leaves (`bin/jay-clear`).
- Claude: `claude respawn <id>` (2.1.308, tested on one version) restarts a background agent on
  the installed binary in ~1 s: same id, name, session id, conversation, respawnFlags, cwd and
  entered worktree; new pid and startedAt; a `claude attach` client stays. It ends a running
  turn for good (the agent then waits like a new one: needs "send a prompt to start"), kills its
  Monitors, drops the notify_when_idle subscriptions it holds; crons, a ScheduleWakeup and
  background Bash processes stay. With its state.json cwd gone it fails ("could not be resolved
  on disk") and the old process runs on. state.json cliVersion changes only at the next turn
  (also after an attach wakes a retired agent): the running binary is the path after `--` in the
  parent `claude bg-pty-host` process. The daemon starts every worker from its own binary.
- Claude: a notify_when_idle subscription to an idle session fires at once.
- Claude: ← in `claude attach` execs the same pid as `claude agents` (its args change; SIGTERM
  ends it). From that view Enter attaches the chosen agent. `claude --bg --resume <session-id>
  --name x` of an ended session took the same ids (no copy) and wrote the new title into that
  session's transcript: never use an old session of the user as a probe.
- Test Claude sessions in a pty with every CLAUDE*/ANTHROPIC* variable unset: an inherited
  `CLAUDE_CODE_CHILD_SESSION` turns off the transcript and hides the session from `claude agents`.
- A test that starts Claude sessions removes them at the end (`claude rm <id>`): without the
  CLAUDE* variables, such a session shows in the user's hub list. Only `jay new` workers stay.
- Mod: `cd mod && claude plugin test . && claude plugin validate .`; it loads from its folder,
  edits apply at the next session start or `/reload-plugins`.
- Commits: no Claude-Session trailer, no ticket ids.

## zellij 0.45 facts

- `list-panes -a -j -c`: `pane_command` is the running program and can be null — find panes by
  title or column (`pane_x`), not by command.
- `run --in-place --close-replaced-pane` replaces the focused pane; plain `run` splits it;
  `run --no-focus` / `--near-current-pane` from outside make invisible panes.
- `focus-pane-id` exits 2 when the pane is already focused. From the CLI it does not move a real
  client's focus: it sets a separate CLI focus (then `list-panes` shows two focused panes).
  `move-focus` moves the real client. On a suspended pane it makes the pane float.
- `action new-pane --in-place --pane-id X` works from outside; closing that pane brings back the
  suspended one, but a chained `--close-replaced-pane` over it loses the suspended pane.
- `new-pane --in-place --pane-id X` on a suspended X makes a lost pane: `list-panes` does not
  show it and nobody sees it, but its program runs on. Closing the shown pane over X still
  brings X back.
- `rename-pane` does nothing on a suspended pane.
- `override-layout` does nothing from outside the session and adds panes from inside it; do not
  use it on the live hub.
- A click on an unfocused pane only focuses it; the program does not get that click.
- A held (exited) command pane cannot be re-run from outside; close it and open a new one.
- A server can outlive its session after a quit and hang every zellij command; all calls in
  `lib/jay-lib.sh` go through a 5 s timeout wrapper, and `jay` kills such a server.

## tmux facts (3.8, from the tests of the tmux hub)

- `select-pane -T <title>` only sets the title; it does not make the pane active. A separate
  `select-pane -t <pane>` does, and from the CLI it moves the client's real focus.
- Targets: `=jay:hub.1` works; `=jay:=hub` does not. A window name with `.` or `:`
  (`shop/release-1.2`) breaks a target by name: go by window id (`@5`).
- `display -p -t =jay '<fmt>'` prints nothing while a client is attached; `-t =jay:` (with the
  colon) or a pane id works. In zsh, quote `=jay`: `=word` is zsh's command expansion.
- `#{pane_start_command}` quotes args with spaces (`jay-run --exec "pnpm dev"`); a pane made
  without a command has an empty one. `#{pane_current_command}` is only the program's name
  (`claude`, `bash`), not its args: look at the process under `#{pane_pid}` (`ps`, `pgrep -P`).
  The pane processes are children of the server (`#{pid}`), started directly when the command
  is given as several args.
- `swap-pane -d` with a pane in a hidden window (`new-window -d`) puts a pane over another; the
  covered one runs on there (it gets SIGWINCH to the hidden window's size). `break-pane -d` /
  `join-pane -d -h -l <columns>` hide and show review; `-l N%` is a share of the target pane, not
  of the window. Pane ids stay.
- `send-keys -l` sends control characters too (`\x05\x15 line\r` types a line with Enter).
- A key table (`bind -n C-g switch-client -T jay`) acts once and goes back; `run-shell -b` runs a
  script without a pane. `display-popup -E -e VAR=1` sets a variable in the popup; a popup has
  no pane of its own (its `TMUX_PANE` is the pane under it: `jay_mux_self` ignores it there).
  The popup's `-T` title is a format. A client has one popup at a time: a new `display-popup`
  replaces the open one, and the old one's command ending then closes the new one. To follow a
  popup with another (the launcher's output), the first one runs `run-shell -b "sleep 0.3;
  tmux display-popup -c <client> …"` and ends; `display -p '#{client_name}'` in a popup gives
  its client.
- `set-titles-string '#S | #{pane_title}'` (zellij's title format): tmux sends a new title
  (OSC 2) when the focus moves and when the focused pane is renamed.
- One status position only (top or bottom) for all status lines: the banner and the bar are
  both at the top, not banner top and bar bottom as in zellij.
- User options carry the bar: `set -g @jay_tasks '#[fg=...]text'` (styles in the value work; `#`
  must be doubled), `set -w -t @5 @jay_note …` for one window; the status line reads pane, then
  window, then global options.
- `extended-keys on` with `terminal-features …:extkeys`: `claude attach` in a pane asks for
  mode 2 (`#{pane_key_mode}` = `Ext 2`); Shift+Enter from the terminal as CSI u (`\e[13;2u`) or
  xterm's `\e[27;2;13~` reaches Claude as a new line. `claude attach` turns on the mouse modes
  (`mouse_any_flag`, `mouse_sgr_flag`) and the other screen.
- A click on an unfocused pane focuses it and reaches the program (one click picks in the list).
- Under `set -e` (`jay`, `jay go`), a process substitution inherits errexit: any failing command
  in it (a `kill` of a child that just ended, `x=$(cat <missing file>)`) ends it silently.
- `new-session` checks the client's `TERM`: `xterm-ghostty` needs Ghostty's `TERMINFO` (set in
  Ghostty's tabs, not in `env -i`).

# CLAUDE.md

Alex's personal hub tooling (see README.md). Machine-only: the files here are the live install —
`~/.local/bin`, `~/.local/lib`, `~/mods/wt-hub` and the configs are symlinks into this repo, so an
edit is live at once.

## Rules

- Edit with the Edit/Write tools (so `/diff` tracks changes), never python/sed via Bash.
- A script that is running (`wt-sidebar`, `wt-hub-pane`) must be replaced write-then-mv: edit a
  copy, then `mv` it over the file. Bash reads a running script lazily.
- macOS `/bin/bash` is 3.2: empty arrays under `set -u` need `${arr[@]+...}`.
- No wide (East Asian W) glyphs in sidebar rows: they shift lines in zellij.
- Test zellij actions in a throwaway session, never Alex's live `hub`:
  `env -u CLAUDE_JOB_DIR zellij attach --create-background <name> options --default-layout <kdl>`,
  drive it with a pty client from `python3 -I` (`pty.fork`, SGR mouse sequences for clicks and
  drags; focus by a click, CLI `focus-pane-id` may move another client), and stop it by killing
  its server process (`pkill -9 -f 'zellij --server .*/<name>$'`) — `kill-session` can hang.
- Starting a pane in the live hub from an agent: strip `CLAUDE*`/`ANTHROPIC*` env vars.
- Mod: `cd mod && claude plugin test . && claude plugin validate .`; it loads from its folder,
  edits apply at the next session start or `/reload-plugins`.
- Commits: no Claude-Session trailer, no ticket ids.

## zellij 0.45 facts

- `list-panes -a -j -c`: `pane_command` is the running program and can be null — find panes by
  title or column (`pane_x`), not by command.
- `run --in-place --close-replaced-pane` replaces the focused pane; plain `run` splits it;
  `run --no-focus` / `--near-current-pane` from outside make invisible panes.
- `focus-pane-id` exits 2 when the pane is already focused.
- A held (exited) command pane cannot be re-run from outside; close it and open a new one.
- A server can outlive its session after a quit and hang every zellij command; all calls in
  `lib/wt-lib.sh` go through a 5 s timeout wrapper, and `wt hub` kills such a server.

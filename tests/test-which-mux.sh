#!/bin/bash
# The hub's backend when JAY_MUX is not set (jay_which_mux in lib/jay-lib.sh): JAY_MUX in the
# environment, then the hub pane the caller runs in, then JAY_MUX in the config, then the hub
# that runs (tmux when both or none run). The hubs here are socket files of this test only, and
# a stub pgrep says which server runs ($STUB/run-tmux, $STUB/run-zellij).
# zellij's and tmux's sockets in /tmp: macOS allows 104 bytes for a socket path.
TMPDIR=/tmp
source "$(dirname "$0")/lib.sh"
link_install
unset JAY_MUX
export JAY_SESSION=jaytest JAY_TMUX_SOCKET=jaytest-sock TMUX_TMPDIR="$TMP/t" ZELLIJ_SOCKET_DIR="$TMP/z"
stub pgrep '
case "$*" in
  *"tmux -L jaytest-sock"*) [[ -f "$STUB/run-tmux" ]] ;;
  *"zellij --server "*"/contract_version_1/jaytest\$") [[ -f "$STUB/run-zellij" ]] ;;
  *) exit 1 ;;
esac'
tsock="$TMUX_TMPDIR/tmux-$UID/$JAY_TMUX_SOCKET"
zsock="$ZELLIJ_SOCKET_DIR/contract_version_1/$JAY_SESSION"
mkdir -p "${tsock%/*}" "${zsock%/*}" "$HOME/.config/jay"

# A socket file at $1 (the server's own, or one left by a server that was killed).
sock() { /usr/bin/python3 -I -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"; }
# hubs <tmux> <zellij>: each "run" (socket and server), "stale" (a socket, no server) or "none".
hubs() {
  rm -f "$tsock" "$zsock" "$STUB/run-tmux" "$STUB/run-zellij"
  [[ "$1" == none ]] || sock "$tsock"
  [[ "$2" == none ]] || sock "$zsock"
  [[ "$1" != run ]] || : >"$STUB/run-tmux"
  [[ "$2" != run ]] || : >"$STUB/run-zellij"
  rm -f "$STUB/pgrep.calls"
}
# The backend and hub state of a script that loads jay-lib.sh with the settings "$@" (env).
which_mux() {
  env "$@" /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh" && printf "%s %s\n" "$JAY_MUX" "${JAY_HUB_STATE#"$JAY_STATE"}"'
}
pgreps() { cat "$STUB/pgrep.calls" 2>/dev/null | wc -l | tr -d ' '; }
config() { printf '%s\n' "$@" >"$HOME/.config/jay/config"; }

# --- No JAY_MUX: the hub that runs ---
config '# none'
hubs none none
eq "none runs: tmux" "tmux /tmux" "$(which_mux)"
eq "none runs: no process asked" 0 "$(pgreps)"
hubs run none
eq "only tmux runs: tmux" "tmux /tmux" "$(which_mux)"
eq "only tmux runs: no process asked" 0 "$(pgreps)"
hubs none run
eq "only zellij runs: zellij" "zellij " "$(which_mux)"
eq "only zellij runs: one pgrep" 1 "$(pgreps)"
hubs run run
eq "both run: tmux" "tmux /tmux" "$(which_mux)"
eq "both run: one pgrep" 1 "$(pgreps)"
hubs none stale
eq "a killed zellij hub's socket: tmux" "tmux /tmux" "$(which_mux)"
hubs stale run
eq "a killed tmux hub's socket and zellij runs: zellij" "zellij " "$(which_mux)"
hubs stale stale
eq "both sockets left, none runs: tmux" "tmux /tmux" "$(which_mux)"
hubs stale none
eq "a killed tmux hub's socket alone: tmux" "tmux /tmux" "$(which_mux)"
eq "a tmux socket alone: no process asked" 0 "$(pgreps)"
# Without ZELLIJ_SOCKET_DIR: zellij's sockets are in $TMPDIR/zellij-<uid> (TMPDIR ends in / on
# macOS; the server's command line has one /).
hubs none none
mkdir -p "$TMP/d/zellij-$UID/contract_version_1"
sock "$TMP/d/zellij-$UID/contract_version_1/jaytest"
: >"$STUB/run-zellij"
eq "zellij's socket in TMPDIR: zellij" "zellij " "$(which_mux -u ZELLIJ_SOCKET_DIR TMPDIR="$TMP/d/")"
eq "zellij's socket in TMPDIR: the server's path" "-a -f zellij --server $TMP/d/zellij-$UID/contract_version_1/jaytest\$" \
  "$(cat "$STUB/pgrep.calls")"
rm -rf "$TMP/d"

# --- JAY_MUX in the environment, then in the config ---
hubs run none
eq "env JAY_MUX=zellij wins over the tmux hub that runs" "zellij " "$(which_mux JAY_MUX=zellij)"
hubs none run
eq "env JAY_MUX=tmux wins over the zellij hub that runs" "tmux /tmux" "$(which_mux JAY_MUX=tmux)"
config 'JAY_MUX=tmux'
eq "config JAY_MUX=tmux wins over the zellij hub that runs" "tmux /tmux" "$(which_mux)"
eq "config: no process asked" 0 "$(pgreps)"
hubs run none
config 'JAY_MUX=zellij'
eq "config JAY_MUX=zellij wins over the tmux hub that runs" "zellij " "$(which_mux)"
eq "env wins over the config" "tmux /tmux" "$(which_mux JAY_MUX=tmux)"
config 'WT_MUX=zellij'
eq "the old name in the config" "zellij " "$(which_mux)"
config '# none'

# --- In a hub pane: the pane's own hub, also when the config names the other one ---
hubs none run
eq "a pane of jay's tmux server: tmux" "tmux /tmux" "$(which_mux TMUX="$tsock,1,0" TMUX_PANE=%3)"
config 'JAY_MUX=zellij'
eq "a pane of jay's tmux server: tmux, over the config" "tmux /tmux" "$(which_mux TMUX="$tsock,1,0" TMUX_PANE=%3)"
eq "a tmux pane: env JAY_MUX wins (the other hub, jay_hub_retarget)" "zellij " "$(which_mux TMUX="$tsock,1,0" JAY_MUX=zellij)"
config '# none'
hubs run none
eq "a pane of the zellij hub: zellij" "zellij " "$(which_mux ZELLIJ=0 ZELLIJ_SESSION_NAME=jaytest ZELLIJ_PANE_ID=2)"
config 'JAY_MUX=tmux'
eq "a pane of the zellij hub: zellij, over the config" "zellij " "$(which_mux ZELLIJ=0 ZELLIJ_SESSION_NAME=jaytest ZELLIJ_PANE_ID=2)"
config '# none'
hubs none run
eq "a pane of the user's own tmux server: the hub that runs" "zellij " "$(which_mux TMUX="$TMUX_TMPDIR/tmux-$UID/default,1,0" TMUX_PANE=%0)"
hubs run none
eq "a pane of the user's own zellij session: the hub that runs" "tmux /tmux" "$(which_mux ZELLIJ=0 ZELLIJ_SESSION_NAME=acme)"
eq "a background agent with a zellij hub pane's variables: the hub that runs" "tmux /tmux" \
  "$(which_mux ZELLIJ=0 ZELLIJ_SESSION_NAME=jaytest CLAUDE_JOB_DIR="$TMP/job")"
hubs none run
eq "a background agent with a tmux hub pane's variables: the hub that runs" "zellij " \
  "$(which_mux TMUX="$tsock,1,0" CLAUDE_JOB_DIR="$TMP/job")"

finish

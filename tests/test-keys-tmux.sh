#!/bin/bash
# jay.conf's keys in a real tmux (a server of its own, jay.conf as its config) with pty clients
# (tests/pty-client.py): the Rex workaround (its block in jay.conf, made by tools/rex-keys.swift)
# gives a Rex client the character that Option composes, and a client that is not Rex keeps its
# M- keys; M-p, M-P, M-o stay stopped; Ctrl g [ (also M-[ from Rex) opens copy-mode. The pane's
# program writes the bytes it reads to a file. About 10 s.
TMPDIR=/tmp # tmux's socket path must stay under 104 bytes
source "$(dirname "$0")/lib.sh"
command -v tmux >/dev/null 2>&1 || PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if ! command -v tmux >/dev/null 2>&1; then
  printf '%-20s skipped: no tmux\n' "$TEST_NAME"
  exit 0
fi
unset TMUX TMUX_PANE
export JAY_MUX=tmux TMUX_TMPDIR="$TMP/tsock" TERM=xterm-256color LANG=en_US.UTF-8
SOCK=jaykeys$$
mkdir -p "$TMUX_TMPDIR"
PY=/usr/bin/python3
CLIENT=""
trap 'kill $CLIENT 2>/dev/null; tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$TMP"' EXIT

# The pane's program: raw mode, every byte it reads goes to $TMP/in.
cat >"$TMP/sink.py" <<'EOF'
import os, sys, tty
tty.setraw(0)
with open(sys.argv[1], "ab", 0) as f:
    while True:
        f.write(os.read(0, 4096))
EOF
: >"$TMP/in"
tmux -u -L "$SOCK" -f "$REPO/config/tmux/jay.conf" new-session -d -s k -x 120 -y 30 \
  "$PY -I $TMP/sink.py $TMP/in"
eq "jay.conf loads with no errors" "" "$(tmux -L "$SOCK" show-messages 2>/dev/null | grep 'jay.conf:')"

# The block's keys and the bytes Rex sends for each under modifyOtherKeys 2: CSI 27;3;<cp>~ for
# M-<c> (Option), CSI 27;4;<cp>~ for M-S-<c> (Shift+Option).
block=$(sed -n '/^# --- Rex workaround: begin/,/^# --- Rex workaround: end/p' "$REPO/config/tmux/jay.conf")
keys=$(printf '%s\n' "$block" | sed -n "s/^bind -n '\(M-[^']*\)' .*/\1/p")
nkeys=$(printf '%s\n' "$keys" | grep -c .)
ok "the block has binds" test "$nkeys" -gt 50
eq "tmux took every bind of the block" "$nkeys" \
  "$(tmux -L "$SOCK" list-keys -T root | grep -c 'client_termtype')"
# csi KEY...: the hex of the CSI 27 sequence of each key name, one per line.
csi() {
  $PY -I -c '
import sys
for k in sys.argv[1:]:
    mod, ch = (4, k[4:]) if k.startswith("M-S-") else (3, k[2:])
    print(("\x1b[27;%d;%d~" % (mod, ord(ch))).encode().hex())' "$@"
}

# client NAME XTVERSION: attach a pty client that answers tmux's queries, XTVERSION as given.
client() {
  PTY_GHOSTTY=0 PTY_XTVERSION="$2" $PY -I "$REPO/tests/pty-client.py" "$TMP/$1.out" 120 30 \
    tmux -u -L "$SOCK" attach -t '=k' &
  CLIENT=$!
  disown # no "Terminated" line when it is killed
  local i
  for i in $(seq 50); do
    [[ "$(tmux -L "$SOCK" list-clients -F '#{client_termtype}' 2>/dev/null)" == "$2" ]] && return 0
    sleep 0.1
  done
  return 1
}
# typed NAME HEX...: type the keys in client NAME; print what the pane read since (hex) once its
# input stops growing.
typed() {
  local name=$1 before size last i
  shift
  before=$(wc -c <"$TMP/in")
  printf '%s\n' "$@" >>"$TMP/$name.out.keys"
  last=-1
  for i in $(seq 60); do
    sleep 0.1
    size=$(wc -c <"$TMP/in")
    ((size > before && size == last)) && break
    last=$size
  done
  tail -c +$((before + 1)) "$TMP/in" | xxd -p | tr -d '\n'
}
# press NAME HEX...: type the keys in client NAME, for keys that the pane does not read.
press() {
  local name=$1
  shift
  printf '%s\n' "$@" >>"$TMP/$name.out.keys"
  sleep 0.6
}
hex() { printf '%s' "$1" | xxd -p | tr -d '\n'; }
in_mode() { tmux -L "$SOCK" display -p -t '=k:' '#{pane_in_mode}'; }

# A Rex client: Rex's XTVERSION answer is "rex <version>".
ok "a Rex client" client rex 'rex 0.1.0-preview.18'
for c in / '[' @ π; do
  eq "Rex: Option types $c" "$(hex "$c")" "$(typed rex "$(csi "M-$c")")"
done
eq "Rex: Shift+Option types ±" "$(hex ±)" "$(typed rex "$(csi M-S-±)")"
want=$(printf '%s\n' "$keys" | sed 's/^M-S-//; s/^M-//' | tr -d '\n')
# shellcheck disable=SC2046
eq "Rex: all $nkeys keys of the block type their character" "$(hex "$want")" \
  "$(typed rex $(csi $keys))"
eq "Rex: M-p, M-P, M-o stay stopped" "$(hex z)" "$(typed rex "$(csi M-p)" "$(csi M-P)" "$(csi M-o)" 7a)"
eq "Rex: plain keys as before" "$(hex 'a/é')" "$(typed rex 61 2f c3a9)"
press rex 07 5b
eq "Rex: Ctrl g [ opens copy-mode" 1 "$(in_mode)"
press rex 71
eq "Rex: q leaves it" 0 "$(in_mode)"
press rex 07 "$(csi 'M-[')"
eq "Rex: Ctrl g and Option+9 ([ on CSA) open copy-mode" 1 "$(in_mode)"
press rex 71
kill "$CLIENT"

# A client that is not Rex (Ghostty): the M- keys go on to the pane (ESC and the character in a
# pane with no extended keys).
ok "a Ghostty client" client ghostty 'ghostty 1.3.2'
for c in / '[' @ π; do
  eq "Ghostty: M-$c stays M-$c" "$(hex $'\e'"$c")" "$(typed ghostty "$(csi "M-$c")")"
done
eq "Ghostty: M-p, M-P, M-o stay stopped" "$(hex z)" \
  "$(typed ghostty "$(csi M-p)" "$(csi M-P)" "$(csi M-o)" 7a)"
press ghostty 07 "$(csi 'M-[')"
eq "Ghostty: Ctrl g M-[ is no copy-mode" 0 "$(in_mode)"
press ghostty 07 5b
eq "Ghostty: Ctrl g [ opens copy-mode" 1 "$(in_mode)"
press ghostty 71
finish

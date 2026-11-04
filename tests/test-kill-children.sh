#!/bin/bash
# jay_kill_children (a pick in the hub list stops the program of a pane): it stops the pane's
# own processes, but not a process that leads a group of its own, nor anything under it.
# Claude's daemon (2.1.318) is a child of the client that started it, often the `claude attach`
# of the agent pane, in a process group of its own, and the background agents run under it.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

pids="$TMP/pids"
mkdir -p "$pids"
# The stand-in of `claude attach`: a helper with a child of its own in its group (as
# leave_agent_view and the like), a "daemon" in a process group of its own (setpgrp) with a
# child, and a "service" in a session of its own (setsid) with a child.
cat >"$TMP/attach" <<EOF
#!/bin/bash
bash -c 'sleep 301 & echo \$! >"$pids/helper-child"; wait' &
echo \$! >"$pids/helper"
perl -e 'setpgrp(0, 0); exec @ARGV' bash -c 'sleep 302 & echo \$! >"$pids/daemon-child"; wait' &
echo \$! >"$pids/daemon"
perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash -c 'sleep 303 & echo \$! >"$pids/service-child"; wait' &
echo \$! >"$pids/service"
wait
EOF
chmod +x "$TMP/attach"
# The stand-in of jay-pane: runs the attach, and runs on after it (as jay-pane waits for the
# next target).
bash -c '"$1" & echo $! >"$2/attach"; wait; exec sleep 304' _ "$TMP/attach" "$pids" 2>/dev/null &
pane=$!

cleanup() {
  local f
  for f in daemon service; do [[ -s "$pids/$f" ]] && kill -KILL -- "-$(cat "$pids/$f")" 2>/dev/null; done
  for f in "$pids"/*; do [[ -s "$f" ]] && kill -KILL "$(cat "$f")" 2>/dev/null; done
  { kill -KILL "$pane" && wait "$pane"; } 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# Running, not a zombie that waits for its parent.
alive() {
  local s
  s=$(ps -o stat= -p "$1" 2>/dev/null)
  [[ -n "$s" && "$s" != Z* ]]
}
pid() { cat "$pids/$1" 2>/dev/null; }

for _ in $(seq 50); do
  [[ -s "$pids/helper-child" && -s "$pids/daemon-child" && -s "$pids/service-child" ]] && break
  sleep 0.1
done
eq "setup: the daemon leads its own group" "$(pid daemon)" "$(ps -o pgid= -p "$(pid daemon)" | tr -d ' ')"
eq "setup: the attach is in the pane's group" "$(ps -o pgid= -p "$pane" | tr -d ' ')" \
  "$(ps -o pgid= -p "$(pid attach)" | tr -d ' ')"

jay_kill_children "$pane"
gone() { local _p; for _p in $(seq 30); do alive "$1" || return 0; sleep 0.1; done; return 1; }

ok "the attach stops" gone "$(pid attach)"
ok "its helper stops" gone "$(pid helper)"
ok "and the helper's child" gone "$(pid helper-child)"
ok "the pane stand-in itself runs on" alive "$pane"
ok "the daemon (a group of its own) runs on" alive "$(pid daemon)"
ok "and its child (a background agent)" alive "$(pid daemon-child)"
ok "a setsid service runs on" alive "$(pid service)"
ok "and its child" alive "$(pid service-child)"

finish

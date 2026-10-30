#!/bin/bash
# jay run restart of a task as turbo runs `pnpm dev`: on Ctrl-C it sends TERM to its children
# (which ignore Ctrl-C, as on ptys of their own), they stop a second late, and it exits 143; a
# process under it ends 2 s after it. The restart starts it again once all of that ended, and
# the new run stays (the restart used to stop it with TERM 10 s later: exited 143). A tmux
# server of its own (no `jay` hub, no client): the window hub and the task's tasks window.
TMPDIR=/tmp
source "$(dirname "$0")/lib.sh"
link_install
command -v tmux >/dev/null 2>&1 || PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if ! command -v tmux >/dev/null 2>&1; then
  printf '%-20s skipped: no tmux\n' "$TEST_NAME"
  exit 0
fi
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
unset TMUX TMUX_PANE
SOCK=jayrestart$$
export JAY_MUX=tmux JAY_TMUX_SOCKET=$SOCK JAY_SESSION=jay TMUX_TMPDIR="$TMP/tsock" ZELLIJ_SOCKET_DIR="$TMP/zsock"
export SHELL=/bin/bash TERM=xterm-256color JAY_TASK_SHELL="/bin/bash -c"
mkdir -p "$TMUX_TMPDIR"
tm() { tmux -L "$SOCK" "$@"; }
trap 'tm kill-server 2>/dev/null; rm -rf "$TMP"' EXIT
tm -f /dev/null new-session -d -s jay -n hub -x 200 -y 50 'sleep 100000'

LOG="$TMP/dev.log"
repo "$TMP/shop"
cat >"$TMP/shop/dev.sh" <<EOF
#!/bin/bash
printf 'start %s\n' \$\$ >>"$LOG"
kids=()
for i in 1 2; do
  bash -c 'trap "" INT; trap "sleep 1; exit 143" TERM; while :; do sleep 0.2; done' &
  kids+=(\$!)
done
bash -c 'while kill -0 \$1 2>/dev/null; do sleep 0.1; done; sleep 2; echo linger-end >>"$LOG"' - \$\$ &
trap 'kill -TERM "\${kids[@]}"; wait "\${kids[@]}"; exit 143' INT TERM
while :; do sleep 0.2; done
EOF
chmod +x "$TMP/shop/dev.sh"
cd "$TMP/shop" || exit 1

starts() { grep -c '^start' "$LOG" 2>/dev/null; }
starts_are() { [[ "$(starts)" == "$1" ]]; }
onces_are() { [[ "$(grep -c '^once' "$LOG")" == "$1" ]]; }
# within SECS CMD...: CMD succeeds within SECS seconds.
within() {
  local end=$((SECONDS + $1))
  shift
  until "$@"; do ((SECONDS >= end)) && return 1; sleep 0.2; done
}
state() { jay run ls --json | jq -r '.[] | select(.name == "dev") | .state'; }

has "started" "dev: started in the hub" "$(jay run -n dev -- ./dev.sh 2>&1)"
within 10 starts_are 1 || fail "the task never started" "$(cat "$LOG" 2>/dev/null)"
sleep 1
t0=$SECONDS
has "restart" "dev: restarted" "$(jay run restart dev 2>&1)"
ok "the restart takes no 10 s (no TERM)" test $((SECONDS - t0)) -lt 9
within 5 starts_are 2
eq "the new run starts after the old one ended, the process that it left too" \
  "start linger-end start" "$(awk '{ print $1 }' "$LOG" | tr '\n' ' ' | sed 's/ $//')"
new=$(awk '/^start/ { p = $2 } END { print p }' "$LOG")
# The old restart sent TERM to the new run 10 s after its Ctrl-C.
((t0 + 12 > SECONDS)) && sleep $((t0 + 12 - SECONDS))
ok "the new run still runs 12 s after the restart" kill -0 "$new"
eq "its state" "running" "$(state)"
eq "no third start" "2" "$(starts)"

# A task that ended (exited, waiting for Enter): restart starts it again.
jay run stop dev >/dev/null 2>&1
has "a short task" "once: started" "$(jay run -n once -- 'echo once >>"'"$LOG"'"; exit 3' 2>&1)"
once() { jay run ls --json | jq -r '.[] | select(.name == "once") | "\(.state) \(.exit // "")"'; }
once_is() { [[ "$(once)" == "$1" ]]; }
within 10 once_is "exited 3" || fail "once never exited" "$(once)"
has "restart of an exited task" "once: restarted" "$(jay run restart once 2>&1)"
within 5 onces_are 2 || fail "once did not run again" "$(cat "$LOG")"
jay run stop once >/dev/null 2>&1
finish

#!/bin/bash
# A throwaway zellij hub: `jay` starts it in a pty (tests/pty-client.py) as a session of its own,
# in the fake HOME, with a stub claude, stub tuicr and yazi. It checks that the hub's panes
# cannot be lost: fzf's quit keys do nothing in the list, a list whose fzf is killed starts
# again, and a pane that is closed or whose program was killed (zellij holds it) comes back with
# `jay`, in its column and at its saved width; also a hub tab with none of its panes left. The
# server is killed at the end. Run it with: tests/run.sh smoke
# The fake HOME and zellij's sockets (TMPDIR) go in /tmp: macOS allows 104 bytes for a socket path.
TMPDIR=/tmp
source "$(dirname "$0")/lib.sh"
link_install
rm -f "$HOME/.local/bin/zellij" "$HOME/.local/bin/curl" # the real zellij; the list's fzf takes its reloads through curl
command -v zellij >/dev/null 2>&1 || PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if ! command -v zellij >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1; then
  printf '%-20s skipped: no zellij or fzf\n' "$TEST_NAME"
  exit 0
fi
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
export TMPDIR=/tmp JAY_SESSION=jaysmokez$$ TERM=xterm-256color JAY_ROOTS="$TMP/projects" SHELL=/bin/bash
mkdir -p "$HOME/.config/zellij" "$HOME/.local/share/mise/shims" "$TMP/projects/acme"
# Locked, as the hub expects: every key but Ctrl g reaches the panes. No tips or notes (a
# floating pane would take the focus).
printf 'show_startup_tips false\nshow_release_notes false\ndefault_mode "locked"\n' >"$HOME/.config/zellij/config.kdl"

repo "$TMP/projects/acme/shop"
git -C "$TMP/projects/acme/shop" worktree add -q -b fix-login "$TMP/projects/acme/shop.fix-login"
now=$(($(date +%s) * 1000))
stub_agents "[
 {\"kind\":\"background\",\"id\":\"aaaa0001\",\"sessionId\":\"aaaa0001-0000-0000-0000-000000000001\",\"name\":\"fix-login\",
  \"cwd\":\"$TMP/projects/acme/shop.fix-login\",\"state\":\"working\",\"status\":\"idle\",\"startedAt\":$now,\"pid\":1},
 {\"kind\":\"background\",\"id\":\"bbbb0001\",\"sessionId\":\"bbbb0001-0000-0000-0000-000000000001\",\"name\":\"hub\",
  \"cwd\":\"$TMP/projects\",\"state\":\"working\",\"status\":\"idle\",\"startedAt\":$now,\"pid\":1}]"
mkdir -p "$HOME/.local/state/jay"
printf 'bbbb0001\n' >"$HOME/.local/state/jay/hub-claude"
# jay-pane puts mise's shims first on its PATH: the stubs go there too.
for d in "$HOME/.local/bin" "$HOME/.local/share/mise/shims"; do
  cat >"$d/claude" <<SH
#!/bin/bash
case "\${1:-} \${2:-}" in
  "agents --json") cat "$STUB/agents.json" ;;
  "attach "*) printf '\nATTACHED %s\n' "\$2"; exec sleep 100000 ;;
  *) exit 1 ;;
esac
SH
  printf '#!/bin/bash\nprintf "TUICR %%s %%s\\n" "$PWD" "$*"\nprintf "\\n\\n NORMAL  q quit\\n"\nexec sleep 100000\n' >"$d/tuicr"
  printf '#!/bin/bash\nprintf "YAZI %%s\\n" "$*"\nread -rsn1 _\n' >"$d/yazi"
  chmod +x "$d/claude" "$d/tuicr" "$d/yazi"
done

z() { perl -e 'alarm 5; exec @ARGV or exit 127' zellij -s "$JAY_SESSION" action "$@"; }
within() {
  local name=$1 end=$((SECONDS + $2))
  shift 2
  while :; do
    "$@" >/dev/null 2>&1 && { pass "$name"; return 0; }
    ((SECONDS >= end)) && { fail "$name" "never: $*"; return 1; }
    sleep 0.3
  done
}
# The hub tab's panes from the left: "<title>" each, and the one of a title.
hub_panes() { z list-panes -a -j -c | jq -r '[.[] | select((.is_plugin | not) and .tab_name == "hub" and (.is_floating | not))] | sort_by(.pane_x) | .[] | "terminal_\(.id) \(.exited // false) \(.pane_x) \(.pane_columns) \(.title)"'; }
cols_are() { [[ "$(hub_panes | awk '$2 == "false" { print $5 }' | tr '\n' ' ')" == "$1" ]]; }
pane_by_title() { hub_panes | awk -v t="$1" '$5 == t { print $1; exit }'; }
screen_has() { z dump-screen -p "$1" 2>/dev/null | grep -q "$2"; }
held() { hub_panes | awk -v p="$1" '$1 == p && $2 == "true" { f = 1 } END { exit !f }'; }
share_of() { hub_panes | awk -v p="$1" '{ w = $3 + $4; if (w > t) t = w } $1 == p { c = $4 } END { print int(c * 100 / t + 0.5) }'; }
near() { (($1 >= $2 - 6 && $1 <= $2 + 6)); }
list_fzf() { pgrep -f "fzf .*--listen=$HOME/" | head -1; }
key() { printf '%s\n' "$1" >>"$TMP/client.out.keys"; }
cleanup() {
  kill "$client" 2>/dev/null
  wait "$client" 2>/dev/null # no "Terminated" line
  pkill -9 -f "zellij --server .*/$JAY_SESSION\$" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

/usr/bin/python3 -I "$REPO/tests/pty-client.py" "$TMP/client.out" 200 50 jay &
client=$!
within "jay starts the zellij hub" 15 cols_are "worktrees hub review "
list=$(pane_by_title worktrees) agent=$(pane_by_title hub) review=$(pane_by_title review)
within "the list shows the agents" 15 screen_has "$list" fix-login
within "the agent pane opens the hub Claude" 10 screen_has "$agent" 'ATTACHED bbbb0001'
share=$(share_of "$list")

# fzf's quit keys do nothing; a killed fzf starts again.
z move-focus left; z move-focus left
fzf_pid=$(list_fzf)
key 1b; key 03; key 11; key 04
sleep 1
eq "esc, Ctrl-C, Ctrl-Q, Ctrl-D: fzf runs on" "$fzf_pid" "$(list_fzf)"
kill -9 "$fzf_pid"
within "fzf killed: the list says so" 3 screen_has "$list" 'The list ended'
within "fzf killed: rows again" 15 screen_has "$list" fix-login
ok "fzf killed: a new fzf" bash -c "[[ \"\$(pgrep -f 'fzf .*--listen=$HOME/' | head -1)\" != $fzf_pid ]]"

# The list's program killed: zellij holds the pane; jay brings a new list in its place.
fzf_pid=$(list_fzf)
pid=$(ps -o ppid= -p "$fzf_pid" | tr -d ' ')
kill -9 "$pid" "$fzf_pid"
within "list program killed: zellij holds the pane" 5 held "$list"
jay >/dev/null 2>&1
within "held list, jay: a new list, left" 8 cols_are "worktrees hub review "
list=$(pane_by_title worktrees)
within "jay: rows in the new list" 15 screen_has "$list" fix-login
ok "jay: the list at its width" near "$(share_of "$list")" "$share"
z close-pane --pane-id "$list"
within "list closed" 3 cols_are "hub review "
jay >/dev/null 2>&1
within "list closed, jay: a new list, left" 8 cols_are "worktrees hub review "
list=$(pane_by_title worktrees)
within "jay: rows" 15 screen_has "$list" fix-login
ok "jay: at its width" near "$(share_of "$list")" "$share"

# The agent and review: closed, or their program killed.
z close-pane --pane-id "$agent"
within "agent closed" 3 cols_are "worktrees review "
jay >/dev/null 2>&1
within "agent closed, jay: back in the middle" 8 cols_are "worktrees hub review "
agent=$(pane_by_title hub)
within "jay: the agent it showed" 10 screen_has "$agent" 'ATTACHED bbbb0001'
# Only this hub's: the fake HOME is in the command line.
pid=$(pgrep -f "$HOME/.local/bin/jay-pane agent\$" | head -1)
[[ -n "$pid" ]] && { pkill -9 -P "$pid"; kill -9 "$pid"; }
within "agent program killed: zellij holds the pane" 5 held "$agent"
jay >/dev/null 2>&1
within "held agent, jay: back in the middle" 8 cols_are "worktrees hub review "
agent=$(pane_by_title hub)
within "jay: the agent again" 10 screen_has "$agent" 'ATTACHED bbbb0001'
z close-pane --pane-id "$review"
within "review closed" 3 cols_are "worktrees hub "
jay >/dev/null 2>&1
within "review closed, jay: back on the right" 8 cols_are "worktrees hub review "
review=$(pane_by_title review)
within "jay: review's pane" 10 screen_has "$review" 'Pick a worktree'

# None of the hub's panes left, the hub tab closed (another tab keeps the session): jay makes
# the hub tab again.
z new-tab --name tasks >/dev/null
for p in "$list" "$agent" "$review"; do z close-pane --pane-id "$p"; done
within "all three closed" 3 cols_are ""
jay >/dev/null 2>&1
within "jay: a hub tab with list, agent, review" 10 cols_are "worktrees hub review "
within "jay: rows in its list" 15 screen_has "$(pane_by_title worktrees)" fix-login
eq "one hub tab" 1 "$(z list-tabs -j | jq '[.[] | select(.name == "hub")] | length')"
finish

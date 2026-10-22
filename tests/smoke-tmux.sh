#!/bin/bash
# A throwaway tmux hub (no JAY_MUX: the default): `jay` starts it in a pty (tests/pty-client.py) on a
# socket of its own, in the fake HOME, with a stub claude (attach keeps its args, ← is the agent
# view), stub tuicr and yazi. It checks the layout, a pick (also over Claude's agent view), the
# focus keys, files over review and back, hide and show review, tasks windows, the bar and its
# note, the tasks picker, panes that cannot be lost (fzf's quit keys, killed programs, closed
# panes and window: Ctrl g 1 2 3 and jay bring them back) and Ctrl g q. The server is killed at the end. About a minute.
# Run it with: tests/run.sh smoke
# The fake HOME goes in /tmp: the list's fzf socket and tmux's socket live in it, and macOS
# allows 104 bytes for a socket path (the default temp folder is too deep).
TMPDIR=/tmp
source "$(dirname "$0")/lib.sh"
link_install
command -v tmux >/dev/null 2>&1 || PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if ! command -v tmux >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1; then
  printf '%-20s skipped: no tmux or fzf\n' "$TEST_NAME"
  exit 0
fi
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
unset TMUX TMUX_PANE
SOCK=jaysmoke$$
# No JAY_MUX: with no hub, jay starts a tmux hub, and the scripts outside it find it
# (jay_which_mux). zellij's sockets in a folder of this test, so a zellij hub of the user's never
# counts.
unset JAY_MUX
export JAY_TMUX_SOCKET=$SOCK JAY_SESSION=jay TMUX_TMPDIR="$TMP/tsock" ZELLIJ_SOCKET_DIR="$TMP/zsock" TERM=xterm-256color
export JAY_ROOTS="$TMP/projects" SHELL=/bin/bash
mkdir -p "$TMUX_TMPDIR" "$HOME/.config/jay" "$HOME/.local/share/mise/shims" "$TMP/projects/acme"
ln -sfn "$REPO/config/tmux/jay.conf" "$HOME/.config/jay/tmux.conf"
rm -f "$HOME/.local/bin/curl" # the list's fzf takes its reloads through curl (a unix socket)

# acme/shop with a worktree shop.fix-login; two agents and the hub Claude.
repo "$TMP/projects/acme/shop"
git -C "$TMP/projects/acme/shop" worktree add -q -b fix-login "$TMP/projects/acme/shop.fix-login"
# acme/web with a worktree web.fix, in JAY_ORCHESTRATE: a pick of its rows starts its orchestrator.
repo "$TMP/projects/acme/web"
git -C "$TMP/projects/acme/web" worktree add -q -b fix "$TMP/projects/acme/web.fix"
printf 'JAY_ORCHESTRATE=web\n' >"$HOME/.config/jay/config"
now=$(($(date +%s) * 1000))
stub_agents "[
 {\"kind\":\"background\",\"id\":\"aaaa0001\",\"sessionId\":\"aaaa0001-0000-0000-0000-000000000001\",\"name\":\"fix-login\",
  \"cwd\":\"$TMP/projects/acme/shop.fix-login\",\"state\":\"working\",\"status\":\"idle\",\"startedAt\":$now,\"pid\":1},
 {\"kind\":\"background\",\"id\":\"aaaa0002\",\"sessionId\":\"aaaa0002-0000-0000-0000-000000000002\",\"name\":\"orch\",
  \"cwd\":\"$TMP/projects/acme/shop\",\"state\":\"working\",\"status\":\"idle\",\"startedAt\":$now,\"pid\":1},
 {\"kind\":\"background\",\"id\":\"bbbb0001\",\"sessionId\":\"bbbb0001-0000-0000-0000-000000000001\",\"name\":\"hub\",
  \"cwd\":\"$TMP/projects\",\"state\":\"working\",\"status\":\"idle\",\"startedAt\":$now,\"pid\":1},
 {\"kind\":\"background\",\"id\":\"dddd0001\",\"sessionId\":\"dddd0001-0000-0000-0000-000000000001\",\"name\":\"outsider\",
  \"cwd\":\"$TMP/projects-old\",\"state\":\"working\",\"status\":\"busy\",\"startedAt\":$now,\"pid\":1}]"
mkdir -p "$HOME/.local/state/jay"
printf 'bbbb0001\n' >"$HOME/.local/state/jay/hub-claude"
# jay-pane puts mise's shims first on its PATH: the stubs go there too.
for d in "$HOME/.local/bin" "$HOME/.local/share/mise/shims"; do
  cat >"$d/claude" <<SH
#!/bin/bash
case "\${1:-} \${2:-}" in
  "agents --json") cat "$STUB/agents.json" ;;
  # A new background agent (the orchestrator of a pick): it comes into the agents a second later.
  "--bg "*)
    printf '%s\n' "\$*" >>"$STUB/bg.calls"
    sleep 1
    jq -c --arg c "\$PWD" '. + [{kind: "background", id: "cccc0001", sessionId: "cccc0001-0000-0000-0000-000000000001",
      name: "web/main", cwd: \$c, state: "blocked", status: "idle", startedAt: 0, pid: 1}]' "$STUB/agents.json" >"$STUB/agents.new" \
      && mv "$STUB/agents.new" "$STUB/agents.json"
    echo "backgrounded · cccc0001" ;;
  "agents "*) printf 'AGENT VIEW enter to return · space to reply\n'; sleep 100000 ;;
  "attach "*)
    # As claude attach: the process keeps its args. Left arrow: the agent view, by exec (as
    # Claude does), or in the same process when \$STUB/inproc exists.
    # As claude attach in a tmux pane: it appends ',*:RGB' to the server's terminal-features.
    [[ -n "\${TMUX:-}" ]] && tmux set -as terminal-features ',*:RGB'
    printf '\nATTACHED %s\n' "\$2"
    while IFS= read -rsn1 c; do
      [[ "\$c" == \$'\e' ]] || continue
      read -rsn2 c
      [[ "\$c" == '[D' ]] || continue
      if [[ -f "$STUB/inproc" ]]; then printf '\nAGENT VIEW enter to return · space to reply\n'; else exec "\$0" agents; fi
    done
    sleep 100000 ;;
  *) exit 1 ;;
esac
SH
  printf '#!/bin/bash\nprintf "TUICR %%s %%s\\n" "$PWD" "$*"\nprintf "\\n\\n NORMAL  q quit\\n"\nexec sleep 100000\n' >"$d/tuicr"
  printf '#!/bin/bash\nprintf "YAZI %%s\\n" "$*"\nread -rsn1 _\n' >"$d/yazi"
  chmod +x "$d/claude" "$d/tuicr" "$d/yazi"
done

tm() { tmux -L "$SOCK" "$@"; }
# within NAME SECS CMD...: CMD succeeds within SECS seconds.
within() {
  local name=$1 end=$((SECONDS + $2))
  shift 2
  while :; do
    "$@" >/dev/null 2>&1 && { pass "$name"; return 0; }
    ((SECONDS >= end)) && { fail "$name" "never: $*"; return 1; }
    sleep 0.2
  done
}
pane_by_title() { tm list-panes -s -t =jay -F '#{pane_id} #{pane_title}' | awk -v t="$1" 'index(substr($0, index($0, " ") + 1), t) == 1 { print $1; exit }'; }
screen_has() { tm capture-pane -p -J -t "$1" 2>/dev/null | grep -q "$2"; }
screen_hasnt() { ! screen_has "$@"; }
active_window() { tm list-windows -t =jay -F '#{?window_active,#{window_name},}' | grep .; }
active_pane() { tm list-panes -s -t =jay -F '#{?#{&&:#{window_active},#{pane_active}},#{pane_id},}' | grep .; }
is_pane() { [[ "$(active_pane)" == "$1" ]]; }
is_window() { [[ "$(active_window)" == "$1" ]]; }
place_of() { tm display -p -t "$1" '#{window_name}.#{pane_index}'; }
is_at() { [[ "$(place_of "$1")" == "$2" ]]; }
key() { printf '%s\n' "$1" >>"$TMP/client.out.keys"; }
client_shows() { tr -d '\000' <"$TMP/client.out" | tail -c 8000 | grep -q "$1"; }
# The last terminal title tmux sent to the client (OSC 0 or 2).
last_title() { perl -0777 -ne 'my @t = /\e\][02];([^\a\e]*)(?:\a|\e\\)/g; print $t[-1] // ""' "$TMP/client.out"; }
title_is() { [[ "$(last_title)" == "$1" ]]; }
no_window() { ! tm list-windows -t =jay -F '#{window_name}' | grep -qx "$1"; }
has_window() { tm list-windows -t =jay -F '#{window_name}' | grep -qx "$1"; }
has_client() { [[ -n "$(tm list-clients 2>/dev/null)" ]]; }
option_is() { [[ "$(tm show -gv "$1")" == "$2" ]]; }
option_has() { [[ "$(tm show -gv "$1")" == *"$2"* ]]; }
cleanup() {
  kill "$client" 2>/dev/null
  tm kill-server 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

/usr/bin/python3 -I "$REPO/tests/pty-client.py" "$TMP/client.out" 200 50 jay &
client=$!
within "jay starts the tmux hub" 10 tm has-session -t =jay
# jay_mux_start names the panes after the splits: wait for the names, not only the panes.
within "the hub window: list, agent, review" 10 bash -c "[[ \"\$(tmux -L $SOCK list-panes -t =jay:hub -F '#{pane_title}' | sort | tr '\n' ' ')\" == 'hub review worktrees ' ]]"
list=$(pane_by_title worktrees) agent=$(pane_by_title hub) review=$(pane_by_title review)
eq "the panes from the left" "hub.0 hub.1 hub.2" "$(place_of "$list") $(place_of "$agent") $(place_of "$review")"
within "a client" 3 has_client
within "the agent pane opens the hub Claude" 10 screen_has "$agent" 'ATTACHED bbbb0001'
within "the list shows the agents" 15 screen_has "$list" fix-login
ok "an agent outside JAY_ROOTS has no row" screen_hasnt "$list" outsider
first_row_is_hub() { tm capture-pane -p -t "$list" | grep -v '^[[:space:]]*$' | head -1 | grep -q '◆ hub'; }
within "the list has no counts row: its first row is ◆ hub" 5 first_row_is_hub

within "the focus starts in the middle" 2 is_pane "$agent"
eq "no JAY_MUX outside the hub: the tmux hub that runs" "tmux" "$(bash -c 'source "$HOME/.local/lib/jay-lib.sh" && printf %s "$JAY_MUX"')"
ok "jay run ls from outside, no JAY_MUX: the hub answers" jay run ls

# A click on a list row selects it (no pick); a double click opens it, as Enter.
click_at() { # click_at PANE TEXT [2]: (double) click on the first line of PANE that has TEXT
  local top left n x y seq
  read -r top left < <(tm display -p -t "$1" '#{pane_top} #{pane_left}')
  n=$(tm capture-pane -p -t "$1" | grep -n "$2" | head -1 | cut -d: -f1)
  [[ -n "$n" ]] || return 1
  # pane_top counts from the window; the status line is the screen's first row.
  x=$((left + 8)) y=$((top + 1 + n))
  seq=$(printf '\e[<0;%d;%dM\e[<0;%d;%dm' "$x" "$y" "$x" "$y")
  [[ "${3:-}" == 2 ]] && seq+=$seq
  key "$(printf '%s' "$seq" | xxd -p | tr -d '\n')"
}
cursor_on() { tm capture-pane -p -t "$list" | grep "$1" | head -1 | grep -q '▌'; }
click_at "$list" '○ fix-login'
within "click: the list gets the focus" 3 is_pane "$list"
within "click: the cursor on the clicked row" 3 cursor_on '○ fix-login'
sleep 1.5
ok "click: no pick (the middle still shows the hub Claude)" screen_has "$agent" 'ATTACHED bbbb0001'
ok "click: no pick (review unchanged)" bash -c "! tmux -L $SOCK capture-pane -p -J -t $review | grep -q 'TUICR .*shop.fix-login'"
click_at "$list" '○ fix-login' 2
within "double click: the agent opens" 5 screen_has "$agent" 'ATTACHED aaaa0001'
within "double click: the focus in the middle, as Enter" 3 is_pane "$agent"
sleep 1
ok "double click: the focus stays in the middle (tmux's late double click does not take it back)" is_pane "$agent"
within "double click: review in its worktree" 5 screen_has "$review" 'TUICR .*shop.fix-login'
# fzf takes a click right after a double click (its pick still running) as nothing: a pause.
sleep 1
click_at "$list" '◆ hub'
within "click on ◆ hub: selected" 3 cursor_on '◆ hub'
sleep 1
ok "click on ◆ hub: no pick" screen_has "$agent" 'ATTACHED aaaa0001'

# A pick: the agent in the middle (Opening at once), its worktree in review, the banner.
jay go aaaa0001
within "pick: Opening <name>" 3 screen_has "$agent" 'Opening fix-login'
within "pick: the agent attached" 5 screen_has "$agent" 'ATTACHED aaaa0001'
within "tab title: the session and the agent, as zellij's" 3 title_is 'jay | fix-login'
eq "pick: its title" fix-login "$(tm display -p -t "$agent" '#{pane_title}')"
within "pick: review in its worktree" 5 screen_has "$review" 'TUICR .*shop.fix-login'
within "pick: review's title" 2 bash -c "[[ \"\$(tmux -L $SOCK display -p -t $review '#{pane_title}')\" == 'turns · shop'* ]]"
within "pick: the banner's worktree" 3 option_is @jay_where shop/fix-login
tm select-pane -t "$list"
jay go aaaa0001
within "pick from the list: the focus in the middle" 2 is_pane "$agent"

# Claude's agent view (← in claude attach), then a pick of the same agent: it opens again.
: >"$STUB/inproc"
key 1b5b44
within "← in place: the agent view" 3 screen_has "$agent" 'AGENT VIEW'
jay go aaaa0001
within "same agent over the agent view: attached anew" 3 screen_hasnt "$agent" 'AGENT VIEW'
rm -f "$STUB/inproc"
key 1b5b44
within "← by exec: the pane says you left" 4 screen_has "$agent" 'You left this agent'
jay go aaaa0001
within "same agent after leaving: attached" 3 screen_has "$agent" 'ATTACHED aaaa0001'

# A notice click: jay-notify gives terminal-notifier a command (-execute), which macOS runs
# through /bin/sh with launchd's environment: HOME and the system PATH, no TMUX, no JAY_MUX
# anywhere (jay_which_mux finds the tmux hub that runs). The agent opens in the middle column and the hub's Ghostty tab
# comes to the front; no new tab. Stubs first on PATH: Ghostty's AppleScript (a tab on the hub's
# client, another tab selected), pgrep for Ghostty, lsappinfo.
printf 'JAY_ROOTS=%s\n' "$JAY_ROOTS" >>"$HOME/.config/jay/config"
cat >"$HOME/.local/bin/terminal-notifier" <<SH
#!/bin/bash
while ((\$#)); do [[ "\$1" == -execute ]] && printf '%s\n' "\$2" >"$STUB/notice.execute"; shift; done
SH
mkdir -p "$TMP/gh"
cat >"$TMP/gh/osascript" <<SH
#!/bin/bash
if [[ "\$1" == -e ]]; then
  printf 'gh-hub\tfalse\ttrue\t%s\tjay | hub\ngh-other\ttrue\ttrue\t/dev/ttys999\tzsh\n' \
    "\$(tmux -L $SOCK list-clients -F '#{client_tty}' | head -1)"
else
  cat >/dev/null
  printf '%s\n' "\$*" >>"$STUB/gh.calls"
  [[ \$# == 3 ]] && echo gh-new
fi
exit 0
SH
printf '#!/bin/bash\n[[ "$*" == "-xq ghostty" ]] || exec /usr/bin/pgrep "$@"\n' >"$TMP/gh/pgrep"
printf '#!/bin/bash\nexit 0\n' >"$TMP/gh/lsappinfo"
chmod +x "$HOME/.local/bin/terminal-notifier" "$TMP/gh/"*
jay go hub
within "click: the middle shows the hub Claude first" 5 screen_has "$agent" 'ATTACHED bbbb0001'
jq -n --arg c "$TMP/projects/acme/shop.fix-login" '{hook_event_name: "Stop", cwd: $c,
  session_id: "aaaa0001-0000-0000-0000-000000000001", last_assistant_message: "result: done"}' | jay-notify
within "notice: terminal-notifier gets the click command" 5 test -s "$STUB/notice.execute"
has "notice: the click runs jay-go with the session id" "jay-go aaaa0001-0000-0000-0000-000000000001" "$(cat "$STUB/notice.execute" 2>/dev/null)"
env -i HOME="$HOME" PATH="$TMP/gh:/usr/bin:/bin:/usr/sbin:/sbin" TMUX_TMPDIR="$TMUX_TMPDIR" JAY_TMUX_SOCKET="$SOCK" \
  ZELLIJ_SOCKET_DIR="$ZELLIJ_SOCKET_DIR" /bin/sh -c "$(cat "$STUB/notice.execute")"
within "click: the agent in the middle column" 5 screen_has "$agent" 'ATTACHED aaaa0001'
eq "click: its title" fix-login "$(tm display -p -t "$agent" '#{pane_title}')"
within "click: the focus in the middle" 2 is_pane "$agent"
eq "click: the hub's Ghostty tab comes to the front, no new tab" "- gh-hub" "$(cat "$STUB/gh.calls" 2>/dev/null)"
eq "click: jay-go says nothing in the notice log" "" "$(cat "$HOME/.local/state/jay/notify.log" 2>/dev/null)"

# Ctrl g keys.
key 0731; within "Ctrl g 1: the list" 2 is_pane "$list"
within "tab title follows the focus" 3 title_is 'jay | worktrees'
key 0733; within "Ctrl g 3: review" 2 is_pane "$review"
key 0732; within "Ctrl g 2: the agent" 2 is_pane "$agent"
within "tab title back on the agent" 3 title_is 'jay | fix-login'
key 0768; within "Ctrl g h: left" 2 is_pane "$list"
key 076c; within "Ctrl g l: right" 2 is_pane "$agent"
key 07; within "Ctrl g: the bar shows the keys" 2 client_shows 'h l 1 2 3 ; v Tab r t q'
key 1b

# Files over review (e in review) and back (q in yazi; or from outside).
jay-sidebar --files
files=$(pane_by_title "files ·")
ok "files: a pane" test -n "$files"
within "files: yazi runs" 5 screen_has "$files" YAZI
eq "files: in review's place" hub.2 "$(place_of "$files")"
eq "files: review runs on, hidden" _cover "$(tm display -p -t "$review" '#{window_name}')"
tm send-keys -t "$files" q
within "files q: review back in its place" 3 is_at "$review" hub.2
within "files q: no hidden window left" 2 no_window _cover
jay-sidebar --files
/bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh"; jay_hub_show_review'
within "files closed from outside: review back" 3 is_at "$review" hub.2
# e in review (jay-keys reads tuicr's status line through jay-mux): files.
key 0733
within "Ctrl g 3: review" 2 is_pane "$review"
key 65
within "e in review: files" 5 bash -c "tmux -L $SOCK list-panes -s -t =jay -F '#{pane_title}' | grep -q '^files ·'"
files=$(pane_by_title "files ·")
tm send-keys -t "$files" q
within "q in files: review back" 3 is_at "$review" hub.2

# Hide review and show it again (Ctrl g v twice).
before=$(tm display -p -t "$review" '#{pane_width}')
key 0776
within "hide: review in a hidden window" 3 bash -c "[[ \"\$(tmux -L $SOCK display -p -t $review '#{window_name}')\" == _review ]]"
within "hide: the agent takes its width" 2 bash -c "(( \$(tmux -L $SOCK display -p -t $agent '#{pane_width}') > 120 ))"
key 0776
within "show: review back right of the agent" 3 is_at "$review" hub.2
eq "show: its old width" "$before" "$(tm display -p -t "$review" '#{pane_width}')"

# Tasks: a window per worktree, the bar (sign, project, name; the picked worktree bright, no
# ports), the note of tasks elsewhere, the pane titles with ports, the picker.
wt=$TMP/projects/acme/shop.fix-login main=$TMP/projects/acme/shop
port1=$((20000 + RANDOM % 20000)) port2=$((20000 + RANDOM % 20000 + 1))
(cd "$wt" && jay run -n web -- python3 -m http.server "$port1" >/dev/null 2>&1)
(cd "$main" && jay run -n api -- python3 -m http.server "$port2" >/dev/null 2>&1)
within "run: a window for each worktree" 2 bash -c "$(declare -f has_window tm); SOCK=$SOCK; has_window 'shop/fix-login · acme' && has_window 'shop/main · acme'"
ok "run: wait" bash -c "cd '$wt' && jay run wait web -t 15"
ok "run 2: wait" bash -c "cd '$main' && jay run wait api -t 15"
ls=$(jay run ls 2>&1)
has "ls: running with its port" "running  $port1" "$ls"
has "ls: the console" "idle" "$ls"
hasnt "ls: not the hub's hidden windows" "_cover" "$ls"
# The status line: one line at the top; left (where), middle (agent counts), right (tasks).
hubw=$(tm list-windows -t =jay -F '#{window_id} #{window_name}' | awk '$2 == "hub" { print $1 }')
wid=$(tm list-windows -t =jay -F '#{window_id} #{window_name}' | awk '/fix-login/ { print $1 }')
wopt() { tm show -wv -t "$1" "$2" 2>/dev/null; }
wopt_has() { [[ "$(wopt "$1" "$2")" == *"$3"* ]]; }
plain() { perl -pe 's/#\[[^]]*\]//g'; }
eq "status: one line" on "$(tm show -gv status)"
eq "the config loads without errors" "" "$(tm show-messages 2>/dev/null | grep -i 'jay.conf:' | head -3)"
features=$'xterm*:clipboard:ccolour:cstyle:focus:title\nscreen*:title\nrxvt*:ignorefkeys
xterm-ghostty:RGB:extkeys:clipboard:focus:sync:hyperlinks:usstyle\nxterm*:RGB:extkeys'
ok "terminal-features: claude attach ran (it appends *:RGB)" screen_has "$agent" ATTACHED
eq "terminal-features: tmux's and jay's, no *:RGB of claude attach" "$features" "$(tm show -sv terminal-features)"
for _ in 1 2 3; do tm source-file "$HOME/.config/jay/tmux.conf"; done
eq "terminal-features: three reloads give the same list" "$features" "$(tm show -sv terminal-features)"
eq "status: at the top" top "$(tm show -gv status-position)"
within "status left: the tab you are on (hub) and the picked worktree" 5 bash -c "[[ \"\$(tmux -L $SOCK show -wv -t $hubw @jay_left | perl -pe 's/#\[[^]]*\]//g')\" == '◆ JAY › hub › shop/fix-login' ]]"
within "status middle: the agent counts" 5 wopt_has "$hubw" @jay_mid '3 idle'
ok "status middle: no count for the agent outside JAY_ROOTS (it works)" \
  bash -c "! tmux -L $SOCK show -wv -t $hubw @jay_mid | grep -q working"
within "status right: the picked worktree's task, bright" 8 wopt_has "$hubw" @jay_right '#[fg=colour2]●#[default] shop/fix-login web'
within "status right: the main checkout's, dim, the repo as project" 3 wopt_has "$hubw" @jay_right '#[dim]● shop api'
hasnt "status: no ports" "$port1" "$(wopt "$hubw" @jay_right)"
within "status left of a tasks window: its worktree and the tasks elsewhere" 5 bash -c "[[ \"\$(tmux -L $SOCK show -wv -t $wid @jay_left | perl -pe 's/#\[[^]]*\]//g')\" == '◆ JAY › tasks › shop/fix-login · acme · 1 running elsewhere: shop' ]]"
within "status: the client shows the line" 3 client_shows '◆ JAY ›'
# Cut to the width (a second terminal makes the windows its size): at 140 columns all fits; at
# 80 the other worktrees' tasks go first ("+1"), then the picked worktree's names (signs only).
right_plain() { wopt "$hubw" @jay_right | plain; }
right_is() { [[ "$(tm show -wv -t "$hubw" @jay_right | plain)" == "$1" ]]; }
for cols in 140 80 64; do
  /usr/bin/python3 -I "$REPO/tests/pty-client.py" "$TMP/client$cols.out" "$cols" 40 tmux -L "$SOCK" attach -t =jay &
  extra=$!
  within "status at $cols columns: the window's width" 5 bash -c "[[ \$(tmux -L $SOCK display -p -t $hubw '#{window_width}') == $cols ]]"
  case $cols in
    140) within "status at 140: all tasks with their names" 8 right_is '● shop/fix-login web  ● shop api'
         has "status at 140: the counts with their words" "3 idle" "$(wopt "$hubw" @jay_mid | plain)" ;;
    80) within "status at 80: first the other worktrees' tasks to +1" 8 right_is '● shop/fix-login web  +1' ;;
    64) within "status at 64: then the picked worktree's tasks to their signs" 8 right_is '●  +1'
        has "status at 64: the left part whole" "◆ JAY › hub › shop/fix-login" "$(wopt "$hubw" @jay_left | plain)" ;;
  esac
  kill "$extra" 2>/dev/null
  wait "$extra" 2>/dev/null
done
eq "tasks window: console and task side by side, as zellij's tab" "1 1" \
  "$(tm list-panes -t "$wid" -F '#{pane_top}' | sort -u | wc -l | tr -d ' ') $(tm list-panes -t "$wid" -F '#{pane_left}' | grep -c '^0$')"
eq "pane titles centered in the border, as zellij's frames" '#[align=centre] #{pane_title} ' "$(tm show -gv pane-border-format)"
within "pane title: name and ports" 4 bash -c "tmux -L $SOCK list-panes -s -t =jay -F '#{pane_title}' | grep -qx 'web · :$port1'"
has "ls: the name without the ports" "  web  " "$(jay run ls)"
has "log" "Serving" "$(jay run log web)"
key 0709; within "Ctrl g Tab: the picked worktree's tasks window" 3 is_window 'shop/fix-login · acme'
key 0709; within "Ctrl g Tab again: the hub" 3 is_window hub
key 0774; within "Ctrl g t: the tasks picker" 3 client_shows 'task ❯'
sleep 0.5
key 0d; within "picker, Enter: the task's window (shop first)" 3 is_window 'shop/main · acme'
key 0709; within "Ctrl g Tab from a tasks window: the hub" 3 is_window hub
# The launcher (Ctrl g r): a popup whose Enter types the line into the picked worktree's console.
key 0772; within "Ctrl g r: the launcher, titled with the worktree" 3 client_shows 'run in shop/fix-login'
sleep 0.5
key "$(printf 'echo launched-%s\r' "$$" | xxd -p | tr -d '\n')"
console=$(tm list-panes -t "$wid" -F '#{pane_id} #{pane_title}' | awk '$2 == "console" { print $1; exit }')
within "launcher: the line ran in the console" 5 screen_has "$console" "launched-$$"
# A command that ends: its output in a popup of its size (as zellij's launcher grows), until a key.
within "launcher: the output in a popup" 5 client_shows "any key: close"
within "launcher: the popup's title, worktree and line" 2 client_shows "shop/fix-login · acme: echo launched-$$"
popup_open() { tr -d '\000' <"$TMP/client.out" | tail -c 3000 | grep -q 'any key: close'; }
: >"$TMP/client.out"
key 71
sleep 1
ok "launcher: a key closes the output" bash -c "! grep -q 'any key: close' '$TMP/client.out'"
# A command that runs on: the launcher closes, no output popup.
key 0772; within "Ctrl g r again" 3 client_shows 'run in shop/fix-login'
sleep 0.5
: >"$TMP/client.out"
key "$(printf 'sleep 30\r' | xxd -p | tr -d '\n')"
sleep 3
ok "launcher, a command that runs on: no output popup" bash -c "! grep -q 'any key: close' '$TMP/client.out'"
within "launcher, a command that runs on: it runs in the console" 3 bash -c "tmux -L $SOCK list-panes -t $wid -F '#{pane_title}' | grep -qx sleep"
jay run stop api >/dev/null 2>&1
jay run stop web >/dev/null 2>&1
ok "run: stopped" bash -c "! lsof -nP -iTCP:$port1 -sTCP:LISTEN"
within "status: the agents" 5 wopt_has "$hubw" @jay_mid idle

# JAY_ORCHESTRATE=web: a pick of web's worktree row (as the list runs it) starts web's
# orchestrator. The middle column says so, then shows it; the focus stays in the list.
tm select-pane -t "$list"
TMUX="$TMUX_TMPDIR/tmux-$(id -u)/$SOCK,1,0" jay-sidebar --act wt "$TMP/projects/acme/web.fix"
within "orchestrate: the note in the middle" 3 screen_has "$agent" 'Starting the orchestrator of web (JAY_ORCHESTRATE)'
within "orchestrate: then the orchestrator" 8 screen_has "$agent" 'ATTACHED cccc0001'
eq "orchestrate: its title" web/main "$(tm display -p -t "$agent" '#{pane_title}')"
ok "orchestrate: the focus stays in the list" is_pane "$list"
has "orchestrate: the orchestrator prompt" "--name web/main --append-system-prompt You are the orchestrator of the repo web" "$(cat "$STUB/bg.calls")"
within "orchestrate: review on the picked worktree" 5 screen_has "$review" 'TUICR .*web.fix'

# The list, agent and review panes cannot be lost: fzf's quit keys do nothing, a program that
# ends starts again in its pane, and a pane that is closed comes back with Ctrl g 1 2 3 or jay.
list_fzf() { pgrep -P "$(tm display -p -t "$list" '#{pane_pid}')" -x fzf; }
pane_of() { tm list-panes -t =jay:hub -F '#{pane_id} #{@jay_role}' | awk -v r="$1" '$2 == r { print $1 }'; }
cols_are() { [[ "$(tm list-panes -t =jay:hub -F '#{@jay_role}' | tr '\n' ' ')" == "$1" ]]; }
respawned() { [[ "$(tm display -p -t "$1" '#{pane_dead}')" == 0 && "$(tm display -p -t "$1" '#{pane_pid}')" != "$2" ]]; }
width_near() { local w; w=$(tm display -p -t "$1" '#{pane_width}'); ((w >= $2 - 2 && w <= $2 + 2)); }
eq "roles of the hub window's panes" "list agent review " "$(tm list-panes -t =jay:hub -F '#{@jay_role}' | tr '\n' ' ')"
eq "role panes: remain-on-exit" "on on on" "$(tm list-panes -t =jay:hub -F '#{remain-on-exit}' | tr '\n' ' ' | sed 's/ $//')"
fzf_pid=$(list_fzf)
key 0731; within "Ctrl g 1: the list" 2 is_pane "$list"
key 1b; key 03; key 11; key 04; key 0707
sleep 1
eq "esc, Ctrl-C, Ctrl-Q, Ctrl-D, Ctrl g Ctrl g: fzf runs on" "$fzf_pid" "$(list_fzf)"
kill -9 "$fzf_pid"
within "fzf killed: the list says so" 3 screen_has "$list" 'The list ended'
within "fzf killed: the list starts again in its pane" 8 bash -c "[[ -n \"\$(pgrep -P \$(tmux -L $SOCK display -p -t $list '#{pane_pid}') -x fzf)\" ]]"
within "fzf killed: rows again" 10 screen_has "$list" fix-login
pid=$(tm display -p -t "$list" '#{pane_pid}')
pkill -9 -P "$pid"; kill -9 "$pid"
within "list program killed: the pane starts it again" 8 respawned "$list" "$pid"
within "list program killed: rows again" 10 screen_has "$list" fix-login
eq "list program killed: its title" worktrees "$(tm display -p -t "$list" '#{pane_title}')"
share=$(cat "$HOME/.local/state/jay/sidebar.pct" 2>/dev/null || echo 22)
tm kill-pane -t "$list"
key 0731
within "list closed, Ctrl g 1: a list again, left" 5 cols_are "list agent review "
list=$(pane_of list)
within "Ctrl g 1: the focus in the new list" 2 is_pane "$list"
eq "the new list: its title" worktrees "$(tm display -p -t "$list" '#{pane_title}')"
ok "the new list: its saved width" width_near "$list" $((200 * share / 100))
within "the new list: rows" 15 screen_has "$list" fix-login
tm kill-pane -t "$list"
jay >/dev/null 2>&1
within "list closed, jay: a list again, left" 5 cols_are "list agent review "
list=$(pane_of list)
within "jay: rows in the new list" 15 screen_has "$list" fix-login
# The agent: its program killed, its pane closed (Ctrl g 2, jay); it opens its agent again.
pid=$(tm display -p -t "$agent" '#{pane_pid}')
pkill -9 -P "$pid"; kill -9 "$pid"
within "agent program killed: the pane starts it again" 8 respawned "$agent" "$pid"
within "agent program killed: it opens the agent again" 8 screen_has "$agent" 'ATTACHED cccc0001'
tm kill-pane -t "$agent"
key 0732
within "agent closed, Ctrl g 2: an agent pane again, in the middle" 5 cols_are "list agent review "
agent=$(pane_of agent)
within "Ctrl g 2: the focus in it" 2 is_pane "$agent"
within "the new agent pane: the agent it showed" 8 screen_has "$agent" 'ATTACHED cccc0001'
eq "the new agent pane: its title" web/main "$(tm display -p -t "$agent" '#{pane_title}')"
tm kill-pane -t "$agent"
jay >/dev/null 2>&1
within "agent closed, jay: back in the middle" 5 cols_are "list agent review "
agent=$(pane_of agent)
within "jay: the agent it showed" 8 screen_has "$agent" 'ATTACHED cccc0001'
# Review: the same, also under files and while hidden.
pid=$(tm display -p -t "$review" '#{pane_pid}')
pkill -9 -P "$pid"; kill -9 "$pid"
within "review program killed: the pane starts it again" 8 respawned "$review" "$pid"
within "review program killed: tuicr again" 8 screen_has "$review" 'TUICR .*web.fix'
tm kill-pane -t "$review"
key 0733
within "review closed, Ctrl g 3: review again, right" 5 cols_are "list agent review "
review=$(pane_of review)
within "Ctrl g 3: the focus in it" 2 is_pane "$review"
within "the new review: its worktree" 8 screen_has "$review" 'TUICR .*web.fix'
within "the new review: its title" 3 bash -c "[[ \"\$(tmux -L $SOCK display -p -t $review '#{pane_title}')\" == 'turns · web'* ]]"
jay-sidebar --files
files=$(pane_by_title "files ·")
within "files over review" 5 screen_has "$files" YAZI
tm kill-pane -t "$review"
jay >/dev/null 2>&1
within "review closed under files, jay: files goes, review again" 5 cols_are "list agent review "
review=$(pane_of review)
within "jay: tuicr in the new review" 8 screen_has "$review" 'TUICR .*web.fix'
key 0776
within "hidden review" 3 bash -c "[[ \"\$(tmux -L $SOCK display -p -t $review '#{window_name}')\" == _review ]]"
jay >/dev/null 2>&1
eq "jay: a hidden review stays hidden" _review "$(tm display -p -t "$review" '#{window_name}')"
key 0776
within "shown again" 3 is_at "$review" hub.2
# The hub window closed (tasks windows left): jay makes it again.
if has_window 'shop/main · acme'; then
  tm kill-window -t =jay:hub
  jay >/dev/null 2>&1
  within "hub window closed, jay: list, agent, review again" 5 cols_are "list agent review "
  within "jay: rows in the new list" 15 screen_has "$(pane_of list)" fix-login
  within "jay: the agent it showed" 8 screen_has "$(pane_of agent)" 'ATTACHED cccc0001'
fi

# Cmd keys as Ghostty sends them (CSI 27, Super bit): Cmd+P and Cmd+O never reach a pane (tmux
# makes them Alt+P, Claude's model picker, and Alt+O, fast mode); Cmd+X does, as Alt+X. A DCS
# reply that tmux does not expect: its ESC P (M-P, Alt+P for Claude) does not, its text does.
tm new-window -d -n keys bash -c 'stty raw -echo; while IFS= read -rsn1 -d "" c; do printf %s "$c" | xxd -p >>"$1"; done' _ "$TMP/keys.got"
tm select-window -t =jay:keys
key 1b5b32373b393b3131327e; key 1b5b32373b393b3131317e; key 1b5b32373b393b3132307e
key "$(printf '\eP>|late\e\\' | xxd -p | tr -d '\n')"
got_keys() { tr -d '\n' <"$TMP/keys.got" 2>/dev/null; }
within "Cmd+X reaches the pane as Alt+X" 3 bash -c "$(declare -f got_keys); TMP=$TMP; [[ \$(got_keys) =~ 1b78|5b3132303b3375 ]]"
within "an unexpected DCS reply: its text reaches the pane" 3 bash -c "$(declare -f got_keys); TMP=$TMP; [[ \$(got_keys) == *3e7c6c617465* ]]"
eq "Cmd+P, Cmd+O and the reply's ESC P do not" "" "$(got_keys | grep -oE '5b3131(32|31)3b3375|5b38303b3375|1b(70|6f|50)')"
tm kill-window -t =jay:keys

# Ctrl g q: the client goes, the hub runs on.
key 0771
within "Ctrl g q: the client detaches" 3 bash -c "$(declare -f has_client tm); SOCK=$SOCK; ! has_client"
ok "Ctrl g q: the hub runs on" tm has-session -t =jay
finish

#!/bin/bash
# A throwaway tmux hub (JAY_MUX=tmux): `jay` starts it in a pty (tests/pty-client.py) on a
# socket of its own, in the fake HOME, with a stub claude (attach keeps its args, ← is the agent
# view), stub tuicr and yazi. It checks the layout, a pick (also over Claude's agent view), the
# focus keys, files over review and back, hide and show review, tasks windows, the bar and its
# note, the tasks picker and Ctrl g q. The server is killed at the end. About a minute.
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
export JAY_MUX=tmux JAY_TMUX_SOCKET=$SOCK JAY_SESSION=jay TMUX_TMPDIR="$TMP/tsock" TERM=xterm-256color
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
  \"cwd\":\"$TMP/projects\",\"state\":\"working\",\"status\":\"idle\",\"startedAt\":$now,\"pid\":1}]"
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
within "the focus starts in the middle" 2 is_pane "$agent"

# A pick: the agent in the middle (Opening at once), its worktree in review, the banner.
jay go aaaa0001
within "pick: Opening <name>" 3 screen_has "$agent" 'Opening fix-login'
within "pick: the agent attached" 5 screen_has "$agent" 'ATTACHED aaaa0001'
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

# Ctrl g keys.
key 0731; within "Ctrl g 1: the list" 2 is_pane "$list"
key 0733; within "Ctrl g 3: review" 2 is_pane "$review"
key 0732; within "Ctrl g 2: the agent" 2 is_pane "$agent"
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
within "bar: the picked worktree's task, bright" 8 option_has @jay_tasks '#[fg=colour2]●#[default] shop/fix-login web'
within "bar: the main checkout's, dim, the repo as project" 3 option_has @jay_tasks '#[dim]● shop api'
hasnt "bar: no ports" "$port1" "$(tm show -gv @jay_tasks)"
wid=$(tm list-windows -t =jay -F '#{window_id} #{window_name}' | awk '/fix-login/ { print $1 }')
within "note: the fix-login window names the task elsewhere" 3 bash -c "[[ \"\$(tmux -L $SOCK show -wv -t $wid @jay_note)\" == '1 running elsewhere: shop' ]]"
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
key 71
within "launcher: closed" 3 bash -c "! tmux -L $SOCK display -p '#{popup_active}' 2>/dev/null | grep -q 1"
jay run stop api >/dev/null 2>&1
jay run stop web >/dev/null 2>&1
ok "run: stopped" bash -c "! lsof -nP -iTCP:$port1 -sTCP:LISTEN"
within "bar: the agents" 5 option_has @jay_agents idle

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

# Ctrl g q: the client goes, the hub runs on.
key 0771
within "Ctrl g q: the client detaches" 3 bash -c "$(declare -f has_client tm); SOCK=$SOCK; ! has_client"
ok "Ctrl g q: the hub runs on" tm has-session -t =jay
finish

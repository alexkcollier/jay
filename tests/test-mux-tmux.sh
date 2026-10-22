#!/bin/bash
# The mux layer's tmux backend (lib/jay-mux-tmux.sh, JAY_MUX=tmux): the tmux calls it makes on
# jay's own server, the pane and tab lists it gives back, the bar's styles; and the bar text of
# jay run (both backends). A stub tmux records each call and answers from $STUB/panes.txt and
# $STUB/windows.txt.
source "$(dirname "$0")/lib.sh"
link_install
export JAY_MUX=tmux JAY_SESSION=jaytest JAY_TMUX_SOCKET=jaytest-sock
stub tmux '
args=" $* "
case "$args" in
  *" list-panes "*) cat "$STUB/panes.txt" ;;
  *" list-windows "*) cat "$STUB/windows.txt" ;;
  *" list-clients "*) [[ -f "$STUB/clients.txt" ]] && cat "$STUB/clients.txt" ;;
  *" has-session "*) [[ -f "$STUB/alive" ]] ;;
  *" new-window "*) echo %9 ;;
  *" display-message "*"@jay_covers"*) echo %2 ;;
  *" display-message "*"window_name"*) echo "_review @7" ;;
  *" capture-pane "*) printf "screen of the pane\n" ;;
esac'
# id, window, window id, left, width, active, window active, dead, dead status, pid, cwd,
# command, title, start command (tabs between them).
t=$'\t'
cat >"$STUB/panes.txt" <<EOF
%0${t}hub${t}@0${t}0${t}40${t}0${t}1${t}0${t}${t}101${t}/w${t}bash${t}worktrees${t}/h/.local/bin/jay-sidebar
%1${t}hub${t}@0${t}41${t}86${t}1${t}1${t}0${t}${t}102${t}/w/shop${t}bash${t}fix-login${t}/h/.local/bin/jay-pane agent
%3${t}hub${t}@0${t}128${t}72${t}0${t}1${t}0${t}${t}103${t}/w/shop${t}bash${t}files · shop${t}/h/.local/bin/jay-pane files
%2${t}_cover${t}@4${t}0${t}200${t}1${t}0${t}0${t}${t}104${t}/w/shop${t}bash${t}turns · shop${t}/h/.local/bin/jay-pane review
%5${t}shop/main · acme${t}@5${t}0${t}200${t}1${t}0${t}0${t}${t}105${t}/w/shop${t}zsh${t}console${t}
%6${t}shop/main · acme${t}@5${t}0${t}200${t}0${t}0${t}1${t}1${t}106${t}/w/shop${t}node${t}web${t}/h/.local/bin/jay-run --exec "pnpm dev --port 5173"
EOF
cat >"$STUB/windows.txt" <<EOF
@0${t}hub${t}1
@4${t}_cover${t}0
@5${t}shop/main · acme${t}0
EOF
source "$HOME/.local/lib/jay-lib.sh"
calls() { cat "$STUB/tmux.calls" 2>/dev/null; }
reset() { rm -f "$STUB/tmux.calls"; }

eq "the tmux backend" tmux "$JAY_MUX"
eq "its own hub state" "$JAY_STATE/tmux" "$JAY_HUB_STATE"
eq "jay's own server and config" "-L jaytest-sock -f $HOME/.config/jay/tmux.conf has-session -t =jaytest" "$(reset; jay_mux_alive; calls)"
no "alive: no session" jay_mux_alive
: >"$STUB/alive"
ok "alive: the session" jay_mux_alive

# Panes.
panes=$(jay_mux_panes)
eq "panes: all of the session" 6 "$(wc -l <<<"$panes" | tr -d ' ')"
eq "panes: id and number" "%1 1" "$(jq -r 'select(.title == "fix-login") | "\(.pane) \(.n)"' <<<"$panes")"
eq "panes: a hidden window's pane is the hub's, hidden" "hub true" "$(jq -r 'select(.pane == "%2") | "\(.tab) \(.hidden)"' <<<"$panes")"
eq "panes: focused only in the active window" "%1" "$(jq -r 'select(.focused) | .pane' <<<"$panes")"
eq "panes: launch without tmux's quotes" '/h/.local/bin/jay-run --exec pnpm dev --port 5173' "$(jq -r 'select(.pane == "%6") | .launch' <<<"$panes")"
eq "panes: no start command is null" null "$(jq -r 'select(.pane == "%5") | .launch' <<<"$panes")"
eq "panes: dead with its status" "true 1" "$(jq -r 'select(.pane == "%6") | "\(.exited) \(.exit)"' <<<"$panes")"
eq "panes: pid" 102 "$(jq -r 'select(.pane == "%1") | .pid' <<<"$panes")"

# Tabs: windows, the hidden ones left out.
eq "tabs: no hidden window" "@0 @5" "$(jay_mux_tabs | jq -r .id | paste -sd' ' -)"
eq "tabs: id by name (a name with dots and spaces)" "@5" "$(jay_mux_tab_id 'shop/main · acme')"
eq "tabs: active" hub "$(jay_mux_active_tab)"
reset; jay_mux_tab_go 'shop/main · acme'
eq "tab go by name: by its id" "-L jaytest-sock -f $HOME/.config/jay/tmux.conf list-windows -t =jaytest -F #{window_id}	#{window_name}	#{window_active}
-L jaytest-sock -f $HOME/.config/jay/tmux.conf select-window -t @5" "$(calls)"

# Self: TMUX_PANE only on jay's server, never in a popup.
eq "self: outside" "" "$(jay_mux_self)"
eq "self: another tmux server" "" "$(TMUX=/tmp/tmux-501/default,1,0 TMUX_PANE=%4 jay_mux_self)"
eq "self: jay's server" "%4" "$(TMUX=/tmp/tmux-501/jaytest-sock,1,0 TMUX_PANE=%4 jay_mux_self)"
eq "self: a popup" "" "$(JAY_POPUP=1 TMUX=/tmp/tmux-501/jaytest-sock,1,0 TMUX_PANE=%4 jay_mux_self)"
ok "in the hub: on jay's server" env TMUX=/tmp/tmux-501/jaytest-sock,1,0 /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh"; jay_in_hub'
no "in the hub: not from an agent" env TMUX=/tmp/tmux-501/jaytest-sock,1,0 CLAUDE_JOB_DIR=/x /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh"; jay_in_hub'

# Calls.
reset
jay_mux_rename %1 "fix-login"
jay_mux_type %5 $'\x05\x15 pnpm dev\r'
jay_mux_read %5 --full >/dev/null
jay_mux_close %6
jay_mux_focus agent
has "rename" "select-pane -t %1 -T fix-login" "$(calls)"
has "type: literal" "send-keys -t %5 -l" "$(calls)"
has "read --full: the scrollback" "capture-pane -p -t %5 -S -" "$(calls)"
has "close" "kill-pane -t %6" "$(calls)"
has "focus: the hub window's middle pane" "select-window -t =jaytest:hub ; select-pane -t =jaytest:hub.1" "$(calls)"
reset
jay_mux_rename "" x
eq "rename of no pane: no call (tmux would take the active one)" "" "$(calls)"

# Cover and uncover: files over review through a hidden window.
reset
eq "cover: the new pane" %9 "$(jay_mux_cover %2 "files · shop" /w/shop "$HOME/.local/bin/jay-pane" files)"
has "cover: a hidden window" "new-window -d -t =jaytest: -n _cover -c /w/shop -P -F #{pane_id} $HOME/.local/bin/jay-pane files" "$(calls)"
has "cover: swapped into review's place, with its record" "set-option -p -t %9 @jay_covers %2 ; swap-pane -d -s %9 -t %2" "$(calls)"
reset
jay_mux_uncover %3
has "uncover: review back" "swap-pane -d -s %3 -t %2" "$(calls)"
has "uncover: files closed" "kill-pane -t %3" "$(calls)"

# Hidden review: its window is _review.
eq "review hidden: its window" "@7" "$(jay_mux_review_hidden %2)"

# Bar: ANSI colors become tmux styles, # doubled.
reset
jay_mux_bar tasks $'\e[32m●\e[0m shop web  \e[2m○ shop/fix #1\e[0m'
has "bar: styles" "set-option -g @jay_tasks #[fg=colour2]●#[default] shop web  #[dim]○ shop/fix ##1#[default]" "$(calls)"
jay_mux_tab_note @5 "1 running elsewhere: shop"
has "tab note: the window's own" "set-option -w -t @5 @jay_note 1 running elsewhere: shop" "$(calls)"

# Tasks tab: a window with the worktree as its banner label and a console.
reset
eq "tab new: its id" %9 "$(jay_mux_tab_new 'shop/main · acme' /w/shop)"
has "tab new: no focus" "new-window -d -t =jaytest: -n shop/main · acme -c /w/shop" "$(calls)"
has "tab new: banner label" "@jay_wt shop/main · acme" "$(calls)"

# The bar text (jay run --bar, both backends): sign, project, name; the picked worktree first and
# bright, the others dim; no ports. The note: the tasks that run in other worktrees.
cat >"$TMP/tasks.json" <<'JSON'
[{"name": "api", "project": "shop", "top": "/w/shop", "state": "running", "ports": [3000]},
 {"name": "web", "project": "shop/fix-login", "top": "/w/shop.fix-login", "state": "running", "ports": [5173]},
 {"name": "test", "project": "shop/fix-login", "top": "/w/shop.fix-login", "state": "exited", "exit": 1, "ports": []},
 {"name": "shell", "project": "shop", "top": "/w/shop", "state": "idle", "ports": []},
 {"name": "db", "project": "acme-api", "top": "/w/acme-api", "state": "running", "ports": [5432]}]
JSON
bar=$(jay-run --bar "$TMP/tasks.json" /w/shop.fix-login)
eq "bar: picked first and bright, others dim, no ports" \
  $'\e[32m●\e[0m shop/fix-login web  \e[31m✗\e[0m shop/fix-login test  \e[2m● shop api\e[0m  \e[2m● acme-api db\e[0m' "$bar"
hasnt "bar: no idle shells" "shell" "$bar"
eq "note: tasks elsewhere, by project" "2 running elsewhere: acme-api, shop" "$(jay-run --note "$TMP/tasks.json" /w/shop.fix-login)"
jq 'map(.state = "running")' "$TMP/tasks.json" >"$TMP/all-running.json"
eq "note: a count per project" "3 running elsewhere: acme-api, shop/fix-login (2)" "$(jay-run --note "$TMP/all-running.json" /w/shop)"
jq 'map(select(.top == "/w/shop"))' "$TMP/tasks.json" >"$TMP/only-shop.json"
eq "note: none elsewhere" "" "$(jay-run --note "$TMP/only-shop.json" /w/shop)"

finish

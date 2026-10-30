#!/bin/bash
# The mux layer (jay_mux_* in lib/jay-mux-zellij.sh): the zellij calls it makes, the pane and tab
# lists it gives back, and the hub functions on top of it. A stub zellij records each call and
# answers from $STUB/panes.json and $STUB/tabs.json.
source "$(dirname "$0")/lib.sh"
link_install
export JAY_SESSION=jaytest
stub zellij '
case "$*" in
  "list-sessions"*) echo "jaytest [Created 1m ago]" ;;
  *" action list-clients") printf "CLIENT_ID ZELLIJ_PANE_ID RUNNING_COMMAND\n1 terminal_1 x\n" ;;
  *" action list-panes"*) [[ -f "$STUB/panes.fail" ]] && { echo nope; exit 0; }; cat "$STUB/panes.json" ;;
  *" action list-tabs"*) cat "$STUB/tabs.json" ;;
  *" action new-pane"* | *" action new-tab"*) echo terminal_9 ;;
  *" action dump-screen"*) if [[ -f "$STUB/screen" ]]; then cat "$STUB/screen"; else printf "line one\nNORMAL mode\n"; fi ;;
  # As zellij: a pipe waits while its stdin is open; with $STUB/pipe.hang, for good.
  *" pipe "*) cat >/dev/null; [[ -f "$STUB/pipe.hang" ]] && exec sleep 30 ;;
esac
exit 0'
cat >"$STUB/panes.json" <<'JSON'
[
  {"id": 0, "is_plugin": true, "title": "zjstatus", "tab_id": 0, "tab_name": "hub"},
  {"id": 1, "is_plugin": false, "title": "worktrees", "tab_id": 0, "tab_name": "hub", "pane_x": 0,
   "pane_columns": 40, "terminal_command": "/h/.local/bin/jay-sidebar", "pane_command": "fzf",
   "pane_cwd": "/w", "is_focused": true, "is_floating": false, "is_suppressed": false, "exited": false},
  {"id": 2, "is_plugin": false, "title": "hub", "tab_id": 0, "tab_name": "hub", "pane_x": 40,
   "pane_columns": 86, "terminal_command": "/h/.local/bin/jay-pane agent", "pane_command": null,
   "pane_cwd": "/w", "is_focused": false, "is_floating": false, "is_suppressed": false},
  {"id": 3, "is_plugin": false, "title": "review", "tab_id": 0, "tab_name": "hub", "pane_x": 126,
   "pane_columns": 74, "terminal_command": "/h/.local/bin/jay-pane review", "pane_command": "tuicr",
   "pane_cwd": "/w", "is_focused": false, "is_floating": false, "is_suppressed": true, "exited": false,
   "exit_status": null}
]
JSON
cat >"$STUB/tabs.json" <<'JSON'
[{"tab_id": 0, "name": "hub", "active": false}, {"tab_id": 4, "name": "shop/main", "active": true}]
JSON
source "$HOME/.local/lib/jay-lib.sh"
calls() { cat "$STUB/zellij.calls" 2>/dev/null; }
reset() { rm -f "$STUB/zellij.calls"; }

eq "the zellij backend" zellij "$JAY_MUX"

# Panes: no plugins; ids, launch and running commands, hidden (suspended) panes.
panes=$(jay_mux_panes)
eq "panes: three, no plugin" 3 "$(wc -l <<<"$panes" | tr -d ' ')"
eq "panes: pane id and number" "terminal_2 2" "$(jq -r 'select(.title == "hub") | "\(.pane) \(.n)"' <<<"$panes")"
eq "panes: launch command" "/h/.local/bin/jay-pane review" "$(jq -r 'select(.n == 3) | .launch' <<<"$panes")"
eq "panes: running command, null when zellij has none" "fzf null" "$(jq -rs '[.[0].command, .[1].command] | map(tostring) | join(" ")' <<<"$panes")"
eq "panes: suspended is hidden" "false true" "$(jq -rs 'map(.hidden) | .[1:] | map(tostring) | join(" ")' <<<"$panes")"
eq "panes: geometry" "126 74" "$(jq -r 'select(.n == 3) | "\(.x) \(.cols)"' <<<"$panes")"
: >"$STUB/panes.fail"
no "panes: fails when zellij gives no list" jay_mux_panes
rm -f "$STUB/panes.fail"

# Tabs.
eq "tabs: id of a name" 4 "$(jay_mux_tab_id shop/main)"
eq "tabs: the active one" shop/main "$(jay_mux_active_tab)"

# The calls, each to the hub's session.
reset
jay_mux_rename terminal_3 "turns · shop"
jay_mux_type terminal_3 '('
jay_mux_close terminal_9
jay_mux_bar agents "1 working"
jay_mux_tab_go hub
jay_mux_tab_go_id 4
jay_mux_tab_close 4
has "rename" "-s jaytest action rename-pane -p terminal_3 turns · shop" "$(calls)"
has "type" "-s jaytest action write-chars -p terminal_3 (" "$(calls)"
has "close" "-s jaytest action close-pane --pane-id terminal_9" "$(calls)"
has "status line: the counts in the middle pipe" "-s jaytest pipe zjstatus::pipe::pipe_mid::1 working" "$(calls)"
has "status line: the right pipe" "-s jaytest pipe zjstatus::pipe::pipe_right::" "$(calls)"
has "tab by name" "-s jaytest action go-to-tab-name hub" "$(calls)"
has "tab by id" "-s jaytest action go-to-tab-by-id 4" "$(calls)"
has "close tab" "-s jaytest action close-tab-by-id 4" "$(calls)"
reset
jay_mux_bar where shop/fix-login
has "status line: the picked worktree, left" "-s jaytest pipe zjstatus::pipe::pipe_where::shop/fix-login" "$(calls)"
reset
jay_mux_bar note "1 running elsewhere: shop"
has "status line: the note of the tasks tabs" "-s jaytest pipe zjstatus::pipe::pipe_note:: · 1 running elsewhere: shop" "$(calls)"
# A pipe does not wait on the caller's stdin, and a pipe that hangs (its session gone or stalled)
# gives up after the timeout.
mkfifo "$TMP/stdin"
sleep 20 >"$TMP/stdin" &
open=$!
start=$SECONDS
jay_mux_bar where shop/a <"$TMP/stdin"
took=$((SECONDS - start))
ok "status line: stdin open, no wait (took $took s)" test "$took" -le 1
kill "$open"
wait "$open" 2>/dev/null
: >"$STUB/pipe.hang"
start=$SECONDS
JAY_ZELLIJ_PIPE_TIMEOUT=1 jay_mux_bar agents "1 working"
took=$((SECONDS - start))
ok "status line: a hung pipe gives up (2 pipes, 1 s each; took $took s)" test "$took" -le 3
rm -f "$STUB/pipe.hang"
eq "read" "line one
NORMAL mode" "$(jay_mux_read terminal_3)"
reset
jay_mux_read terminal_3 --full >/dev/null
eq "read --full" "-s jaytest action dump-screen -p terminal_3 --full" "$(calls)"

# Cover: files over review, in place; the new pane's id comes back.
reset
eq "cover: new pane id" terminal_9 "$(jay_mux_cover terminal_3 "files · shop" /w "$HOME/.local/bin/jay-pane" files)"
eq "cover: in place over review" "-s jaytest action new-pane --in-place --pane-id terminal_3 --close-on-exit --name files · shop --cwd /w -- $HOME/.local/bin/jay-pane files" "$(calls)"
no "cover: review is suspended, not shown" env JAY_SESSION=jaytest /bin/bash -c 'source "$HOME/.local/lib/jay-lib.sh"; jay_mux_wait_shown terminal_3'
ok "wait shown: a shown pane" jay_mux_wait_shown terminal_2

# Focus: from anywhere, the hub tab and relative moves; from the list, only moves right.
reset
jay_mux_focus agent
eq "focus agent" "-s jaytest action go-to-tab-name hub
-s jaytest action move-focus left
-s jaytest action move-focus left
-s jaytest action move-focus right" "$(calls)"
reset
jay_mux_focus review list
eq "focus review from the list" "-s jaytest action move-focus right
-s jaytest action move-focus right" "$(calls)"

# Self and the jay-mux command.
eq "self outside a pane" "" "$(jay_mux_self)"
eq "self" terminal_7 "$(ZELLIJ_PANE_ID=7 jay_mux_self)"
reset
ZELLIJ_PANE_ID=7 jay-mux rename self "run in shop"
eq "jay-mux: self is the caller's pane" "-s jaytest action rename-pane -p terminal_7 run in shop" "$(calls)"
eq "jay-mux: an unknown name" 2 "$(jay-mux nothing >/dev/null 2>&1; echo $?)"

# Tasks tab: a layout with the banner, the console in the worktree and the bar; no CLAUDE vars.
reset
eq "tab new: its id" 4 "$(CLAUDE_X=1 jay_mux_tab_new shop/main "/w/shop")"
has "tab new: no focus, named, in the worktree" "action new-tab --no-focus --layout" "$(calls)"
has "tab new: name and cwd" "--name shop/main --cwd /w/shop" "$(calls)"
reset
eq "tab pane: its id" terminal_9 "$(jay_mux_tab_pane 4 web /w/shop jay-run --exec "pnpm dev")"
eq "tab pane: the call" "-s jaytest action new-pane --tab-id 4 --cwd /w/shop --name web --close-on-exit -- jay-run --exec pnpm dev" "$(calls)"
eq "without claude: vars gone" "" "$(CLAUDE_X=1 ANTHROPIC_Y=2 jay_without_claude /bin/bash -c 'echo "${CLAUDE_X:-}${ANTHROPIC_Y:-}"')"

# The hub on top: a pane record of an older version (a bare number) is that zellij pane.
exec -a "jay-pane agent" sleep 30 &
pid=$!
printf '2\t%s\n' "$pid" >"$(jay_hub_pane_file agent)"
eq "role: an old record" "terminal_2	$pid" "$(jay_hub_role agent)"
jay_hub_pane_record terminal_2 agent "$pid"
eq "role record: the bare number" "2	$pid" "$(cat "$(jay_hub_pane_file agent)")"
reset
printf 'old\tx\n' >"$(jay_hub_target_file agent)"
eq "show: the pane changes" "terminal_2" "$(jay_hub_show aaaa0001 "fix login" /w >/dev/null; jay_hub_role agent | cut -f1)"
has "show: renamed" "rename-pane -p terminal_2 fix login" "$(calls)"
has "show: focus to the agent" "move-focus right" "$(calls)"
eq "show: the target line" "aaaa0001	/w	background	fix login" "$(cat "$(jay_hub_target_file agent)")"
# The same agent again while no `claude attach` of it runs under the pane (the agent view, say):
# it opens again.
rm -f "$JAY_HUB_STATE/agent.again"
eq "same agent, not attached: restart" "terminal_2	1" "$(jay_hub_point agent "$(printf 'aaaa0001\t/w\tbackground\tfix login')")"
ok "same agent, not attached: the again file" test -f "$JAY_HUB_STATE/agent.again"
rm -f "$JAY_HUB_STATE/agent.again"
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
# A pane whose jay-pane runs `claude attach aaaa0001`: no restart, unless its screen is Claude's
# agent view.
mkdir -p "$TMP/fake"
cat >"$TMP/fake/jay-pane" <<'SH'
#!/bin/bash
# a jay-pane agent: its child is a `claude attach <id>`
"${0%/*}/claude" attach aaaa0001 &
wait 2>/dev/null
SH
printf '#!/bin/bash\nsleep 30\n' >"$TMP/fake/claude"
chmod +x "$TMP/fake/jay-pane" "$TMP/fake/claude"
"$TMP/fake/jay-pane" agent &
pid=$!
sleep 0.3
printf '2\t%s\n' "$pid" >"$(jay_hub_pane_file agent)"
eq "same agent, attached: no restart" "terminal_2	0" "$(jay_hub_point agent "$(printf 'aaaa0001\t/w\tbackground\tfix login')")"
printf 'Needs input\n enter to return · space to reply · ctrl+x to delete\n' >"$STUB/screen"
eq "same agent, agent view on screen: restart" "terminal_2	1" "$(jay_hub_point agent "$(printf 'aaaa0001\t/w\tbackground\tfix login')")"
rm -f "$STUB/screen" "$JAY_HUB_STATE/agent.again"
pkill -P "$pid" 2>/dev/null
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

# The list's width in columns (sidebar.cols): the same in any window, at most 60 % of it.
rm -f "$JAY_STATE/sidebar.cols" "$JAY_STATE/sidebar.pct"
eq "list width: the default" 44 "$(jay_list_cols)"
eq "widths: the default in 200 columns" "44 86 70" "$(jay_hub_widths 200)"
eq "widths: no window width, 200" "44 86 70" "$(jay_hub_widths)"
printf '30\n' >"$JAY_STATE/sidebar.cols"
eq "widths: saved columns in 200 columns" "30 93 77" "$(jay_hub_widths 200)"
eq "widths: the same columns in 120" "30 49 41" "$(jay_hub_widths 120)"
printf '100\n' >"$JAY_STATE/sidebar.cols"
eq "list width: at most 60 % of the window" 90 "$(jay_list_cols 150)"
eq "list width: the saved one with no window" 100 "$(jay_list_cols)"
printf '5\n' >"$JAY_STATE/sidebar.cols"
eq "list width: at least 24" 24 "$(jay_list_cols 200)"
jay_list_save 10
eq "save: at least 24" 24 "$(cat "$JAY_STATE/sidebar.cols")"
jay_list_save 52
eq "save: the columns" 52 "$(cat "$JAY_STATE/sidebar.cols")"
jay_list_save abc
eq "save: no number, no change" 52 "$(cat "$JAY_STATE/sidebar.cols")"
# An older jay's sidebar.pct: columns of the first window width it meets, once.
rm -f "$JAY_STATE/sidebar.cols"
printf '30\n' >"$JAY_STATE/sidebar.pct"
eq "sidebar.pct, no window: the default" 44 "$(jay_list_cols)"
ok "sidebar.pct, no window: it stays" test -f "$JAY_STATE/sidebar.pct"
eq "sidebar.pct: columns of the window" 54 "$(jay_list_cols 180)"
eq "sidebar.pct: saved as columns" 54 "$(cat "$JAY_STATE/sidebar.cols")"
ok "sidebar.pct: removed" test ! -e "$JAY_STATE/sidebar.pct"
eq "sidebar.pct: the columns stay in another window" 54 "$(jay_list_cols 250)"
rm -f "$JAY_STATE/sidebar.cols"
printf '80\n' >"$JAY_STATE/sidebar.pct"
eq "sidebar.pct out of range: the default" 44 "$(jay_list_cols 200)"
rm -f "$JAY_STATE/sidebar.pct"

# The list's width and its fit (the stub's list: 40 of 200 columns; zellij resizes in steps of
# 5 % of the tab, so a fit stops within 3 %: 6 columns).
eq "list width: list and tab" "40 200" "$(ZELLIJ_PANE_ID=1 jay_mux_list_width)"
reset
eq "fit: prints the list's width and the tab's at its last look" "40 200" "$(jay_mux_fit_list 46)"
ok "fit: within 3 % of the tab, no resize" bash -c "! grep -q 'action resize' '$STUB/zellij.calls'"
jay_mux_fit_list 60 >/dev/null
has "fit: wider" "-s jaytest action resize -p terminal_1 increase right" "$(calls)"
reset
jay_mux_fit_list 25 >/dev/null
has "fit: narrower" "-s jaytest action resize -p terminal_1 decrease right" "$(calls)"

# The list's tick (keep_width in jay-sidebar) compares the next look with the fit's own last look.
# The stubs keep the list's and the window's widths in $T (a fit runs in a subshell); a fit sets
# the list and prints its last look, and then (with $T/after) the window or the list changes: a
# new window size (zellij scales the list) or a drag.
# tick_fits [window <width> | drag <columns>]: three ticks (at the start, in a window of 150, once
# more), the change after the second fit; prints the number of fits and the list's width.
T=$STUB/tick
tick_fits() {
  (
    eval "$(sed -n '/^last_win="" last_list=""$/p; /^keep_width() {$/,/^}$/p' "$REPO/bin/jay-sidebar")"
    jay_mux_list_width() { echo "$(<"$T/l") $(<"$T/w")"; }
    jay_mux_fit_list() {
      local look kind n
      echo "$(($(<"$T/fits") + 1))" >"$T/fits"
      echo "$1" >"$T/l"
      look="$1 $(<"$T/w")"
      if [[ -f "$T/after" ]]; then
        read -r kind n <"$T/after"
        rm -f "$T/after"
        case $kind in
          window) echo "$(($1 * n / $(<"$T/w")))" >"$T/l"; echo "$n" >"$T/w" ;;
          drag) echo "$n" >"$T/l" ;;
        esac
      fi
      echo "$look"
    }
    rm -rf "$T"
    mkdir -p "$T"
    echo 0 >"$T/fits"; echo 44 >"$T/l"; echo 200 >"$T/w"
    keep_width >/dev/null
    echo 33 >"$T/l"; echo 150 >"$T/w"
    [[ -z "${1:-}" ]] || echo "$1 $2" >"$T/after"
    keep_width >/dev/null
    keep_width >/dev/null
    echo "$(<"$T/fits") $(<"$T/l")"
  )
}
rm -f "$JAY_STATE/sidebar.cols"
eq "tick: a fit at the start and at a new window width" "2 44" "$(tick_fits)"
eq "tick: the window changes again during a fit: a fit at the next tick" "3 44" "$(tick_fits window 250)"
eq "tick: a new window width saves nothing" "" "$(cat "$JAY_STATE/sidebar.cols" 2>/dev/null)"
eq "tick: a drag during a fit: a fit at the next tick" "3 60" "$(tick_fits drag 60)"
eq "tick: a drag during a fit: saved at the next tick" 60 "$(cat "$JAY_STATE/sidebar.cols" 2>/dev/null)"
rm -f "$JAY_STATE/sidebar.cols"

# Layout: the list at its saved columns, as % of the session's width (200 in the stub).
printf '60\n' >"$JAY_STATE/sidebar.cols"
has "layout: list at its columns" 'pane size="30%" name="worktrees"' "$(jay --print-layout)"
has "layout: agent and review 43:35 of the rest" 'pane size="38%" name="hub"' "$(jay --print-layout)"
has "layout: the agent pane" 'args "agent"' "$(jay --print-layout)"
has "layout without zjstatus: the compact bar" 'zellij:compact-bar' "$(jay --print-layout)"
mkdir -p "$HOME/.local/share/jay" && : >"$HOME/.local/share/jay/zjstatus-v0.25.0.wasm"
layout=$(jay --print-layout)
eq "layout: one status line, no other bar" 1 "$(grep -c 'plugin location' <<<"$layout")"
ok "layout: the status line first, at the top" bash -c "grep -n 'plugin location\|split_direction' <<<'$layout' | head -1 | grep -q plugin"
has "layout: its left part, the tab you are on" '◆ JAY › hub ›#[fg=default,nobold] {pipe_where}#[default]' "$layout"
has "layout: counts, then tasks and time" '{pipe_mid}' "$layout"
has "layout: tasks and time on the right" 'format_right  "{pipe_right}  #[fg=#727169]{datetime} "' "$layout"
tasks_layout=$(jay --print-tasks-tab /w/shop 'shop/main · acme')
has "tasks tab: its left part" '◆ JAY › tasks ›#[fg=default,nobold] shop/main · acme{pipe_note}#[default]' "$tasks_layout"
eq "tasks tab: one status line" 1 "$(grep -c 'plugin location' <<<"$tasks_layout")"
rm -f "$HOME/.local/share/jay/zjstatus-v0.25.0.wasm"

# jay run --where: the status line gets the picked worktree.
repo "$TMP/w/shop"
reset
jay-run --where "$TMP/w/shop"
has "where: the status line's left part" "-s jaytest pipe zjstatus::pipe::pipe_where::shop/main" "$(calls)"

finish

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

eq "the zellij backend is the default" zellij "$JAY_MUX"

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
has "bar" "-s jaytest pipe zjstatus::pipe::pipe_agents::1 working" "$(calls)"
has "tab by name" "-s jaytest action go-to-tab-name hub" "$(calls)"
has "tab by id" "-s jaytest action go-to-tab-by-id 4" "$(calls)"
has "close tab" "-s jaytest action close-tab-by-id 4" "$(calls)"
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

# Layout: the list keeps its width.
printf '30\n' >"$JAY_STATE/sidebar.pct"
eq "widths" "30 38 32" "$(jay_hub_widths)"
has "layout: list at its share" 'pane size="30%" name="worktrees"' "$(jay --print-layout)"
has "layout: the agent pane" 'args "agent"' "$(jay --print-layout)"

# jay run --where: the banner gets the picked worktree.
repo "$TMP/w/shop"
reset
jay-run --where "$TMP/w/shop"
eq "where: the banner" "-s jaytest pipe zjstatus::pipe::pipe_where::shop/main" "$(calls)"

finish

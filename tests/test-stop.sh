#!/bin/bash
# Idle agents stop (lib/jay-lib.sh): the setting JAY_AUTO_STOP, the child processes of an agent
# (jay_agent_children), the middle column of both hubs (jay_hubs_shown), the stop rule
# (jay_stop_plan, one check for each condition), jay_auto_stop, the list's auto step
# (jay_stop_auto), the respawn step after it, and `jay wake`.
source "$(dirname "$0")/lib.sh"
link_install
export JAY_ROOTS=$TMP
source "$HOME/.local/lib/jay-lib.sh"

# claude: `agents --json` prints $STUB/agents.json; `stop` and `respawn` answer like Claude and
# fail when $STUB/<command>.fail is there; a respawn gives the agent a pid in agents.json.
stub claude '
case "${1:-} ${2:-}" in
  "--version "*) echo "2.1.309 (Claude Code)" ;;
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "stop "*) [[ -f "$STUB/stop.fail" ]] && { echo "No session $2."; exit 1; }; echo "stopped $2" ;;
  "respawn "*) [[ -f "$STUB/respawn.fail" ]] && { echo "Could not respawn $2."; exit 1; }
    jq -c --arg i "$2" "map(if .id == \$i then .pid = 4242 else . end)" "$STUB/agents.json" >"$STUB/agents.new" \
      && mv "$STUB/agents.new" "$STUB/agents.json"
    echo "respawned $2" ;;
  *) exit 1 ;;
esac'
# ps: `ps -axo ...` prints $STUB/ps.txt (pid ppid command, or command alone for -o command=);
# other calls go to the real ps.
stub ps '
if [[ "${1:-}" == -axo ]]; then
  if [[ "${2:-}" == command= ]]; then cut -d" " -f3- "$STUB/ps.txt"; else cat "$STUB/ps.txt"; fi
  exit 0
fi
exec /bin/ps "$@"'

# --- The setting: default 15; ~/.config/jay/config; the environment wins ---
eq "JAY_AUTO_STOP: default 15" 15 "$JAY_AUTO_STOP"
mkdir -p "$HOME/.config/jay" && printf 'JAY_AUTO_STOP = off\n' >"$HOME/.config/jay/config"
eq "JAY_AUTO_STOP: from the settings file" off "$(env -u JAY_AUTO_STOP bash -c 'source "$HOME/.local/lib/jay-lib.sh"; echo "$JAY_AUTO_STOP"')"
eq "JAY_AUTO_STOP: the environment wins" 30 "$(JAY_AUTO_STOP=30 bash -c 'source "$HOME/.local/lib/jay-lib.sh"; echo "$JAY_AUTO_STOP"')"
rm -f "$HOME/.config/jay/config"

# --- The agents ---
now=$(date +%s)
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z; } # iso SECONDS
old=$(iso $((now - 20 * 60)))
root="$HOME/Documents/projects/acme"
web="$root/web"
repo "$web"
bg() { # bg ID PID [more JSON]: a running background agent, done and idle, started 30 min ago
  local more=${3:-}
  [[ -n "$more" ]] || more='{}'
  jq -nc --arg id "$1" --arg pid "$2" --argjson t "$(((now - 30 * 60) * 1000))" --argjson more "$more" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: ("acme/" + $id), cwd: env.HOME,
      state: "done", status: "idle", startedAt: $t,
      pid: (if $pid == "" then null else ($pid | tonumber) end)} + $more'
}
state() { # state ID JSON: state.json of a job, last changed 20 min ago
  job "$1" "$(jq -nc --arg c "$HOME" --arg u "$old" --argjson s "$2" '{cwd: $c, createdAt: "2026-10-01T10:00:00.000Z",
    updatedAt: $u, tempo: "idle", inFlight: {tasks: 0, queued: 0, kinds: []}} + $s')"
}
orchflags=$(jq -nc --arg p "$(jay_orchestrator_prompt web "$web")" '["--name", "web/main", "--append-system-prompt", $p]')
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do state "s$i" '{}'; done
state s03 "{\"cwd\": \"$web\", \"respawnFlags\": $orchflags}"
state s05 "{\"cwd\": \"$root/gone\"}"
state s06 '{"tempo": "active"}'
state s11 '{"inFlight": {"tasks": 1, "queued": 0, "kinds": ["monitor"]}}'
state s12 '{"inFlight": {"tasks": 0, "queued": 0, "kinds": [], "wake": {"at": 1}}}'
state s17 "{\"updatedAt\": \"$(iso $((now - 5 * 60)))\"}"
agents=$(jq -sc . <<EOF
$(bg s01 1001)
$(bg s02 1002)
$(bg s03 1003 "{\"cwd\": \"$web\"}")
$(bg s04 1004)
$(bg s05 1005)
$(bg s06 1006)
$(bg s07 1007 '{"state": "working", "status": "busy"}')
$(bg s08 1008 '{"state": "working"}')
$(bg s09 1009 '{"state": "blocked"}')
$(bg s10 1010 '{"state": "failed"}')
$(bg s11 1011)
$(bg s12 1012)
$(bg s13 1013)
$(bg s14 1014)
$(bg s15 1015)
$(bg s16 1016)
$(bg s17 1017)
$(bg s18 1018)
$(bg s19 1019)
$(bg s20 "")
$(bg s21 1021)
$(bg s22 1022)
$(bg s23 1023 "{\"startedAt\": $(((now - 2 * 60) * 1000))}")
{"kind": "interactive", "sessionId": "sid-inter", "cwd": "$HOME", "status": "idle", "state": "done", "pid": 1030}
EOF
)
stub_agents "$agents"
# s13: a background Bash command (zsh) under its process; s21: only caffeinate (a turn ended
# a moment ago); s16: a claude attach client.
cat >"$STUB/ps.txt" <<EOF
1001 900 claude bg-spare --bg-spare /tmp/cc/spare/1001.claim.sock
2001 1013 /bin/zsh -c source /tmp/snapshot.sh && eval 'tests/run.sh smoke'
2002 1021 caffeinate -i -t 300
2003 1 claude attach s16
2004 1030 /bin/zsh -c ls
EOF
mkdir -p "$JAY_STATE/replaced"
echo s99 >"$JAY_STATE/replaced/s04"
echo s02 >"$JAY_HUB_CLAUDE_FILE"
jay_mark seen sid-s18
mkdir -p "$JAY_STATE/stopped" && touch -t "$(date -r $((now - 3 * 60)) +%Y%m%d%H%M.%S)" "$JAY_STATE/stopped/s19"

# The middle columns: the zellij hub shows s14 (by id), the tmux hub s15 (by session id); a
# target file whose jay-pane does not run any more (s22) does not count.
mkdir -p "$TMP/x" "$JAY_STATE/tmux"
printf '#!/bin/bash\ntrap '\''kill $! 2>/dev/null; exit 0'\'' TERM\nsleep 60 &\nwait\n' >"$TMP/x/jay-pane"
chmod +x "$TMP/x/jay-pane"
pane=$( ("$TMP/x/jay-pane" agent >/dev/null 2>&1 &) ; sleep 0.2; pgrep -f "$TMP/x/jay-pane agent")
printf '3\t%s\n' "$pane" >"$JAY_STATE/agent.pane"
printf 's14\t%s\tbackground\tacme/s14\n' "$HOME" >"$JAY_STATE/agent.target"
printf '%%2\t%s\n' "$pane" >"$JAY_STATE/tmux/agent.pane"
printf 'sid-s15\t%s\tbackground\tacme/s15\n' "$HOME" >"$JAY_STATE/tmux/agent.target"
shown=$(jay_hubs_shown)
eq "jay_hubs_shown: both hubs" '["s14","sid-s15"]' "$shown"
printf '%%2\t999999\n' >"$JAY_STATE/tmux/agent.pane"
eq "jay_hubs_shown: a hub whose agent pane does not run" '["s14"]' "$(jay_hubs_shown)"
printf '%%2\t%s\n' "$pane" >"$JAY_STATE/tmux/agent.pane"

kids=$(jay_agent_children "$agents")
eq "jay_agent_children: a background Bash command" "zsh, pid 2001" "$(jq -r .s13 <<<"$kids")"
eq "jay_agent_children: caffeinate is no background work" null "$(jq -r .s21 <<<"$kids")"
eq "jay_agent_children: not an interactive session" 1 "$(jq length <<<"$kids")"

phased=$(jay_agent_phases "$agents" "")
jobs=$(jay_jobs "$phased")
eq "jay_jobs: updated, from updatedAt" "$(((now - 20 * 60) * 1000))" "$(jq '.s01.updated' <<<"$jobs")"
plan=$(jay_stop_plan "$phased" "$jobs" 15)
why() { awk -F'\t' -v i="$1" '$1 == i { print $4 }' <<<"$plan"; }
inplan() { awk -F'\t' -v i="$1" '$1 == i { print "yes" }' <<<"$plan"; }
eq "rule: idle 20 min, nothing needs it: stops" "" "$(why s01)"
has "rule: the plan names it and its idle minutes" "$(printf 's01\tacme/s01\t20\t')" "$plan"
eq "rule: the hub Claude" "the hub Claude" "$(why s02)"
eq "rule: an orchestrator" "an orchestrator: it waits for reports" "$(why s03)"
eq "rule: a replaced entry" "a copy replaced it" "$(why s04)"
eq "rule: the folder it wakes in is gone" "its folder is gone: it could not wake" "$(why s05)"
eq "rule: a turn runs (tempo)" "a turn runs" "$(why s06)"
eq "rule: a turn runs (status busy)" "a turn runs" "$(why s07)"
eq "rule: state working, process idle (waits for an idle notice)" "its state is working: it may wait for an idle notice" "$(why s08)"
eq "rule: blocked (a question, a permission prompt, a first prompt)" "it asks you something or waits for its first prompt" "$(why s09)"
eq "rule: failed" "it failed" "$(why s10)"
eq "rule: a background task or Monitor" "it has background tasks, crons or wakeups" "$(why s11)"
eq "rule: a wakeup (ScheduleWakeup)" "it has background tasks, crons or wakeups" "$(why s12)"
eq "rule: a child process (a background Bash command)" "it runs zsh, pid 2001" "$(why s13)"
eq "rule: in the zellij hub's middle column" "it is in a hub's middle column" "$(why s14)"
eq "rule: in the tmux hub's middle column (session id)" "it is in a hub's middle column" "$(why s15)"
eq "rule: a claude attach client" "a claude attach client shows it" "$(why s16)"
eq "rule: its job changed 5 min ago" "idle for 5 min" "$(why s17)"
eq "rule: you saw it a moment ago (mark seen)" "idle for 0 min" "$(why s18)"
eq "rule: the hub tried to stop it 3 min ago" "the hub tried to stop it 3 min ago" "$(why s19)"
eq "rule: not in the plan when it does not run" "" "$(inplan s20)"
eq "rule: caffeinate alone: stops" "" "$(why s21)"
eq "rule: a hub target whose pane does not run: stops" "" "$(why s22)"
eq "rule: started (a wake, a respawn) 2 min ago" "idle for 2 min" "$(why s23)"
eq "rule: not an interactive session" 0 "$(grep -c sid-inter <<<"$plan")"
plan=$(jay_stop_plan "$phased" "$jobs" 30)
eq "rule: JAY_AUTO_STOP=30: 20 min is not enough" "idle for 20 min" "$(why s01)"

# --- jay_auto_stop: claude stop, the mark, the log ---
: >"$STUB/claude.calls"
out=$(jay_auto_stop s01 acme/s01 20)
eq "jay_auto_stop: Claude's output" "stopped s01" "$out"
eq "jay_auto_stop: claude stop <id>" "stop s01" "$(cat "$STUB/claude.calls")"
ok "jay_auto_stop: the mark" test -f "$JAY_STATE/stopped/s01"
has "jay_auto_stop: the log" "s01 (acme/s01): stop after 20 min idle: stopped s01" "$(cat "$JAY_STATE/prune.log")"
: >"$STUB/stop.fail"
no "jay_auto_stop: fails when claude stop fails" jay_auto_stop s21 acme/s21 20
ok "jay_auto_stop: a failed one is marked too (the next try waits)" test -f "$JAY_STATE/stopped/s21"
has "jay_auto_stop: the failure in the log" "s21 (acme/s21): stop after 20 min idle: No session s21." "$(cat "$JAY_STATE/prune.log")"
rm -f "$STUB/stop.fail" "$JAY_STATE/stopped/s01" "$JAY_STATE/stopped/s21" "$JAY_STATE/prune.log"

# --- jay_stop_auto: the setting, once a minute, only the ones the rule lets ---
: >"$STUB/claude.calls"
JAY_AUTO_STOP=off jay_stop_auto "$phased" "$jobs"
eq "auto: off does nothing" "" "$(grep stop "$STUB/claude.calls")"
JAY_AUTO_STOP=soon jay_stop_auto "$phased" "$jobs"
eq "auto: not a number: nothing" "" "$(grep stop "$STUB/claude.calls")"
JAY_AUTO_STOP=0 jay_stop_auto "$phased" "$jobs"
eq "auto: 0: nothing" "" "$(grep stop "$STUB/claude.calls")"
jay_stop_auto "$phased" "$jobs"
eq "auto: stops only the agents that pass the rule" "stop s01 stop s21 stop s22" \
  "$(grep stop "$STUB/claude.calls" | tr '\n' ' ' | sed 's/ $//')"
eq "auto: three lines in the log" 3 "$(grep -c 'min idle' "$JAY_STATE/prune.log")"
: >"$STUB/claude.calls"
rm -f "$JAY_STATE"/stopped/s0* "$JAY_STATE"/stopped/s2*
jay_stop_auto "$phased" "$jobs"
eq "auto: not again within a minute" "" "$(grep stop "$STUB/claude.calls")"

# --- The respawn step after it (same agents JSON) leaves an agent the hub just stopped ---
stale='{"s01": "2.1.300"}'
touch "$JAY_STATE/stopped/s01"
eq "respawn rule: not an agent the hub stopped just now" "the hub stopped it just now: it wakes on the new version" \
  "$(jay_respawn_plan "$phased" "$jobs" "$stale" "" | awk -F'\t' '$1 == "s01" { print $4 }')"
touch -t "$(date -r $((now - 5 * 60)) +%Y%m%d%H%M.%S)" "$JAY_STATE/stopped/s01"
eq "respawn rule: a stop some minutes ago does not count" "" \
  "$(jay_respawn_plan "$phased" "$jobs" "$stale" "" | awk -F'\t' '$1 == "s01" { print $4 }')"
kill "$pane" 2>/dev/null

# --- jay wake ---
two=$(jq -sc . <<EOF
$(bg w1 "")
$(bg w2 1102)
$(bg w3 "" '{"name": "acme/twin"}')
$(bg w4 "" '{"name": "acme/twin"}')
$(bg w5 "")
$(bg w6 "" '{"name": "Acme/Mixed"}')
EOF
)
stub_agents "$two"
state w1 '{}'
state w5 "{\"cwd\": \"$root/gone\"}"
state w6 '{}'
rm -f "$JAY_STATE/prune.log"
: >"$STUB/claude.calls"
out=$(jay wake acme/w1 2>&1)
has "jay wake <name>: it runs again" "\"acme/w1\" (w1) runs again: SendMessage reaches it now." "$out"
eq "jay wake: one claude respawn" "respawn w1" "$(grep respawn "$STUB/claude.calls")"
has "jay wake: the log" "w1 (acme/w1): wake: respawned w1" "$(cat "$JAY_STATE/prune.log")"
: >"$STUB/claude.calls"
out=$(jay wake w2 2>&1)
has "jay wake <id> that runs: nothing to wake" "runs: nothing to wake" "$out"
eq "jay wake: never a respawn of an agent that runs (it would end its turn)" "" "$(grep respawn "$STUB/claude.calls")"
out=$(jay wake acme/twin 2>&1)
has "jay wake: two agents with one name: their ids" "w3  acme/twin" "$out"
no "jay wake: two agents with one name fail" jay wake acme/twin
out=$(jay wake w5 2>&1)
has "jay wake: its folder is gone: jay go --repair" "jay go --repair w5" "$out"
no "jay wake: its folder is gone fails" jay wake w5
no "jay wake: an unknown agent" jay wake nobody
no "jay wake: no agent given" jay wake
out=$(jay wake acme/mixed 2>&1)
has "jay wake: a name in another case" "\"Acme/Mixed\" (w6) runs again" "$out"
stub_agents "$two"
: >"$STUB/respawn.fail"
out=$(jay wake w1 2>&1)
has "jay wake: claude respawn fails: Claude's output" "Could not respawn w1." "$out"
has "jay wake: claude respawn fails: did not wake" "did not wake" "$out"
no "jay wake: claude respawn fails: exit 1" jay wake w1
rm -f "$STUB/respawn.fail"
has "jay --help lists wake" "wake <id|name>" "$(jay --help)"

finish

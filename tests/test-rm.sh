#!/bin/bash
# jay rm (bin/jay-rm, jay_remove_agent and jay_forget_agent in lib/jay-lib.sh): by id, by name,
# an ambiguous name, an interactive session, the hub Claude and an orchestrator, a busy agent
# and --force, a recorded worktree on disk, a `claude rm` that keeps the agent, and an agent that
# removes itself (the detached process).
source "$(dirname "$0")/lib.sh"
link_install
export JAY_ROOTS=$TMP
source "$HOME/.local/lib/jay-lib.sh"

# claude: `agents --json` prints $STUB/agents.json. `stop` takes the pid away; `rm` deletes the
# agent and its job folder, or prints $STUB/rm.out and fails when that file is there. Both note
# the CLAUDE_JOB_DIR they got in $STUB/env.calls; rm notes its caller's process group, then the
# caller's ancestors up to launchd, in $STUB/rm.parent.
stub claude '
agents() { jq -c "$1" --arg i "$2" "$STUB/agents.json" >"$STUB/agents.new" && mv "$STUB/agents.new" "$STUB/agents.json"; }
known() { jq -e --arg i "$1" "any(.[]; .id == \$i)" "$STUB/agents.json" >/dev/null || { echo "No job matching '\''$1'\''"; exit 1; }; }
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "stop "*) echo "stop $2 ${CLAUDE_JOB_DIR:-none}" >>"$STUB/env.calls"; known "$2"
    agents "map(if .id == \$i then .pid = null | .status = null else . end)" "$2"; echo "stopped $2" ;;
  "rm "*) echo "rm $2 ${CLAUDE_JOB_DIR:-none}" >>"$STUB/env.calls"; known "$2"
    p=$PPID; { ps -o pgid= -p $p; while ((p > 1)); do p=$(ps -o ppid= -p $p); echo $p; done; } | xargs >"$STUB/rm.parent"
    [[ -f "$STUB/rm.out" ]] && { cat "$STUB/rm.out"; exit 1; }
    agents "map(select(.id != \$i))" "$2"; rm -rf "$HOME/.claude/jobs/$2"; echo "removed $2" ;;
  *) exit 1 ;;
esac'

bg() { # bg ID NAME PID [more JSON]: a background agent, done and idle
  local more=${4:-}
  [[ -n "$more" ]] || more='{}'
  jq -nc --arg id "$1" --arg name "$2" --arg pid "$3" --argjson more "$more" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $name, cwd: env.HOME, state: "done",
      status: (if $pid == "" then null else "idle" end), pid: (if $pid == "" then null else ($pid | tonumber) end)} + $more'
}
orchflags=$(jq -nc --arg p "$(jay_orchestrator_prompt web "$HOME/web")" '["--name", "web/main", "--append-system-prompt", $p]')
mkdir -p "$TMP/wt-on-disk"
for i in 000000a1 000000a2 000000a3 000000a4 000000hb 000000b1 000000b2 000000w2 000000s1; do
  job "$i" "{\"cwd\": \"$HOME\", \"sessionId\": \"sid-$i\", \"tempo\": \"idle\"}"
done
job 000000o1 "{\"cwd\": \"$HOME/web\", \"respawnFlags\": $orchflags}"
job 000000w1 "{\"cwd\": \"$HOME\", \"worktreePath\": \"$TMP/wt-on-disk\"}"
job 000000b2 '{"tempo": "active"}'
stub_agents "$(jq -sc . <<EOF
$(bg 000000a1 acme/web 1001)
$(bg 000000a2 shop/api "")
$(bg 000000a3 dup 1003)
$(bg 000000a4 dup "")
$(bg 000000hb hub 1005)
$(bg 000000o1 web/main 1006 "{\"cwd\": \"$HOME/web\"}")
$(bg 000000b1 acme/busy 1007 '{"status": "busy", "state": "working"}')
$(bg 000000b2 acme/tempo 1008)
$(bg 000000w1 acme/tree "")
$(bg 000000w2 acme/kept 1010)
$(bg 000000s1 acme/self 1011 '{"status": "busy", "state": "working"}')
{"kind": "interactive", "sessionId": "sid-inter", "name": "term", "cwd": "$HOME", "status": "idle", "state": "done", "pid": 1030}
EOF
)"
jay_state_dir
echo 000000hb >"$JAY_HUB_CLAUDE_FILE"
calls() { cat "$STUB/claude.calls" 2>/dev/null | grep -E '^(stop|rm) '; }
reset_calls() { rm -f "$STUB/claude.calls"; }

# --- By id: stop (it runs), then rm; the gone tasks of that agent go (both hubs, by id or
# session id), others stay; its note goes; prune.log has the stop and the rm ---
mkdir -p "$JAY_STATE/tasks/gone" "$JAY_STATE/tmux/tasks/gone"
echo '{"name": "dev", "agent": "000000a1"}' >"$JAY_STATE/tasks/gone/1-3.json"
echo '{"name": "api", "agent": "sid-000000a1"}' >"$JAY_STATE/tmux/tasks/gone/2-4.json"
echo '{"name": "other", "agent": "000000a2x"}' >"$JAY_STATE/tasks/gone/1-5.json"
echo '{"name": "mine", "agent": null}' >"$JAY_STATE/tasks/gone/1-6.json"
jay_agent_note 000000a1 "the web task"
out=$(jay rm 000000a1 2>&1); rc=$?
eq "id: exit 0" 0 "$rc"
has "id: says removed" '"acme/web" (000000a1) is removed' "$out"
eq "id: stop, then rm" "$(printf 'stop 000000a1\nrm 000000a1')" "$(calls)"
eq "id: its gone tasks go, others stay" "1-5.json 1-6.json" "$(ls "$JAY_STATE/tasks/gone" "$JAY_STATE/tmux/tasks/gone" | grep json | xargs)"
no "id: its note goes" test -f "$JAY_NOTES/000000a1"
has "id: prune.log: the stop" "000000a1 (acme/web): stop for rm: stopped 000000a1" "$(cat "$JAY_STATE/prune.log")"
has "id: prune.log: the rm" "000000a1 (acme/web): rm: removed 000000a1" "$(cat "$JAY_STATE/prune.log")"

# --- By name, in any case; it does not run: rm alone ---
reset_calls
out=$(jay rm SHOP/API 2>&1); rc=$?
eq "name: exit 0" 0 "$rc"
eq "name: no stop, rm" "rm 000000a2" "$(calls)"

# --- An ambiguous name; an unknown one; an interactive session; usage ---
reset_calls
out=$(jay rm dup 2>&1); rc=$?
eq "two named dup: exit 1" 1 "$rc"
has "two named dup: lists one" "000000a3  dup" "$out"
has "two named dup: lists the other" "000000a4  dup" "$out"
eq "two named dup: no stop, no rm" "" "$(calls)"
out=$(jay rm nobody 2>&1); rc=$?
eq "unknown: exit 1" 1 "$rc"
has "unknown: says so" "no background agent nobody" "$out"
out=$(jay rm term 2>&1); rc=$?
eq "interactive: exit 1" 1 "$rc"
has "interactive: says so" "term is an interactive session, not a background agent" "$out"
out=$(jay rm 2>&1); rc=$?
eq "no agent: exit 2" 2 "$rc"
has "jay --help lists rm" "rm <id|name> | --self" "$(jay --help)"
has "jay rm --help" "jay rm [--force] <id | session id | name>" "$(jay rm --help)"
out=$(jay rm a b 2>&1); rc=$?
eq "two agents: exit 2" 2 "$rc"
out=$(jay rm --self 2>&1); rc=$?
eq "--self outside an agent: exit 1" 1 "$rc"
has "--self outside an agent: says so" "only a background agent can remove itself" "$out"
eq "usage errors: no stop, no rm" "" "$(calls)"

# --- The hub Claude, an orchestrator, a busy agent: refused; --force removes them ---
out=$(jay rm hub 2>&1); rc=$?
eq "hub Claude: exit 1" 1 "$rc"
has "hub Claude: says why" "it is the hub Claude" "$out"
has "hub Claude: names --force" "jay rm --force 000000hb" "$out"
out=$(jay rm web/main 2>&1); rc=$?
eq "orchestrator: exit 1" 1 "$rc"
has "orchestrator: says why" "it is an orchestrator" "$out"
out=$(jay rm acme/busy 2>&1); rc=$?
eq "busy: exit 1" 1 "$rc"
has "busy: says why" "a turn runs" "$out"
out=$(jay rm acme/tempo 2>&1); rc=$?
eq "tempo active: exit 1" 1 "$rc"
has "tempo active: says why" "a turn runs" "$out"
eq "refused: no stop, no rm" "" "$(calls)"
out=$(jay rm --force acme/busy 2>&1); rc=$?
eq "busy --force: exit 0" 0 "$rc"
eq "busy --force: stop, then rm" "$(printf 'stop 000000b1\nrm 000000b1')" "$(calls)"
reset_calls
out=$(jay rm -f web/main 2>&1); rc=$?
eq "orchestrator -f: exit 0" 0 "$rc"
eq "orchestrator -f: stop, then rm" "$(printf 'stop 000000o1\nrm 000000o1')" "$(calls)"

# --- A recorded worktree on disk: refused before the stop ---
reset_calls
out=$(jay rm acme/tree 2>&1); rc=$?
eq "worktree on disk: exit 1" 1 "$rc"
has "worktree on disk: names it" "on disk ($TMP/wt-on-disk)" "$out"
has "worktree on disk: wt remove first" "Remove that worktree first (wt remove" "$out"
eq "worktree on disk: no stop, no rm" "" "$(calls)"

# --- claude rm keeps the agent: its text, what to do, and that it is stopped now ---
printf 'kept 000000w2 — its worktree is still at “/x/acme.kept”\n  1 unpushed commit on “kept”.\n' >"$STUB/rm.out"
out=$(jay rm acme/kept 2>&1); rc=$?
rm -f "$STUB/rm.out"
eq "claude rm keeps it: exit 1" 1 "$rc"
has "claude rm keeps it: Claude's text" "kept 000000w2 — its worktree is still at" "$out"
has "claude rm keeps it: what to do" "remove the worktree first (wt remove" "$out"
has "claude rm keeps it: stopped now" "It is stopped now: jay wake 000000w2" "$out"
has "claude rm keeps it: prune.log" "000000w2 (acme/kept): rm: kept 000000w2" "$(cat "$JAY_STATE/prune.log")"
eq "claude rm keeps it: stop, then rm" "$(printf 'stop 000000w2\nrm 000000w2')" "$(calls)"

# --- Itself, in a turn: no refusal for its own turn; a detached process waits until the turn
# ends, then stops and removes it, without the CLAUDE* variables and outside the caller's tree ---
reset_calls
rm -f "$STUB/env.calls"
out=$(CLAUDE_JOB_DIR="$HOME/.claude/jobs/000000s1" CLAUDE_CODE_SESSION_ID=sid-000000s1 JAY_RM_POLL=0.2 jay rm --self 2>&1); rc=$?
eq "self: exit 0" 0 "$rc"
has "self: says it goes after the turn" "is this agent: it goes when this turn ends" "$out"
has "self: prune.log: waits" "000000s1 (acme/self): rm after its turn: a process waits" "$(cat "$JAY_STATE/prune.log")"
sleep 1
eq "self: nothing while the turn runs" "" "$(calls)"
pgrep -f "jay-rm --after-turn 000000s1" >/dev/null && pass "self: the process waits" || fail "self: the process waits" "no jay-rm --after-turn process"
# The turn ends.
jq -c 'map(if .id == "000000s1" then .status = "idle" | .state = "done" else . end)' "$STUB/agents.json" >"$STUB/agents.new" \
  && mv "$STUB/agents.new" "$STUB/agents.json"
# Wait for the rm line in prune.log: jay_remove_agent writes it after `claude rm` returns, so the
# stub's files are complete then (its call line in claude.calls comes first, at its start). Up to
# 30 s: a busy machine slows the waiter's polls and the stub.
done_line="000000s1 (acme/self): rm: "
for _ in $(seq 300); do grep -qF "$done_line" "$JAY_STATE/prune.log" && break; sleep 0.1; done
grep -qF "$done_line" "$JAY_STATE/prune.log" && pass "self: removed within 30 s" \
  || fail "self: removed within 30 s" "no \"$done_line\" in prune.log:" "$(cat "$JAY_STATE/prune.log")"
eq "self: stop, then rm after the turn" "$(printf 'stop 000000s1\nrm 000000s1')" "$(calls)"
eq "self: no CLAUDE_JOB_DIR in the process" "$(printf 'stop 000000s1 none\nrm 000000s1 none')" "$(cat "$STUB/env.calls" 2>/dev/null)"
read -r pgid ancestors <"$STUB/rm.parent"
eq "self: the process tree ends at launchd" 1 "${ancestors##* }"
hasnt "self: outside the caller's process tree" " $$ " " $ancestors "
[[ "$pgid" != "$(ps -o pgid= -p $$ | tr -d ' ')" ]] && pass "self: a process group of its own" \
  || fail "self: a process group of its own" "pgid $pgid is the test's"
has "self: prune.log: the rm" "000000s1 (acme/self): rm: removed 000000s1" "$(cat "$JAY_STATE/prune.log")"

# --- By its own name, the same path (and jay wake still finds agents through jay_agent_find) ---
reset_calls
job 000000s2 "{\"cwd\": \"$HOME\", \"tempo\": \"active\"}"
jq -c --argjson a "$(bg 000000s2 acme/me 1012 '{"status": "busy"}')" '. + [$a]' "$STUB/agents.json" >"$STUB/agents.new" \
  && mv "$STUB/agents.new" "$STUB/agents.json"
out=$(CLAUDE_JOB_DIR="$HOME/.claude/jobs/000000s2/" JAY_RM_POLL=0.2 jay rm acme/me 2>&1); rc=$?
eq "self by name: exit 0" 0 "$rc"
has "self by name: after the turn" "it goes when this turn ends" "$out"
pkill -f "jay-rm --after-turn 000000s2"
out=$(jay wake dup 2>&1); rc=$?
eq "jay wake: ambiguous name still found" 1 "$rc"
has "jay wake: lists them" "000000a3  dup" "$out"

finish

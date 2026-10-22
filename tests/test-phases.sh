#!/bin/bash
# jay_agent_phases (lib/jay-lib.sh): the phase of each agent, and the marks of the Stop hook
# (jay-notify) that make an agent unread.
source "$(dirname "$0")/lib.sh"
link_install
# The hub sees only the agents in JAY_ROOTS; the test's folders are under $TMP.
export JAY_ROOTS=$TMP
source "$HOME/.local/lib/jay-lib.sh"

# mark_at KIND KEY TIME: mark KIND (seen, ended) of KEY at TIME (touch -t format).
mark_at() { mkdir -p "$JAY_MARKS/$1" && touch -t "$3" "$JAY_MARKS/$1/$2"; }
# phase AGENTS ID [SHOWN]: the phase of agent ID (its id, else its session id).
phase() {
  jay_agent_phases "$1" "${3:-}" | jq -r --arg i "$2" '.[] | select((.id // .sessionId) == $i) | .phase'
}

agents='[
  {"kind": "background", "id": "aaaa0001", "sessionId": "s-0001", "state": "blocked", "status": "idle"},
  {"kind": "background", "id": "aaaa0002", "sessionId": "s-0002", "state": "working", "status": "waiting"},
  {"kind": "background", "id": "aaaa0003", "sessionId": "s-0003", "state": "failed", "status": "idle"},
  {"kind": "background", "id": "aaaa0004", "sessionId": "s-0004", "state": "blocked", "status": "idle"},
  {"kind": "background", "id": "aaaa0005", "sessionId": "s-0005", "state": "working", "status": "busy"},
  {"kind": "interactive", "sessionId": "s-0006", "status": "busy"},
  {"kind": "background", "id": "aaaa0007", "sessionId": "s-0007", "state": "working", "status": "idle"},
  {"kind": "background", "id": "aaaa0008", "sessionId": "s-0008", "state": "working", "status": "idle"},
  {"kind": "background", "id": "aaaa0009", "sessionId": "s-0009", "state": "done", "status": "idle"},
  {"kind": "background", "id": "aaaa0010", "sessionId": "s-0010", "state": "done", "status": "idle"},
  {"kind": "interactive", "sessionId": "s-0011", "status": "idle"},
  {"kind": "background", "id": "aaaa0012", "sessionId": "s-0012", "state": "done", "status": "idle"}
]'
# A new agent that waits for its first prompt: `claude agents` calls it blocked, its job says so.
job aaaa0004 '{"needs": "send a prompt to start"}'
job aaaa0001 '{"needs": "permission"}'
mark_at seen aaaa0008 202601010000.00
mark_at ended aaaa0008 202601010001.00
mark_at seen aaaa0009 202601010000.00
mark_at ended aaaa0009 202601010001.00
mark_at ended aaaa0010 202601010000.00
mark_at seen aaaa0010 202601010001.00
mark_at ended s-0011 202601010001.00

eq "blocked: input" input "$(phase "$agents" aaaa0001)"
eq "status waiting: input" input "$(phase "$agents" aaaa0002)"
eq "state failed: failed" failed "$(phase "$agents" aaaa0003)"
eq "new agent (blocked, no first prompt): idle" idle "$(phase "$agents" aaaa0004)"
eq "working and busy: working" working "$(phase "$agents" aaaa0005)"
eq "interactive and busy: working" working "$(phase "$agents" s-0006)"
eq "working with status idle, no turn ended: idle" idle "$(phase "$agents" aaaa0007)"
eq "working with status idle, a turn ended after seen: unread" unread "$(phase "$agents" aaaa0008)"
eq "a turn ended after seen: unread" unread "$(phase "$agents" aaaa0009)"
eq "seen after the turn ended: idle" idle "$(phase "$agents" aaaa0010)"
eq "interactive, marks under its session id: unread" unread "$(phase "$agents" s-0011)"
eq "the shown agent is never unread" idle "$(phase "$agents" aaaa0009 aaaa0009)"
eq "the shown agent is never unread (session id)" idle "$(phase "$agents" s-0011 s-0011)"
eq "no marks: idle" idle "$(phase "$agents" aaaa0012)"
eq "every agent gets a phase" 12 "$(jay_agent_phases "$agents" "" | jq '[.[] | select(.phase)] | length')"

# The Stop hook writes the ended mark: seen, then a new Stop, gives unread.
stop() {
  jq -nc --arg s "$1" --arg c "$TMP" --argjson bg "${2:-[]}" \
    '{hook_event_name: "Stop", session_id: $s, cwd: $c, last_assistant_message: "result: done", background_tasks: $bg}' \
    | JAY_NOTIFY_LOG="$STUB/notify.log" jay-notify
}
jay_mark seen aaaa0012
eq "seen: idle" idle "$(phase "$agents" aaaa0012)"
sleep 1
job aaaa0012 '{"sessionId": "s-0012"}'
CLAUDE_JOB_DIR="$HOME/.claude/jobs/aaaa0012" stop s-0012 >/dev/null
ok "Stop of a background agent: an ended mark under its job id" test -f "$JAY_MARKS/ended/aaaa0012"
eq "seen, then a new Stop: unread" unread "$(phase "$agents" aaaa0012)"
for i in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$STUB/terminal-notifier.calls" ]] && break; sleep 0.2; done
has "Stop posts a notice" "Turn finished" "$(cat "$STUB/terminal-notifier.calls" 2>/dev/null)"

# A Stop while the agent has background tasks: its turn goes on, so no ended mark, no notice.
rm -f "$STUB/terminal-notifier.calls"
stop s-0013 '[{"id": "t1"}]' >/dev/null
no "Stop with background tasks: no ended mark" test -e "$JAY_MARKS/ended/s-0013"
stop s-0014 >/dev/null
ok "Stop without background tasks: an ended mark under the session id" test -f "$JAY_MARKS/ended/s-0014"
sleep 1
no "Stop with background tasks: no notice" grep -q s-0013 "$STUB/terminal-notifier.calls"

# A Notification asks for input: a notice, no ended mark. Through the hook's old name (a shim,
# as in the settings.json of an older install): no output, which could reach Claude.
out=$(jq -nc --arg c "$TMP" '{hook_event_name: "Notification", notification_type: "permission_prompt", session_id: "s-0015", cwd: $c, message: "May I?"}' \
  | claude-notify 2>&1)
eq "the old hook name prints nothing" "" "$out"
no "Notification: no ended mark" test -e "$JAY_MARKS/ended/s-0015"
for i in 1 2 3 4 5 6 7 8 9 10; do grep -q 'Needs input' "$STUB/terminal-notifier.calls" 2>/dev/null && break; sleep 0.2; done
has "the old hook name posts the notice" "Needs input" "$(cat "$STUB/terminal-notifier.calls" 2>/dev/null)"

finish

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

# Blocked agents that ask nothing now. A /clear after a question keeps the job's state blocked
# and its needs, and gives a new session id: its transcript (the job's linkScanPath, else found
# by session id under projects/) has no answer of the agent yet. With no process (no pid, no
# status), nobody waits for an answer: unread or idle by the marks, as a done agent.
# transcript SESSION [TYPE...]: a transcript under projects/-tmp-shop with one line of each type.
transcript() {
  local f="$HOME/.claude/projects/-tmp-shop/$1.jsonl" t
  mkdir -p "${f%/*}" && : >"$f"
  shift
  for t in "$@"; do printf '{"type":"%s","message":{"content":"x"}}\n' "$t" >>"$f"; done
  printf '%s\n' "$f"
}
blocked='[
  {"kind": "background", "id": "aaaa0021", "sessionId": "s-0021", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0022", "sessionId": "s-0022", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0023", "sessionId": "s-0023", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0024", "sessionId": "s-0024", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0025", "sessionId": "s-0025", "state": "blocked"},
  {"kind": "background", "id": "aaaa0026", "sessionId": "s-0026", "state": "blocked", "status": null, "pid": null}
]'
q='"state": "blocked", "needs": "Which colour do you like?"'
job aaaa0021 "{$q, \"linkScanPath\": \"$(transcript s-0021 user system user)\"}"
job aaaa0022 "{$q, \"linkScanPath\": \"$(transcript s-0022 user assistant)\"}"
# linkScanPath still names the session before the /clear: the current session id counts.
transcript s-0023 user >/dev/null
job aaaa0023 "{$q, \"linkScanPath\": \"$(transcript s-0023-old user assistant)\"}"
job aaaa0024 "{$q}"
job aaaa0025 "{$q}"
job aaaa0026 "{$q}"
mark_at seen aaaa0026 202601010000.00
mark_at ended aaaa0026 202601010001.00
eq "blocked, /clear after the question: idle" idle "$(phase "$blocked" aaaa0021)"
eq "blocked, it asked in this session: input" input "$(phase "$blocked" aaaa0022)"
eq "blocked, /clear, linkScanPath of the old session: idle" idle "$(phase "$blocked" aaaa0023)"
eq "blocked, no transcript found: input" input "$(phase "$blocked" aaaa0024)"
eq "blocked, no process: idle" idle "$(phase "$blocked" aaaa0025)"
eq "blocked, no process, a turn ended after seen: unread" unread "$(phase "$blocked" aaaa0026)"
eq "fresh ids: the new agent and the cleared ones" '["aaaa0021","aaaa0023"]' "$(jay_fresh_ids "$blocked")"

# A respawn or a wake of an agent that never had a turn: the job loses needs, and there is no
# transcript. With no first prompt (intent "") it asks nothing; one with a first prompt, or with
# a transcript that has an answer, does.
respawned='[
  {"kind": "background", "id": "aaaa0031", "sessionId": "s-0031", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0032", "sessionId": "s-0032", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0033", "sessionId": "s-0033", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0034", "sessionId": "s-0034", "state": "blocked", "status": "idle", "pid": 1},
  {"kind": "background", "id": "aaaa0035", "sessionId": "s-0035", "state": "blocked", "status": "waiting", "pid": 1},
  {"kind": "background", "id": "aaaa0036", "sessionId": "s-0036", "state": "working", "status": "idle", "pid": 1}
]'
job aaaa0031 '{"state": "working", "detail": "(idle — send a prompt to start)", "intent": "", "linkScanPath": null}'
job aaaa0032 '{"state": "working", "intent": "fix the login", "linkScanPath": null}'
job aaaa0033 "{\"state\": \"blocked\", \"intent\": \"\", \"linkScanPath\": \"$(transcript s-0033 user assistant)\"}"
job aaaa0034 "{\"state\": \"blocked\", \"intent\": \"\", \"needs\": \"Which colour?\", \"linkScanPath\": \"$(transcript s-0034 user)\"}"
job aaaa0035 '{"state": "working", "intent": "", "linkScanPath": null}'
# A wake (claude respawn of a stopped agent): Claude says state working.
job aaaa0036 '{"state": "running", "intent": "", "linkScanPath": null}'
eq "respawned, no turn, no first prompt: idle" idle "$(phase "$respawned" aaaa0031)"
eq "respawned, no transcript, a first prompt: input" input "$(phase "$respawned" aaaa0032)"
eq "blocked, no first prompt, it asked in this session: input" input "$(phase "$respawned" aaaa0033)"
eq "blocked, no first prompt, a transcript with no answer: idle" idle "$(phase "$respawned" aaaa0034)"
eq "status waiting, no turn, no first prompt: input" input "$(phase "$respawned" aaaa0035)"
eq "woken, no turn: idle" idle "$(phase "$respawned" aaaa0036)"

# jay clear takes the phase rule of the list: it refuses an agent that asks (exit 3) and one with
# no process; it goes on for a /clear after a question (the stub's claude attach then fails: 1).
stub_agents "$blocked"
JAY_MUX=zellij jay-clear aaaa0022 >/dev/null 2>&1
eq "jay clear: blocked with a question, refused" 3 $?
JAY_MUX=zellij jay-clear aaaa0025 >/dev/null 2>&1
eq "jay clear: no process, refused" 3 $?
JAY_MUX=zellij jay-clear aaaa0021 >/dev/null 2>&1
eq "jay clear: blocked from before a /clear, goes on" 1 $?

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

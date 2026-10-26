#!/bin/bash
# The hub opens a background agent that does not run: one with no transcript yet (it never got
# a prompt) is woken first (jay_wake_for_attach: `claude respawn`), then attached; one with a
# transcript is only attached (`claude attach` resumes it). jay_transcript finds the transcript.
# A real jay-pane agent process with no multiplexer, one for each case.
source "$(dirname "$0")/lib.sh"
export JAY_ROOTS="$HOME/Documents/projects"
link_install
source "$HOME/.local/lib/jay-lib.sh"

shop="$HOME/Documents/projects/acme/shop"
repo "$shop"
projects="$HOME/.claude/projects"

# The stub claude: `respawn <id>` gives the agent a process; `attach <id>` leaves its id in
# $STUB/attach.log and runs (as Claude, it fails at once on an agent with no process and no
# transcript: $STUB/bare). jay-pane puts mise's shims first on its PATH.
mkdir -p "$HOME/.local/share/mise/shims"
for d in "$HOME/.local/bin" "$HOME/.local/share/mise/shims"; do
  cat >"$d/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB/claude.calls"
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "--version "*) echo "2.1.309 (Claude Code)" ;;
  "respawn "*) jq --arg i "$2" 'map(if .id == $i then .pid = 4242 | .status = "idle" else . end)' \
      "$STUB/agents.json" >"$STUB/a.tmp" && mv "$STUB/a.tmp" "$STUB/agents.json"
    echo "respawned $2" ;;
  "attach "*)
    if grep -qx "$2" "$STUB/bare" 2>/dev/null \
      && jq -e --arg i "$2" 'any(.[]; .id == $i and .pid == null)' "$STUB/agents.json" >/dev/null; then
      echo "Session $2 ended while the background service was off; there is nothing to resume."
      exit 1
    fi
    printf '%s\n' "$2" >>"$STUB/attach.log"
    while sleep 0.2; do :; done ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$d/claude"
done

agent() { # agent ID PID: a background agent in shop (PID null: it does not run)
  jq -nc --arg id "$1" --arg c "$shop" --argjson p "$2" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: ("shop/" + $id), cwd: $c,
      pid: $p, startedAt: 0, state: (if $p == null then "stopped" else "done" end),
      status: (if $p == null then null else "idle" end)}'
}
transcript() { mkdir -p "$projects/$1" && printf '{"type":"user"}\n' >"$projects/$1/$2.jsonl"; }

# Stopped, never prompted: no linkScanPath, no file.
job 0000aa01 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-0000aa01\", \"resumeSessionId\": \"sid-0000aa01\", \"intent\": \"\"}"
# Stopped, with its transcript in linkScanPath.
transcript -acme-shop sid-0000aa02
job 0000aa02 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-0000aa02\", \"linkScanPath\": \"$projects/-acme-shop/sid-0000aa02.jsonl\"}"
# Stopped, resumed elsewhere: no linkScanPath, the file is named after resumeSessionId and lies
# in another folder than its cwd's.
transcript -acme-shop-other sid-old-aa03
job 0000aa03 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-0000aa03\", \"resumeSessionId\": \"sid-old-aa03\"}"
# Runs, never prompted.
job 0000aa04 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-0000aa04\"}"
# Stopped, made with a first prompt, transcript gone: a wake would run that prompt again.
job 0000aa05 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-0000aa05\", \"intent\": \"Goal: fix the login\",
  \"linkScanPath\": \"$projects/-acme-shop/sid-0000aa05.jsonl\"}"
# Stopped, its linkScanPath gone, the session's file in another folder.
transcript -acme-shop-moved sid-0000aa06
job 0000aa06 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-0000aa06\", \"linkScanPath\": \"$projects/-gone/sid-0000aa06.jsonl\"}"
printf '0000aa01\n0000aa05\n' >"$STUB/bare"
stub_agents "$(jq -sc . <<EOF
$(agent 0000aa01 null)
$(agent 0000aa02 null)
$(agent 0000aa03 null)
$(agent 0000aa04 100)
$(agent 0000aa05 null)
$(agent 0000aa06 null)
$(agent 0000aa07 null)
EOF
)"

# --- jay_transcript ---
no "transcript: none, never prompted" jay_transcript 0000aa01
eq "transcript: linkScanPath" "$projects/-acme-shop/sid-0000aa02.jsonl" "$(jay_transcript 0000aa02)"
eq "transcript: resumeSessionId, in another folder" "$projects/-acme-shop-other/sid-old-aa03.jsonl" "$(jay_transcript 0000aa03)"
no "transcript: linkScanPath gone, nothing else" jay_transcript 0000aa05
eq "transcript: linkScanPath gone, the session's file elsewhere" "$projects/-acme-shop-moved/sid-0000aa06.jsonl" "$(jay_transcript 0000aa06)"
no "transcript: no state.json" jay_transcript 0000aa07

# --- jay_wake_for_attach: only a stopped agent with no transcript and no first prompt ---
: >"$STUB/claude.calls"
for id in 0000aa02 0000aa03 0000aa04 0000aa05 0000aa06 0000aa07; do
  eq "wake for attach: $id keeps its id" "$id" "$(jay_wake_for_attach "$id" 2>/dev/null)"
done
eq "wake for attach: no respawn of one with a transcript, that runs, with a first prompt or no state.json" \
  "" "$(grep respawn "$STUB/claude.calls")"

# --- jay-pane: open each agent in the middle column ---
jay_state_dir
pane_pid=""
cleanup() {
  [[ -n "$pane_pid" ]] && { jay_kill_children "$pane_pid"; kill "$pane_pid" 2>/dev/null; }
  pkill -f "$HOME/.*/claude attach" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
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
# start ID: a fresh jay-pane agent on target ID.
start() {
  if [[ -n "$pane_pid" ]]; then
    jay_kill_children "$pane_pid"
    kill "$pane_pid" 2>/dev/null
  fi
  : >"$STUB/claude.calls"
  printf '%s\t%s\tbackground\tshop/%s\n' "$1" "$shop" "$1" >"$JAY_STATE/agent.target"
  env ZELLIJ_PANE_ID=7 TERM=dumb "$HOME/.local/bin/jay-pane" agent </dev/null >"$TMP/pane-$1.log" 2>&1 &
  pane_pid=$!
  disown $!
}
# open ID: start ID; returns when it attached ID (or after 10 s).
open() {
  start "$1"
  within "$1: attached" 10 grep -qx "$1" "$STUB/attach.log"
}
calls() { grep -E '^(respawn|attach) ' "$STUB/claude.calls" | tr '\n' ',' ; }

# A stopped agent with no transcript: woken, then attached.
open 0000aa01
eq "no transcript: respawn, then attach" "respawn 0000aa01,attach 0000aa01," "$(calls)"
has "no transcript: the pane says it wakes it" "shop/0000aa01 does not run and has no conversation yet: waking it" \
  "$(cat "$TMP/pane-0000aa01.log")"
has "no transcript: the wake in prune.log" "0000aa01 (shop/0000aa01): wake: respawned 0000aa01" "$(cat "$JAY_STATE/prune.log")"
hasnt "no transcript: no error" "Could not open this agent" "$(cat "$TMP/pane-0000aa01.log")"

# A stopped agent with a transcript: only attached.
open 0000aa02
eq "transcript: only attach" "attach 0000aa02," "$(calls)"
open 0000aa03
eq "transcript under resumeSessionId: only attach" "attach 0000aa03," "$(calls)"
# One that runs, with no transcript: only attached.
open 0000aa04
eq "runs, no transcript: only attach" "attach 0000aa04," "$(calls)"
# A stopped agent with a first prompt and no transcript: not woken; Claude's error stays.
start 0000aa05
within "first prompt, no transcript: the error stays" 10 grep -q 'Could not open this agent' "$TMP/pane-0000aa05.log"
eq "first prompt, no transcript: no respawn" "attach 0000aa05," "$(calls)"
has "first prompt, no transcript: Claude's error" "there is nothing to resume" "$(cat "$TMP/pane-0000aa05.log")"

finish

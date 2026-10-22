#!/bin/bash
# Claude Code updates (lib/jay-lib.sh): the installed version (jay_claude_version), the version
# each agent runs (jay_running_versions, from ps), the agents on an old one (jay_stale), the
# respawn rule (jay_respawn_plan), jay_respawn, the list's auto step (jay_respawn_auto), its ↻
# mark, and `jay respawn`.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

# claude: its version from $STUB/version; `respawn` answers from $STUB/respawn.out (default
# "respawned <id>") and fails when $STUB/respawn.fail is there.
stub claude '
case "${1:-} ${2:-}" in
  "--version "*) echo "$(cat "$STUB/version") (Claude Code)" ;;
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "respawn "*) [[ -f "$STUB/respawn.fail" ]] && { echo "Workspace not trusted."; exit 1; }
    if [[ -f "$STUB/respawn.out" ]]; then cat "$STUB/respawn.out"; else echo "respawned $2"; fi ;;
  "rm "*) exit 0 ;;
  *) exit 1 ;;
esac'
echo 2.1.308 >"$STUB/version"
# ps: `ps -axo ...` prints $STUB/ps.txt (pid ppid command, or command alone for -o command=);
# other calls go to the real ps.
stub ps '
if [[ "${1:-}" == -axo ]]; then
  if [[ "${2:-}" == command= ]]; then cut -d" " -f3- "$STUB/ps.txt"; else cat "$STUB/ps.txt"; fi
  exit 0
fi
exec /bin/ps "$@"'

# --- The setting: default idle; ~/.config/jay/config; the environment wins ---
eq "JAY_AUTO_RESPAWN: default idle" idle "$JAY_AUTO_RESPAWN"
mkdir -p "$HOME/.config/jay" && printf 'JAY_AUTO_RESPAWN = off\n' >"$HOME/.config/jay/config"
eq "JAY_AUTO_RESPAWN: from the settings file" off "$(env -u JAY_AUTO_RESPAWN bash -c 'source "$HOME/.local/lib/jay-lib.sh"; echo "$JAY_AUTO_RESPAWN"')"
eq "JAY_AUTO_RESPAWN: the environment wins" idle "$(JAY_AUTO_RESPAWN=idle bash -c 'source "$HOME/.local/lib/jay-lib.sh"; echo "$JAY_AUTO_RESPAWN"')"
rm -f "$HOME/.config/jay/config"

# --- jay_claude_version: cached under the binary's path and mtime ---
eq "the installed version" 2.1.308 "$(jay_claude_version)"
: >"$STUB/claude.calls"
jay_claude_version >/dev/null
eq "the second call reads the cache" 0 "$(grep -c -- --version "$STUB/claude.calls")"
echo 2.1.309 >"$STUB/version"
eq "the same binary: the cache" 2.1.308 "$(jay_claude_version)"
touch -t 203001010000 "$HOME/.local/bin/claude"
eq "a new binary (mtime): asks claude again" 2.1.309 "$(jay_claude_version)"
echo 2.1.308 >"$STUB/version" && touch -t 203001020000 "$HOME/.local/bin/claude"

# --- jay_running_versions: the binary path under the agent's pty host ---
pty() { echo "$1 1 claude bg-pty-host --bg-pty-host /tmp/cc/spare/$1.pty.sock 200 50 -- $2 --bg-spare /tmp/cc/spare/$1.claim.sock"; }
spare() { echo "$1 $2 claude bg-spare --bg-spare /tmp/cc/spare/$1.claim.sock"; }
native="$HOME/.local/share/claude/versions"
cat >"$STUB/ps.txt" <<EOF
$(pty 900 "$native/2.1.300")
$(spare 1001 900)
$(pty 901 "$native/2.1.308")
$(spare 1002 901)
$(pty 902 /opt/homebrew/Caskroom/claude-code/2.1.301/claude)
$(spare 1003 902)
903 1 node $HOME/.local/share/mise/installs/node/24.18.0/bin/node /usr/lib/cli.js
$(spare 1004 903)
1005 1 $native/2.1.299 --bg
EOF
bg() { # bg ID PID [more JSON]: a running background agent, idle
  local more=${3:-}
  [[ -n "$more" ]] || more='{}'
  jq -nc --arg id "$1" --arg pid "$2" --argjson more "$more" '{kind: "background", id: $id,
    sessionId: ("sid-" + $id), name: ("acme/" + $id), cwd: env.HOME, state: "done", status: "idle",
    startedAt: 1, pid: (if $pid == "" then null else ($pid | tonumber) end)} + $more'
}
vers=$(jay_running_versions "$(jq -sc . <<EOF
$(bg a1 1001)
$(bg a2 1002)
$(bg a3 1003)
$(bg a4 1004)
$(bg a5 1005)
$(bg a6 "")
EOF
)")
eq "native: the version in versions/<v>" 2.1.300 "$(jq -r .a1 <<<"$vers")"
eq "native: the installed one" 2.1.308 "$(jq -r .a2 <<<"$vers")"
eq "Homebrew: the version in the Caskroom path" 2.1.301 "$(jq -r .a3 <<<"$vers")"
eq "not a claude path (node): no version" null "$(jq -r .a4 <<<"$vers")"
eq "the binary as the process itself" 2.1.299 "$(jq -r .a5 <<<"$vers")"
eq "not running: no version" null "$(jq -r .a6 <<<"$vers")"

# --- jay_stale and jay_respawn_plan ---
root="$HOME/Documents/projects/acme"
web="$root/web"
repo "$web" && git -C "$web" worktree add -q "$root/web.fix" -b fix
cat >"$STUB/ps.txt" <<EOF
$(pty 900 "$native/2.1.300")
$(pty 901 "$native/2.1.308")
$(for p in 1001 1003 1004 1005 1006 1007 1008 1009 1010 1012 1013 1014 1015 1016 1017 1018 1020; do spare $p 900; done)
$(spare 1002 901)
$(spare 1011 901)
$(spare 1019 901)
1100 1 claude attach r07
1101 1 claude attach acme/r08
EOF
state() { # state ID JSON: state.json of a job, with createdAt and cwd defaults
  job "$1" "$(jq -nc --arg c "$HOME" --argjson s "$2" '{cwd: $c, createdAt: "2026-10-01T10:00:00.000Z", cliVersion: "2.1.300", tempo: "idle", inFlight: {tasks: 0, queued: 0, kinds: []}} + $s')"
}
orchflags=$(jq -nc --arg p "$(jay_orchestrator_prompt web "$web")" '["--name", "web/main", "--append-system-prompt", $p]')
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20; do state "r$i" '{}'; done
state r04 '{"tempo": "active"}'
state r05 '{"inFlight": {"tasks": 1, "queued": 0, "kinds": ["monitor"]}}'
state r09 "{\"cwd\": \"$root/gone\"}"
state r12 "{\"cwd\": \"$web\", \"respawnFlags\": $orchflags}"
state r13 "{\"cwd\": \"$root/web.fix\"}"
state r17 '{"tempo": "blocked"}'
state r18 '{"inFlight": {"tasks": 1, "queued": 0, "kinds": ["session_cron"], "wake": {"at": 1}}}'
state r19 '{"cliVersion": "2.1.300"}'
agents=$(jq -sc . <<EOF
$(bg r01 1001)
$(bg r02 1002)
$(bg r03 "")
$(bg r04 1004 '{"state": "working", "status": "busy"}')
$(bg r05 1005 '{"state": "working", "status": "busy"}')
$(bg r06 1006)
$(bg r07 1007)
$(bg r08 1008)
$(bg r09 1009)
$(bg r10 1010)
$(bg r12 1012 "{\"cwd\": \"$web\"}")
$(bg r13 1013 "{\"cwd\": \"$root/web.fix\", \"state\": \"working\", \"status\": \"busy\"}")
$(bg r14 1014)
$(bg r15 1015 '{"state": "failed"}')
$(bg r16 1016 '{"state": "blocked", "status": "waiting"}')
$(bg r17 1017 '{"state": "blocked"}')
$(bg r18 1018 '{"state": "working"}')
$(bg r19 "")
{"kind": "interactive", "sessionId": "sid-inter", "cwd": "$HOME", "status": "idle", "pid": 1020}
EOF
)
stub_agents "$agents"
mkdir -p "$JAY_STATE/replaced" "$JAY_STATE/respawned"
echo r99 >"$JAY_STATE/replaced/r10"
echo 2.1.308 >"$JAY_STATE/respawned/r14"
echo r14 >"$JAY_HUB_CLAUDE_FILE"
phased=$(jay_agent_phases "$agents" r06)
jobs=$(jay_jobs "$phased")
stale=$(jay_stale "$phased" "$jobs")
eq "jay_jobs: created, from createdAt" 1790848800000 "$(jq '.r01.created' <<<"$jobs")"
eq "jay_jobs: tasks, a wakeup counts" 2 "$(jq '.r18.tasks' <<<"$jobs")"
eq "jay_jobs: cwd, the folder it wakes in" "$root/gone" "$(jq -r '.r09.cwd' <<<"$jobs")"
eq "stale: an old binary" 2.1.300 "$(jq -r .r01 <<<"$stale")"
eq "stale: not the installed binary" null "$(jq -r .r02 <<<"$stale")"
eq "stale: not one that does not run (it wakes on the new binary)" null "$(jq -r .r03 <<<"$stale")"
eq "stale: not an interactive session" 0 "$(jq '[to_entries[] | select(.key | startswith("sid"))] | length' <<<"$stale")"
eq "stale: no process version, cliVersion old" 2.1.300 "$(jay_stale "$(bg r19 4242 | jq -sc .)" "$jobs" | jq -r .r19)"
echo 2.1.308 >"$JAY_STATE/respawned/r19"
touch -t 202601010000 "$JAY_STATE/respawned/r19"
eq "stale: no process version, but the hub respawned it onto the installed one" '{}' \
  "$(jay_stale "$(bg r19 4242 | jq -sc .)" "$jobs")"

plan=$(jay_respawn_plan "$phased" "$jobs" "$stale" r06)
why() { awk -F'\t' -v i="$1" '$1 == i { print $4 }' <<<"$plan"; }
inplan() { awk -F'\t' -v i="$1" '$1 == i { print "yes" }' <<<"$plan"; }
eq "rule: idle, quiet: respawns" "" "$(why r01)"
has "rule: the plan names it, its version" "$(printf 'r01\tacme/r01\t2.1.300\t')" "$plan"
eq "rule: not in the plan when on the installed binary" "" "$(inplan r02)"
eq "rule: a turn runs" "a turn runs" "$(why r04)"
eq "rule: background tasks" "it has background tasks, crons or wakeups" "$(why r05)"
eq "rule: shown in the middle column" "it is in the hub's middle column" "$(why r06)"
eq "rule: a claude attach client (id)" "a claude attach client shows it" "$(why r07)"
eq "rule: a claude attach client (name)" "a claude attach client shows it" "$(why r08)"
eq "rule: the folder it wakes in is gone" "its folder is gone: $root/gone" "$(why r09)"
eq "rule: a replaced entry" "a copy replaced it" "$(why r10)"
eq "rule: an orchestrator while a worker of its repo works" "an orchestrator, and agents of its repo work" "$(why r12)"
has "rule: respawned in the last 10 minutes" "respawned 0 min ago" "$(why r14)"
eq "rule: failed" "it failed" "$(why r15)"
eq "rule: waits for an answer in a turn" "it waits for an answer in a turn" "$(why r16)"
eq "rule: asked you something at the end of a turn" "it asked you something" "$(why r17)"
eq "rule: a wakeup (ScheduleWakeup) counts as a task" "it has background tasks, crons or wakeups" "$(why r18)"
# The hub Claude while another agent works.
rm -f "$JAY_STATE/respawned/r14"
plan=$(jay_respawn_plan "$phased" "$jobs" "$stale" r06)
eq "rule: the hub Claude while other agents work" "the hub Claude, and other agents work" "$(why r14)"
# Without the working worker, the orchestrator and the hub Claude may go.
quiet=$(jq -c 'map(select(.id | IN("r04", "r05", "r13", "r16", "r17") | not))' <<<"$phased")
plan=$(jay_respawn_plan "$quiet" "$jobs" "$stale" r06)
eq "rule: an orchestrator whose workers are quiet" "" "$(why r12)"
eq "rule: the hub Claude when no other agent works" "" "$(why r14)"
# --force keeps only the hard reasons.
plan=$(jay_respawn_plan "$phased" "$jobs" "$stale" r06 force)
eq "force: background tasks no longer stop it" "" "$(why r05)"
eq "force: shown no longer stops it" "" "$(why r06)"
eq "force: attached no longer stops it" "" "$(why r07)"
eq "force: asked something no longer stops it" "" "$(why r17)"
eq "force: a turn runs still stops it" "a turn runs" "$(why r04)"
eq "force: waits for an answer in a turn still stops it" "it waits for an answer in a turn" "$(why r16)"
eq "force: a gone folder still stops it" "its folder is gone: $root/gone" "$(why r09)"
eq "force: a replaced entry still stops it" "a copy replaced it" "$(why r10)"

# --- jay_orch_ranks: by the job's creation, not startedAt (a respawn changes startedAt) ---
state o1 "{\"cwd\": \"$web\", \"createdAt\": \"2026-10-01T10:00:00.000Z\", \"respawnFlags\": $orchflags}"
state o2 "{\"cwd\": \"$web\", \"createdAt\": \"2026-10-02T10:00:00.000Z\", \"respawnFlags\": $orchflags}"
two=$(jq -sc . <<EOF
$(bg o1 "" "{\"cwd\": \"$web\", \"startedAt\": 9000}")
$(bg o2 "" "{\"cwd\": \"$web\", \"startedAt\": 100}")
EOF
)
eq "the orchestrator: the oldest job, also after a respawn" 0 "$(jay_orch_ranks "$two" "$(jay_jobs "$two")" | jq '.["sid-o1"].rank')"

# --- jay_respawn: claude respawn, the mark, the log ---
: >"$STUB/claude.calls"
out=$(jay_respawn r01 acme/r01 2.1.300)
eq "jay_respawn: Claude's output" "respawned r01" "$out"
has "jay_respawn: claude respawn <id>" "respawn r01" "$(cat "$STUB/claude.calls")"
eq "jay_respawn: the mark has the version" 2.1.308 "$(cat "$JAY_STATE/respawned/r01")"
has "jay_respawn: the log" "r01 (acme/r01): respawn 2.1.300 → 2.1.308: respawned r01" "$(cat "$JAY_STATE/prune.log")"
echo "respawned r14 → 0000aa77" >"$STUB/respawn.out"
jay_respawn r14 hub 2.1.300 >/dev/null
eq "jay_respawn: a new short id of the hub Claude goes to its id file" 0000aa77 "$(cat "$JAY_HUB_CLAUDE_FILE")"
rm -f "$STUB/respawn.out"
: >"$STUB/respawn.fail"
no "jay_respawn: fails when claude respawn fails" jay_respawn r09 acme/r09 2.1.300
ok "jay_respawn: a failed one is marked too (the next try waits)" test -f "$JAY_STATE/respawned/r09"
has "jay_respawn: the failure in the log" "r09 (acme/r09): respawn 2.1.300 → 2.1.308: Workspace not trusted." "$(cat "$JAY_STATE/prune.log")"
rm -f "$STUB/respawn.fail" "$JAY_STATE"/respawned/* "$JAY_STATE/prune.log"
echo r14 >"$JAY_HUB_CLAUDE_FILE"

# --- jay_respawn_auto: the setting, once a minute, only the ones the rule lets ---
: >"$STUB/claude.calls"
JAY_AUTO_RESPAWN=off jay_respawn_auto "$phased" "$jobs" r06 "$stale"
eq "auto: off does nothing" "" "$(grep respawn "$STUB/claude.calls")"
jay_respawn_auto "$phased" "$jobs" r06 "$stale"
eq "auto: respawns only the agent that passes the rule" "respawn r01" "$(grep respawn "$STUB/claude.calls")"
: >"$STUB/claude.calls"
rm -f "$JAY_STATE/respawned/r01"
jay_respawn_auto "$phased" "$jobs" r06 "$stale"
eq "auto: not again within a minute" "" "$(grep respawn "$STUB/claude.calls")"
touch -t 202601010000 "$JAY_STATE/respawn.stamp"
jay_respawn_auto "$phased" "$jobs" r06 '{}'
eq "auto: nothing stale, nothing to do" "" "$(grep respawn "$STUB/claude.calls")"

# --- jay respawn ---
rm -f "$JAY_STATE"/respawned/*
out=$(jay respawn 2>&1)
has "jay respawn: lists the stale agents" "Agents on an old Claude Code (installed: 2.1.308):" "$out"
has "jay respawn: a ready one" "ready: respawns now with --idle" "$(grep r01 <<<"$out")"
has "jay respawn: why one waits" "a turn runs" "$(grep r04 <<<"$out")"
out=$(jay respawn r04 2>&1)
has "jay respawn <id>: why not" "Not respawned: a turn runs." "$out"
out=$(jay respawn acme/r05 2>&1)
has "jay respawn <name>: why not" "Not respawned: it has background tasks, crons or wakeups." "$out"
has "jay respawn <id>: offers --force" "jay respawn --force r05" "$out"
out=$(jay respawn r02 2>&1)
has "jay respawn <id> on the installed version: nothing to do" "runs Claude Code 2.1.308, the installed version" "$out"
out=$(jay respawn r03 2>&1)
has "jay respawn <id> that does not run" "does not run: it wakes on Claude Code 2.1.308" "$out"
no "jay respawn: an unknown agent" jay respawn nobody
: >"$STUB/claude.calls"
out=$(jay respawn --force r05 2>&1)
has "jay respawn --force: respawns despite the background tasks" "Respawning \"acme/r05\" (r05): Claude Code 2.1.300 → 2.1.308" "$out"
eq "jay respawn --force: one claude respawn" "respawn r05" "$(grep respawn "$STUB/claude.calls")"
no "jay respawn --force: never during a turn" jay respawn --force r04
: >"$STUB/claude.calls"
out=$(jay respawn --idle 2>&1)
has "jay respawn --idle: respawns the ready ones" "Respawning acme/r01 (r01): 2.1.300 → 2.1.308" "$out"
has "jay respawn --idle: says why the others wait" "acme/r04 (r04) waits: a turn runs" "$out"
# r06 too: no hub pane shows it now. r05 respawned a moment ago.
eq "jay respawn --idle: only the ready ones" "respawn r01 respawn r06" "$(grep respawn "$STUB/claude.calls" | tr '\n' ' ' | sed 's/ $//')"
no "jay respawn: --force needs an agent" jay respawn --force

# --- The list: ↻ after an agent on an old binary, and the count in the first row ---
rec() { # rec PATH MAIN BRANCH REPO
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" --arg r "$4" '{path: $p, main: $m, branch: $b,
    client: "acme", repo: $r, task: "", symbols: "", git: {added: 0, deleted: 0, staged: false,
    modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
{ rec "$web" true main web; rec "$root/web.fix" false fix web; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp" "$JAY_STATE/respawn.stamp"
two=$(jq -sc . <<EOF
$(bg r12 1012 "{\"cwd\": \"$web\", \"name\": \"web/main\"}")
$(bg r13 1002 "{\"cwd\": \"$root/web.fix\", \"name\": \"web/fix\"}")
EOF
)
stub_agents "$two"
rows=$(FZF_COLUMNS=80 JAY_SIDEBAR_SUM="$TMP/sum" jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
has "list: ↻ after an agent on an old binary" $'web/main \e[2m↻\e[0m' "$(row sid-r12)"
hasnt "list: no ↻ on the installed binary" "↻" "$(row sid-r13)"
has "the counts for the status line: the ↻ count" $'\e[2m↻ 1' "$(cat "$TMP/sum")"
eq "the list has no counts row (the status line has them)" "" "$(row sum)"
eq "the list's first row: ◆ hub" hub "$(head -1 <<<"$rows" | cut -f2)"
has "list: ↻ in the help (?)" "↻" "$(JAY_SIDEBAR_HELP="$TMP/help" jay-sidebar --footer --toggle)"

finish

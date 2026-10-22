#!/bin/bash
# Agents that went into another worktree (EnterWorktree) and whose home (the folder they came
# from, where Claude wakes them) is removed or gone: jay_jobs finds where they are (worktreePath,
# the cwd of `claude agents`, or the last cwd in the transcript); d on the home moves them first
# (a copy in their worktree), the list marks the ones that cannot wake ("home gone", "lost") and a
# pick repairs them; jay go says what to do, jay go --repair repairs. jay_repo_main,
# jay_drop_replaced.
source "$(dirname "$0")/lib.sh"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop" a="$root/shop.a" b="$root/shop.b"
repo "$shop" && git -C "$shop" worktree add -q "$a" -b a && git -C "$shop" worktree add -q "$b" -b b

# The stub claude of lib.sh, plus: `--bg --resume <sid> <options>` starts a copy (its id from
# $STUB/next-id; the folder and options go to $STUB/bg.calls), `stop <id>` ends its process (no
# pid in agents.json), `rm <id>` leaves its call.
stub claude '
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "--bg --resume") printf "%s %s\n" "$PWD" "$*" >>"$STUB/bg.calls"
    printf "backgrounded · %s · copy\n" "$(cat "$STUB/next-id")" ;;
  "stop "*) jq --arg i "$2" "map(if .id == \$i then del(.pid) else . end)" "$STUB/agents.json" >"$STUB/a.tmp" \
    && mv "$STUB/a.tmp" "$STUB/agents.json" ;;
  "rm "*) exit 0 ;;
  *) exit 1 ;;
esac'
echo 0000c0de >"$STUB/next-id"

# transcript FILE CWD...: a transcript with one line for each folder (compact JSON, as Claude
# writes it), and one line without a cwd.
transcript() {
  local f=$1 d
  shift
  mkdir -p "$(dirname "$f")"
  for d in "$@"; do jq -nc --arg d "$d" '{type: "user", cwd: $d, message: {content: "cd \"cwd\":\"/nowhere\""}}'; done >"$f"
  echo '{"type":"summary"}' >>"$f"
}
proj="$HOME/.claude/projects/acme"
now=$(($(date +%s) * 1000))
agent() { # agent ID NAME CWD [PID] [STATE]
  jq -nc --arg id "$1" --arg n "$2" --arg c "$3" --arg pid "${4:-}" --arg st "${5:-done}" --argjson t "$now" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, startedAt: $t, state: $st, status: "idle"}
     + (if $pid != "" then {pid: ($pid | tonumber)} else {} end)'
}

# v1: runs in b, entered with the path of b (no worktreePath): `claude agents` gives b.
job 000000v1 "{\"cwd\": \"$a\", \"sessionId\": \"sid-000000v1\", \"respawnFlags\": [\"--name\", \"shop/one\", \"--model\", \"opus\"]}"
# v2: does not run, entered with the path of b: its transcript ends in b.
transcript "$proj/sid-000000v2.jsonl" "$a" "$a" "$b"
job 000000v2 "{\"cwd\": \"$a\", \"sessionId\": \"sid-000000v2\", \"linkScanPath\": \"$proj/sid-000000v2.jsonl\", \"name\": \"shop/two\", \"respawnFlags\": [\"--name\", \"shop/two\"]}"
# v3: does not run, in a worktree that EnterWorktree made (worktreePath).
job 000000v3 "{\"cwd\": \"$a\", \"sessionId\": \"sid-000000v3\", \"worktreePath\": \"$b\", \"respawnFlags\": [\"--model\", \"opus\", \"--name=shop/three\"], \"name\": \"shop/three\"}"
# v4: a cd in its own folder is no visit.
transcript "$proj/sid-000000v4.jsonl" "$b" "$b/sub"
job 000000v4 "{\"cwd\": \"$b\", \"sessionId\": \"sid-000000v4\", \"linkScanPath\": \"$proj/sid-000000v4.jsonl\"}"
# v5: no linkScanPath: the transcript of its resume session id, found in any project folder.
transcript "$HOME/.claude/projects/other/rs-000000v5.jsonl" "$a" "$b"
job 000000v5 "{\"cwd\": \"$a\", \"sessionId\": \"sid-000000v5\", \"resumeSessionId\": \"rs-000000v5\"}"
# v6: a worktree of Claude's own in its home (.claude/worktrees) is a visit.
transcript "$proj/sid-000000v6.jsonl" "$b" "$b/.claude/worktrees/x"
job 000000v6 "{\"cwd\": \"$b\", \"sessionId\": \"sid-000000v6\", \"linkScanPath\": \"$proj/sid-000000v6.jsonl\"}"
# v7: in its own folder, no transcript.
job 000000v7 "{\"cwd\": \"$b\", \"sessionId\": \"sid-000000v7\"}"
agents=$(jq -sc . <<EOF
$(agent 000000v1 shop/one "$b" 4242)
$(agent 000000v2 shop/two "$a")
$(agent 000000v3 shop/three "$a")
$(agent 000000v4 shop/four "$b")
$(agent 000000v5 shop/five "$a")
$(agent 000000v6 shop/six "$b")
$(agent 000000v7 shop/seven "$b")
EOF
)
stub_agents "$agents"

jobs=$(jay_jobs "$agents")
at() { jq -r --arg i "$1" '.[$i] | "\(.home) \(.tree)"' <<<"$jobs"; }
eq "jay_jobs: runs, entered by path: the folder of claude agents" "$a $b" "$(at 000000v1)"
eq "jay_jobs: does not run, entered by path: the last cwd of its transcript" "$a $b" "$(at 000000v2)"
eq "jay_jobs: worktreePath" "$a $b" "$(at 000000v3)"
eq "jay_jobs: a cd in its folder is no visit" "null null" "$(at 000000v4)"
eq "jay_jobs: the transcript of the resume session id" "$a $b" "$(at 000000v5)"
eq "jay_jobs: a worktree in .claude/worktrees of its folder" "$b $b/.claude/worktrees/x" "$(at 000000v6)"
eq "jay_jobs: no transcript, no visit" "null null" "$(at 000000v7)"

# d on a (their home): v1, v2, v3 and v5 are away; nothing is busy. v4, v6, v7 are not in a.
in_a=$(jay-sidebar --agents-in "$a")
eq "d on the home: the agents that are away" "000000v1 000000v2 000000v3 000000v5" \
  "$(awk -F'\t' '$1 == "away" { printf "%s ", $2 }' <<<"$in_a" | sed 's/ $//')"
eq "d on the home: an away agent's tree and process" "$b	1" "$(awk -F'\t' '$2 == "000000v1" { print $4 "\t" $5 }' <<<"$in_a")"
# d on b (where they are): they are visits there, as before.
in_b=$(jay-sidebar --agents-in "$b")
eq "d on their worktree: visits" "visit" "$(awk -F'\t' '$2 == "000000v2" { print $1 }' <<<"$in_b")"
# Stopped (state stopped) still counts: Claude would wake it in a.
stub_agents "$(jq -c 'map(if .id == "000000v2" then .state = "stopped" else . end)' <<<"$agents")"
has "d on the home: a stopped agent is away too" "away	000000v2" "$(jay-sidebar --agents-in "$a")"
stub_agents "$agents"

# The confirm of d on a names them and where they are; a key other than y changes nothing.
export TERM=dumb
# tty_run KEY CMD...: CMD in a pty 200 columns wide (the list folds its notes to the width); it
# gets KEY after 1 s, when it waits for an answer.
tty_run() {
  local key=$1
  shift
  (sleep 1; printf '%s' "$key") | script -q /dev/null sh -c 'stty cols 200; exec "$@"' sh "$@" 2>&1
}
out=$(tty_run n jay-sidebar --remove wt "$a")
has "the confirm says why" "Claude wakes an agent in the folder it came from" "$out"
has "the confirm names an agent and its worktree" "shop/two → ~/Documents/projects/acme/shop.b" "$out"
ok "no: a stays" test -d "$a"
no "no: no copy" test -s "$STUB/bg.calls"

# y: each goes on as a copy in b (v1 stops first), then a goes, then the old entries: v1, v2 and
# v5 have no recorded worktree (claude rm), v3 has b (it stays, marked replaced).
stub wt '[[ "$1 $3" == "-C remove" ]] && rm -rf "$2"'
: >"$STUB/claude.calls"
out=$(tty_run y jay-sidebar --remove wt "$a")
has "y: v1 stops first" "stop 000000v1" "$(cat "$STUB/claude.calls")"
eq "y: four copies, in b" 4 "$(grep -c "^$b --bg --resume" "$STUB/bg.calls")"
has "y: the copy has the saved options, the name first" "--bg --resume sid-000000v1 --name shop/one --model opus" "$(cat "$STUB/bg.calls")"
has "y: the transcript's session id (resumeSessionId)" "--bg --resume rs-000000v5 --name shop/five" "$(cat "$STUB/bg.calls")"
# v2 goes at once, so its copy keeps the name; v3 stays, so its copy gets another one.
has "y: the old entry goes: the copy keeps the name" "--resume sid-000000v2 --name shop/two" "$(cat "$STUB/bg.calls")"
has "y: the old entry stays: the copy gets its own name" "--resume sid-000000v3 --name shop/three-2 --model opus" "$(cat "$STUB/bg.calls")"
ok "y: a is removed" test ! -d "$a"
calls=$(cat "$STUB/claude.calls")
has "y: the old entry without a recorded worktree goes" "rm 000000v2" "$calls"
hasnt "y: never claude rm on an entry whose recorded worktree (b) is on disk" "rm 000000v3" "$calls"
ok "y: b stays" test -d "$b"
ok "y: v3 is marked replaced" test -f "$JAY_STATE/replaced/000000v3"
hasnt "y: the marks of removed entries go" "000000v2" "$(jay_replaced_ids)"

# The list after that: v3 (replaced) has no row; agents whose home is gone have a sign.
mkdir -p "$JAY_STATE"
rec() { # rec PATH MAIN BRANCH
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" '{path: $p, main: $m, branch: $b, client: "acme",
    repo: "shop", task: "", symbols: "", git: {added: 0, deleted: 0, staged: false, modified: false,
    untracked: false, conflicted: false, operation: null, state: (if $m then "is_main" else "ahead" end),
    ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
{ rec "$shop" true main; rec "$b" false b; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
gone="$root/shop.gone" gone2="$root/shop.gone2"
# s1: home gone, stopped, in b. s2: home gone, runs in b. s3: home and worktree gone.
job 000000s1 "{\"cwd\": \"$gone\", \"sessionId\": \"sid-000000s1\", \"worktreePath\": \"$b\", \"respawnFlags\": [\"--name\", \"shop/s1\"]}"
job 000000s2 "{\"cwd\": \"$gone\", \"sessionId\": \"sid-000000s2\"}"
job 000000s3 "{\"cwd\": \"$gone\", \"sessionId\": \"sid-000000s3\", \"worktreePath\": \"$gone2\"}"
stub_agents "$(jq -sc . <<EOF
$(agent 000000v3 shop/three "$a")
$(agent 000000s1 shop/s1 "$gone" "" stopped)
$(agent 000000s2 shop/s2 "$b" 4343)
$(agent 000000s3 shop/s3 "$gone")
EOF
)"
rows=$(FZF_COLUMNS=80 jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
eq "a replaced entry has no row" "" "$(row sid-000000v3)"
has "home gone: a yellow note, also when stopped" $'\e[33mhome gone' "$(row sid-000000s1)"
eq "home gone: a pick repairs it (fourth field)" repair "$(awk -F'\t' '$2 == "sid-000000s1" { print $4 }' <<<"$rows")"
has "home gone, runs: the note" "home gone" "$(row sid-000000s2)"
eq "home gone, runs: a pick shows it" "" "$(awk -F'\t' '$2 == "sid-000000s2" { print $4 }' <<<"$rows")"
has "home and worktree gone: red lost" $'\e[31mlost' "$(row sid-000000s3)"
order=$(awk -F'\t' '{ print $2 }' <<<"$rows" | grep -E "^($b|sid-000000s1)\$" | tr '\n' ' ')
eq "home gone: under the worktree it is in" "$b sid-000000s1 " "$order"
has "lost: under the (gone) row of its home" "gone:$gone" "$rows"

# The pick: a repair row repairs, another row acts (Enter with --focus).
eq "pick: repair" 'execute(jay-sidebar --repair {2})+reload-sync(jay-sidebar --rows --fresh)+clear-screen' \
  "$(jay-sidebar --pick --focus repair)"
eq "pick: Enter" 'execute-silent(jay-sidebar --act {1} {2} --focus)+reload-sync(jay-sidebar --rows)' \
  "$(jay-sidebar --pick --focus '')"
eq "pick: click" 'execute-silent(jay-sidebar --act {1} {2})+reload-sync(jay-sidebar --rows)' "$(jay-sidebar --pick '' '')"

# jay go: says what to do; --repair continues it.
out=$(jay-go 000000s1 2>&1)
eq "jay go: cannot wake: exit 1" 1 "$(jay-go 000000s1 >/dev/null 2>&1; echo $?)"
has "jay go: says why" "cannot wake" "$out"
has "jay go: says the repair" "jay go --repair 000000s1" "$out"
out=$(jay-go 000000s3 2>&1)
has "jay go, lost: resume in the main checkout" "continues it in the main checkout $shop" "$out"
has "jay go, lost: or remove" "claude rm 000000s3" "$out"
has "jay go --repair, runs: not now" "Repair it when it does not run" "$(jay-go --repair 000000s2 2>&1)"
: >"$STUB/bg.calls"
echo 0000beef >"$STUB/next-id"
out=$(jay-go --repair 000000s1 2>&1)
has "jay go --repair: the copy" "goes on in $b as 0000beef" "$out"
has "jay go --repair: in b, its own name (the old entry stays)" "$b --bg --resume sid-000000s1 --name shop/s1-2" "$(cat "$STUB/bg.calls")"
has "jay go --repair: the old entry stays while b is on disk" "The old entry 000000s1 stays" "$out"
: >"$STUB/bg.calls"
out=$(jay-go --repair 000000s3 2>&1)
has "jay go --repair, lost: in the main checkout" "$shop --bg --resume sid-000000s3" "$(cat "$STUB/bg.calls")"
hasnt "jay go --repair, lost: its recorded worktree is gone: the old entry goes" "stays" "$out"
has "jay go --repair, lost: claude rm" "rm 000000s3" "$(cat "$STUB/claude.calls")"
eq "jay go --repair, nothing to repair: exit 1" 1 "$(jay-go --repair 000000s2x >/dev/null 2>&1; echo $?)"

# The list's repair (a pick on a repair row): h only hides the old entry; on a lost one, x
# removes it. s4: home gone, in b. s5: home and worktree gone.
job 000000s4 "{\"cwd\": \"$gone\", \"sessionId\": \"sid-000000s4\", \"worktreePath\": \"$b\"}"
job 000000s5 "{\"cwd\": \"$gone\", \"sessionId\": \"sid-000000s5\", \"worktreePath\": \"$gone2\"}"
stub_agents "$(jq -sc . <<EOF
$(agent 000000s4 shop/s4 "$gone")
$(agent 000000s5 shop/s5 "$gone")
EOF
)"
: >"$STUB/bg.calls"
: >"$STUB/claude.calls"
out=$(tty_run n jay-sidebar --repair sid-000000s4)
has "repair: says why" "cannot wake: Claude wakes an agent in the folder it came from" "$out"
has "repair: offers to hide" "h: hide the old entry only" "$out"
no "repair, no: nothing hidden" test -f "$JAY_STATE/replaced/000000s4"
tty_run h jay-sidebar --repair sid-000000s4 >/dev/null
ok "repair, h: hidden" test -f "$JAY_STATE/replaced/000000s4"
no "repair, h: no copy" test -s "$STUB/bg.calls"
hasnt "repair, h: never claude rm while its worktree is on disk" "rm 000000s4" "$(cat "$STUB/claude.calls")"
eq "repair, h: no row" "" "$(FZF_COLUMNS=80 jay-sidebar --rows | awk -F'\t' '$2 == "sid-000000s4"')"
out=$(tty_run x jay-sidebar --repair sid-000000s5)
has "repair, lost: offers the main checkout" "m: continue it in the main checkout ~/Documents/projects/acme/shop" "$out"
has "repair, lost, x: claude rm" "rm 000000s5" "$(cat "$STUB/claude.calls")"
no "repair, lost, x: no copy" test -s "$STUB/bg.calls"
has "repair: a row that can wake" "Nothing to repair" "$(tty_run n jay-sidebar --repair sid-nobody)"

# jay_repo_main: the main checkout for gone folders.
eq "jay_repo_main: a gone <repo>.<branch>" "$shop" "$(jay_repo_main "$gone")"
eq "jay_repo_main: a gone folder in the repo" "$shop" "$(jay_repo_main "$shop/.claude/worktrees/x")"
eq "jay_repo_main: a worktree" "$shop" "$(jay_repo_main "$b")"
eq "jay_repo_main: no repo" "" "$(jay_repo_main "$HOME/nowhere/x.y")"

# jay_drop_replaced: v3 stays while b is on disk, and goes with it.
no "drop: kept while the recorded worktree is on disk" jay_drop_replaced 000000v3
rm -rf "$b"
ok "drop: removed after the worktree went" jay_drop_replaced 000000v3
ok "drop: the mark goes" test ! -f "$JAY_STATE/replaced/000000v3"

finish

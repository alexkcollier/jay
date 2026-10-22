#!/bin/bash
# jay renew (bin/jay-renew) and c in the list (jay-sidebar --clear): /clear keeps an agent's system
# prompt, so an orchestrator or the hub Claude with an older prompt than jay's gets a dim ⇡ in the
# list, and c offers a new agent with the current prompt and the same name in place of the old
# one. jay_prompt_stored, jay_prompt_now, jay_prompt_old, jay_old_prompts, the renewed rank
# (jay_orch_ranks), and the prune of old task notes and renewed marks (jay_prune_agent_files).
source "$(dirname "$0")/lib.sh"
export JAY_ROOTS="$HOME/Documents/projects:$HOME/work"
link_install
source "$HOME/.local/lib/jay-lib.sh"

root="$HOME/Documents/projects/acme"
shop="$root/shop" web="$root/web"
repo "$shop" && git -C "$shop" worktree add -q "$root/shop.feat" -b feat
repo "$web" && git -C "$web" worktree add -q "$root/web.fix" -b fix
mkdir -p "$HOME/work"

# The stub claude of lib.sh, with state: `--bg <options>` starts an agent (its id from
# $STUB/next-id; the folder and options go to $STUB/bg.calls) and writes its job's state.json
# (respawnFlags: the options); `stop <id>` ends its process (no pid); `rm <id>` removes it.
cat >"$HOME/.local/bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB/claude.calls"
jobs="$HOME/.claude/jobs"
case "${1:-} ${2:-}" in
  "agents --json") cat "$STUB/agents.json" 2>/dev/null || echo "[]" ;;
  "--version "*) echo "2.1.306 (Claude Code)" ;;
  "--bg "*)
    printf '%s %s\n' "$PWD" "$*" >>"$STUB/bg.calls"
    id=$(cat "$STUB/next-id")
    shift
    flags=$(jq -nc '$ARGS.positional' --args -- "$@")
    name=$(jq -r 'index("--name") as $i | .[$i + 1]' <<<"$flags")
    mkdir -p "$jobs/$id"
    jq -nc --arg c "$PWD" --arg s "sid-$id" --argjson f "$flags" \
      '{cwd: $c, sessionId: $s, respawnFlags: $f, createdAt: "2026-10-22T12:00:00.000Z"}' >"$jobs/$id/state.json"
    jq --arg i "$id" --arg n "$name" --arg c "$PWD" \
      '. + [{kind: "background", id: $i, sessionId: ("sid-" + $i), name: $n, cwd: $c, pid: 4242,
             startedAt: 0, state: "done", status: "idle"}]' "$STUB/agents.json" >"$STUB/a.tmp" \
      && mv "$STUB/a.tmp" "$STUB/agents.json"
    printf 'backgrounded · %s · %s\n' "$id" "$name" ;;
  "stop "*) jq --arg i "$2" 'map(if .id == $i then del(.pid) else . end)' "$STUB/agents.json" >"$STUB/a.tmp" \
    && mv "$STUB/a.tmp" "$STUB/agents.json" ;;
  "rm "*) [[ -f "$STUB/rm.fail" ]] && { echo "has unpushed work"; exit 1; }
    jq --arg i "$2" 'map(select(.id != $i))' "$STUB/agents.json" >"$STUB/a.tmp" && mv "$STUB/a.tmp" "$STUB/agents.json"
    rm -rf "${jobs:?}/$2" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$HOME/.local/bin/claude"
# jay-clear types /clear through `claude attach`: here it only leaves its call. It is a link into
# the repo, so the link goes first (a write through it would change bin/jay-clear).
rm -f "$HOME/.local/bin/jay-clear"
stub jay-clear 'exit 0'

# tty_run KEY CMD...: CMD in a pty 200 columns wide; it gets KEY after 1 s, when it waits for an
# answer.
tty_run() {
  local key=$1
  shift
  (sleep 1; printf '%s' "$key") | script -q /dev/null sh -c 'stty cols 200; exec "$@"' sh "$@" 2>&1
}

orch_flags() { # orch_flags NAME PROMPT [OPTIONS...]
  local n=$1 p=$2
  shift 2
  jq -nc --arg n "$n" --arg p "$p" '["--name", $n, "--append-system-prompt", $p] + $ARGS.positional' --args -- "$@"
}
now=$(($(date +%s) * 1000))
agent() { # agent ID NAME CWD [STATE] [STATUS]
  jq -nc --arg id "$1" --arg n "$2" --arg c "$3" --arg st "${4:-done}" --arg s "${5:-idle}" --argjson t "$now" \
    '{kind: "background", id: $id, sessionId: ("sid-" + $id), name: $n, cwd: $c, pid: 100, startedAt: $t, state: $st, status: $s}'
}
old_orch="You are the orchestrator of the repo shop, in its main checkout $shop. An older text."
old_hub="You are the hub Claude of a worktree hub: an older text."
# o1: shop's orchestrator, old prompt (created first). o2: an extra one in shop, current prompt
# (created later). o3: web's orchestrator, current prompt. p1: no prompt. hb: the hub Claude, old
# prompt, with an added folder of an older JAY_ROOTS. o4: web's orchestrator prompt, in a worktree
# that Claude recorded for it (worktreePath).
job 000000o1 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-000000o1\", \"createdAt\": \"2026-10-01T10:00:00.000Z\",
  \"respawnFlags\": $(orch_flags shop/main "$old_orch" --model opus)}"
job 000000o2 "{\"cwd\": \"$shop\", \"sessionId\": \"sid-000000o2\", \"createdAt\": \"2026-10-02T10:00:00.000Z\",
  \"respawnFlags\": $(orch_flags shop/main-2 "$(jay_orchestrator_prompt shop "$shop")")}"
job 000000o3 "{\"cwd\": \"$web\", \"sessionId\": \"sid-000000o3\", \"createdAt\": \"2026-10-01T10:00:00.000Z\",
  \"respawnFlags\": $(orch_flags web/main "$(jay_orchestrator_prompt web "$web")")}"
job 000000p1 "{\"cwd\": \"$root/shop.feat\", \"sessionId\": \"sid-000000p1\", \"respawnFlags\": [\"--name\", \"shop/feat\"]}"
job 000000hb "{\"cwd\": \"$HOME/Documents/projects\", \"sessionId\": \"sid-000000hb\",
  \"respawnFlags\": $(orch_flags hub "$old_hub" --add-dir /old/root --model opus)}"
job 000000o4 "{\"cwd\": \"$web\", \"sessionId\": \"sid-000000o4\", \"worktreePath\": \"$root/web.fix\",
  \"respawnFlags\": $(orch_flags web/main-2 "$old_orch")}"
stub_agents "$(jq -sc . <<EOF
$(agent 000000o1 shop/main "$shop")
$(agent 000000o2 shop/main-2 "$shop")
$(agent 000000o3 web/main "$web")
$(agent 000000p1 shop/feat "$root/shop.feat")
$(agent 000000hb hub "$HOME/Documents/projects")
$(agent 000000o4 web/main-2 "$root/web.fix")
EOF
)"
mkdir -p "$JAY_STATE"
printf '000000hb\n' >"$JAY_HUB_CLAUDE_FILE"

# --- Which prompt an agent has, and which one jay gives now ---
eq "stored: the value of --append-system-prompt" "$old_orch" "$(jay_prompt_stored 000000o1)"
eq "stored: none" "" "$(jay_prompt_stored 000000p1)"
eq "now: an orchestrator's, for its main checkout" "$(jay_orchestrator_prompt shop "$shop")" "$(jay_prompt_now 000000o1)"
eq "now: the hub Claude's" "$(jay_hub_claude_prompt)" "$(jay_prompt_now 000000hb)"
no "now: none for another agent" jay_prompt_now 000000p1
ok "old: an orchestrator with an older prompt" jay_prompt_old 000000o1
no "old: an orchestrator with the current prompt" jay_prompt_old 000000o2
ok "old: the hub Claude with an older prompt" jay_prompt_old 000000hb
no "old: no prompt from jay" jay_prompt_old 000000p1
agents=$(cat "$STUB/agents.json")
jobs=$(jay_jobs "$agents")
eq "jay_old_prompts: the orchestrators and the hub Claude with an older prompt" \
  '["000000hb","000000o1","000000o4"]' "$(jay_old_prompts "$agents" "$jobs" | jq -c 'keys')"

# --- The list: a dim ⇡ after them ---
rec() { # rec PATH MAIN BRANCH REPO
  jq -nc --arg p "$1" --argjson m "$2" --arg b "$3" --arg r "$4" '{path: $p, main: $m, branch: $b,
    client: "acme", repo: $r, task: "", symbols: "", git: {added: 0, deleted: 0, staged: false,
    modified: false, untracked: false, conflicted: false, operation: null,
    state: (if $m then "is_main" else "ahead" end), ahead: 1, behind: 0, remote: false, push: 0, pull: 0}}'
}
{ rec "$shop" true main shop; rec "$root/shop.feat" false feat shop
  rec "$web" true main web; rec "$root/web.fix" false fix web; } >"$JAY_STATE/worktrees.ndjson"
touch "$JAY_STATE/prune.stamp"
rows=$(FZF_COLUMNS=80 jay-sidebar --rows)
row() { awk -F'\t' -v s="$1" '$2 == s { print $3 }' <<<"$rows"; }
MARK=$' \e[2m⇡\e[0m'
has "list: ⇡ after an orchestrator with an older prompt" "shop/main$MARK" "$(row sid-000000o1)"
hasnt "list: no ⇡ after one with the current prompt" "⇡" "$(row sid-000000o2)"
hasnt "list: no ⇡ after another agent" "⇡" "$(row sid-000000p1)"
has "list: ⇡ on the ◆ hub row" "$MARK" "$(row hub)"
has "list: ? names ⇡" "old prompt: c renews it" "$(JAY_SIDEBAR_HELP="$TMP/help" jay-sidebar --footer --toggle)"

# --- Refusals ---
: >"$STUB/bg.calls"
: >"$STUB/claude.calls"
out=$(jay-renew 000000o4 2>&1)
eq "refused: in a worktree it entered: exit 3" 3 "$(jay-renew 000000o4 >/dev/null 2>&1; echo $?)"
has "refused: in a worktree it entered: says so" "is in a worktree it entered: ~/Documents/projects/acme/web.fix" "$out"
out=$(jay-renew shop/feat 2>&1)
has "refused: no orchestrator or hub Claude" "jay renew is for those" "$out"
out=$(jay-renew nobody 2>&1)
has "refused: no such agent" "no running background agent nobody" "$out"
eq "jay renew without an agent: usage, exit 2" 2 "$(jay-renew >/dev/null 2>&1; echo $?)"
# o1 works now: not renewed.
stub_agents "$(jq -c 'map(if .id == "000000o1" then .state = "working" | .status = "busy" else . end)' <<<"$agents")"
has "refused: it works" "is working. Try again when it is idle." "$(jay-renew 000000o1 2>&1)"
stub_agents "$agents"
eq "refused: no new agent" "" "$(cat "$STUB/bg.calls")"
hasnt "refused: nothing removed" "rm " "$(cat "$STUB/claude.calls")"

# --- The same prompt: /clear, as before ---
out=$(jay-renew 000000o2 2>&1)
has "jay renew, the current prompt: nothing to do" "has jay's current prompt. jay clear 000000o2" "$out"
eq "jay renew, the current prompt: no new agent" "" "$(cat "$STUB/bg.calls")"
: >"$STUB/jay-clear.calls"
out=$(tty_run y jay-sidebar --clear ag sid-000000o2)
has "c, the current prompt: the /clear confirm" "y: clear" "$out"
hasnt "c, the current prompt: no k" "k: fresh context" "$out"
eq "c, the current prompt, y: jay clear" "000000o2" "$(cat "$STUB/jay-clear.calls")"
eq "c, the current prompt: no new agent" "" "$(cat "$STUB/bg.calls")"

# --- An older prompt: c offers both; k is /clear ---
: >"$STUB/jay-clear.calls"
out=$(tty_run k jay-sidebar --clear ag sid-000000o1)
has "c, older prompt: offers a renew" "y: fresh context with the current prompt (a new agent, same name; the old one is removed)" "$out"
has "c, older prompt: offers /clear" "k: fresh context, keep the old prompt (/clear)" "$out"
eq "c, older prompt, k: jay clear" "000000o1" "$(cat "$STUB/jay-clear.calls")"
eq "c, older prompt, k: no new agent" "" "$(cat "$STUB/bg.calls")"
: >"$STUB/jay-clear.calls"
tty_run n jay-sidebar --clear ag sid-000000o1 >/dev/null
eq "c, older prompt, other key: nothing" "" "$(cat "$STUB/jay-clear.calls")$(cat "$STUB/bg.calls")"

# --- y: the renew ---
jay_agent_note 000000o1 "plan the shop release"
printf '000000o1\t%s\tbackground\tshop/main\n' "$shop" >"$(jay_hub_target_file agent)"
printf '%s\t000000o1\n' "$shop" >"$(jay_hub_target_file review)"
echo 0000ee01 >"$STUB/next-id"
: >"$STUB/claude.calls"
tty_run y jay-sidebar --clear ag sid-000000o1 >/dev/null
calls=$(cat "$STUB/bg.calls")
has "renew: a new agent in the main checkout, same name, its options, the current prompt" \
  "$shop --bg --name shop/main --model opus --append-system-prompt You are the orchestrator of the repo shop, in its main checkout $shop, in jay" "$calls"
eq "renew: the new agent has the current prompt" "$(jay_orchestrator_prompt shop "$shop")" "$(jay_prompt_stored 0000ee01)"
no "renew: so no ⇡" jay_prompt_old 0000ee01
eq "renew: no jay clear" "" "$(cat "$STUB/jay-clear.calls")"
has "renew: the old agent stops" "stop 000000o1" "$(cat "$STUB/claude.calls")"
has "renew: the old agent is removed" "rm 000000o1" "$(cat "$STUB/claude.calls")"
eq "renew: one shop/main, the new one" "0000ee01" "$(jq -r '.[] | select(.name == "shop/main") | .id' "$STUB/agents.json")"
eq "renew: the middle column's target" "0000ee01" "$(cut -f1 "$(jay_hub_target_file agent)")"
eq "renew: the target keeps its folder and name" "$shop background shop/main" "$(cut -f2- "$(jay_hub_target_file agent)" | tr '\t' ' ')"
eq "renew: review's target" "0000ee01" "$(cut -f2 "$(jay_hub_target_file review)")"
eq "renew: the task note moves" "plan the shop release" "$(jq -r '.["0000ee01"] // empty' <<<"$(jay_agent_notes)")"
no "renew: no note of the old id" test -f "$JAY_NOTES/000000o1"
eq "renew: the hub Claude's id stays" "000000hb" "$(jay_hub_claude_id)"
has "renew: prune.log" "000000o1 (shop/main): renew → 0000ee01" "$(cat "$JAY_STATE/prune.log")"
# The new agent keeps the rank of the old one: before o2, which is older than the new job.
agents=$(cat "$STUB/agents.json")
ranks=$(jay_orch_ranks "$agents" "$(jay_jobs "$agents")")
eq "renew: still the orchestrator (rank 0, by the old createdAt)" 0 "$(jq '.["sid-0000ee01"].rank' <<<"$ranks")"
eq "renew: the extra one stays rank 1" 1 "$(jq '.["sid-000000o2"].rank' <<<"$ranks")"

# --- The hub Claude, by name; the old agent cannot be removed ---
echo 0000ee02 >"$STUB/next-id"
: >"$STUB/bg.calls"
: >"$STUB/rm.fail"
out=$(jay-renew hub 2>&1)
rc=$?
rm -f "$STUB/rm.fail"
calls=$(cat "$STUB/bg.calls")
has "hub: in the first root, same name, the other roots as added folders, its model" \
  "$HOME/Documents/projects --bg --name hub --model opus --add-dir $HOME/work --append-system-prompt You are the hub Claude" "$calls"
hasnt "hub: not the added folder of an older JAY_ROOTS" "/old/root" "$calls"
eq "hub: the hub Claude's id file" "0000ee02" "$(jay_hub_claude_id)"
eq "hub: claude rm fails: exit 1" 1 "$rc"
has "hub: claude rm fails: says so" "The old agent 000000hb is stopped, not removed: has unpushed work" "$out"

# --- The prune of old task notes and renewed marks ---
mkdir -p "$JAY_NOTES" "$JAY_RENEWED"
for f in "$JAY_NOTES/000000x1" "$JAY_NOTES/0000ee01" "$JAY_NOTES/000000x2" "$JAY_RENEWED/000000x3"; do echo note >"$f"; done
touch -t 202609010000 "$JAY_NOTES/000000x1" "$JAY_NOTES/0000ee01" "$JAY_RENEWED/000000x3"
jay_prune_agent_files '[]'
ok "prune: not with an empty agent list" test -f "$JAY_NOTES/000000x1"
jay_prune_agent_files "$(cat "$STUB/agents.json")"
no "prune: an old note of an agent that is gone" test -f "$JAY_NOTES/000000x1"
ok "prune: an old note of a listed agent stays" test -f "$JAY_NOTES/0000ee01"
ok "prune: a new note of an agent that is gone stays" test -f "$JAY_NOTES/000000x2"
no "prune: an old renewed mark of an agent that is gone" test -f "$JAY_RENEWED/000000x3"
ok "prune: the renewed mark of a listed agent stays" test -f "$JAY_RENEWED/0000ee01"

finish
